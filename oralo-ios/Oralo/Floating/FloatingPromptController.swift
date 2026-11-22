import AVKit
import Observation
import OraloCore
import SwiftUI

@MainActor @Observable final class FloatingPromptController: NSObject,
    @preconcurrency AVPictureInPictureControllerDelegate {
    enum Mode: String, Codable, CaseIterable { case fixed, voice }
    enum VoiceState { case paused, preparing, listening, holding, interrupted, unavailable }
    enum State { case idle, ready, starting, floating, stopping, unavailable, failed }
    private struct Preferences: Codable {
        var speed = 1.0, scale = 1.0, chineseRate = 240.0, englishRate = 140.0
        var mode: Mode?
    }
    private struct Checkpoint: Codable {
        let revision: Int
        let offset: Int
    }
    static let preferencesKey = "floating.preferences.v1"
    static let positionsKey = "floating.positions.v1"
    private(set) var state = State.idle
    private(set) var mode = Mode.fixed
    private(set) var voiceState = VoiceState.paused
    private(set) var needsModel = false
    private(set) var useCompatibility = false
    private(set) var diagnosticEvents: [String] = []
    @ObservationIgnored private var voice: FloatingSpeechSession?
    @ObservationIgnored private var openAfterVoiceStarts = false
    private(set) var document: ScriptDocument?
    private(set) var isPlaying = false
    private(set) var offset = 0
    private(set) var message: String?
    private(set) var speed = 1.0
    private(set) var scale = 1.0
    private(set) var versionChanged = false
    let surface = FloatingSurfaceView()
    @ObservationIgnored private var liveContent: FloatingContentController?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    private(set) var countdown: Int?
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startTimeout: Task<Void, Never>?
    @ObservationIgnored private var renderer: FloatingFrameRenderer?
    @ObservationIgnored private var timeline: FloatingReadingTimeline?
    @ObservationIgnored private var progress = FloatingReadingProgress()
    @ObservationIgnored private var preferences = Preferences()
    @ObservationIgnored private let defaults = ReadingPreferencesStore.defaults
    @ObservationIgnored private var checkpoints: [String: Checkpoint] = [:]
    @ObservationIgnored private var lastTick = 0.0
    @ObservationIgnored private var lastFrame = 0.0
    @ObservationIgnored private var lastSave = 0.0
    @ObservationIgnored private var lastRenderRecovery = 0.0
    @ObservationIgnored private var audioBufferCount = 0
    @ObservationIgnored private var ownsAudio = false
    @ObservationIgnored private var startRequested = false
    @ObservationIgnored private var previewVisible = false
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var validate: (() -> Bool)?
    @ObservationIgnored var didReturn: ((Int) -> Void)?
    var supported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }
    var hasEnded: Bool { mode == .fixed && (timeline.map { progress.elapsed >= $0.duration } ?? false) }
    var isOpen: Bool { state == .floating || state == .starting || state == .stopping }

    override init() {
        super.init()
        if let data = defaults.data(forKey: Self.preferencesKey), let value = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = value
        } else {
            preferences.chineseRate = ReadingPreferencesStore.shared.value.chineseCharactersPerMinute
            preferences.englishRate = ReadingPreferencesStore.shared.value.englishWordsPerMinute
        }
        preferences.speed = preferences.speed.isFinite ? min(2, max(0.5, preferences.speed)) : 1
        preferences.scale = preferences.scale.isFinite ? min(1.4, max(0.8, preferences.scale)) : 1
        speed = preferences.speed; scale = preferences.scale; mode = preferences.mode ?? .fixed
        if let data = defaults.data(forKey: Self.positionsKey) { checkpoints = (try? JSONDecoder().decode([String: Checkpoint].self, from: data)) ?? [:] }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(foregrounded), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(mediaReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    private func t(_ zh: String, _ en: String) -> String { AppCopy.bilingual(zh, en) }

    func prepare(_ saved: ScriptDocument, initialOffset: Int? = nil, validate: @escaping () -> Bool) {
        if document == saved, timeline != nil {
            self.validate = validate
            if let initialOffset { seek(initialOffset) }
            showPreview(); return
        }
        end()
        self.validate = validate; document = saved; versionChanged = false; message = nil
        audioBufferCount = 0; diagnosticEvents = []
        let timeline = FloatingReadingTimeline(document: saved, chineseRate: preferences.chineseRate, englishRate: preferences.englishRate)
        self.timeline = timeline; progress = FloatingReadingProgress()
        if let initialOffset { progress.seek(offset: initialOffset, timeline: timeline) }
        else if let checkpoint = checkpoints[saved.id.uuidString] {
            if checkpoint.revision == saved.revision { progress.seek(offset: checkpoint.offset, timeline: timeline) }
            else { versionChanged = true }
        }
        offset = timeline.offset(at: progress.elapsed)
        renderer = FloatingFrameRenderer(); renderer?.configure(document: saved, scale: scale)
        // Every text frame uses DisplayImmediately. Apple explicitly advises
        // against combining that attachment with a non-nil control timebase.
        surface.displayLayer.controlTimebase = nil
        configureController()
        state = supported ? .ready : .unavailable
        showPreview(); savePreferences()
    }

    private func configureController() {
        if supported {
            let content = FloatingContentController()
            liveContent = content
            let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: surface, contentViewController: content)
            let pip = AVPictureInPictureController(contentSource: source)
            pip.delegate = self; pip.canStartPictureInPictureAutomaticallyFromInline = false
            controller = pip
            possibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.startIfReady() }
            }
        }
    }

    func showPreview() { previewVisible = true; lastTick = CACurrentMediaTime(); startTimer(); draw(force: true) }
    func hidePreview() {
        previewVisible = false
        if !isOpen { pause(); timer?.invalidate(); timer = nil }
    }
    func setMode(_ value: Mode) {
        guard !isOpen, mode != value else { return }
        pause(); mode = value; preferences.mode = value; message = nil; needsModel = false
        voiceState = .paused; savePreferences(); draw(force: true)
    }
    var voiceStatusText: String {
        switch voiceState {
        case .paused: t("已暂停 · 语音跟随", "Paused · Voice follow")
        case .preparing: t("正在准备语音…", "Preparing speech…")
        case .listening: t("语音跟随 · 正在收音", "Voice follow · Listening")
        case .holding: t("自由发挥 · 停在原句", "Off-script · Position held")
        case .interrupted: t("收音中断 · 停在原句", "Microphone interrupted · Position held")
        case .unavailable: t("语音不可用 · 停在原句", "Speech unavailable · Position held")
        }
    }
    var diagnosticReport: String {
        "Oralo PiP / iOS \(UIDevice.current.systemVersion) / build \(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?")\nMode: \(mode.rawValue)\nState: \(state) / \(voiceState)\nAudio buffers: \(audioBufferCount)\nNo script, audio or transcript included.\n" + diagnosticEvents.joined(separator: "\n")
    }
    private func log(_ event: String) {
        diagnosticEvents.append("\(Int(CACurrentMediaTime())) \(event)")
        if diagnosticEvents.count > 40 { diagnosticEvents.removeFirst(diagnosticEvents.count - 40) }
    }
    func setSpeed(_ value: Double) {
        guard value.isFinite else { return }
        speed = min(2, max(0.5, value)); preferences.speed = speed; savePreferences(); lastTick = CACurrentMediaTime()
    }
    func setScale(_ value: Double) {
        guard value.isFinite, let document else { return }
        scale = min(1.4, max(0.8, value)); preferences.scale = scale
        renderer?.configure(document: document, scale: scale); savePreferences(); draw(force: true)
    }
    func togglePreview() { isPlaying || voiceState == .preparing ? pause() : play() }
    private func play() {
        guard validate?() == true, let timeline else { return }
        if mode == .voice { startVoice(); return }
        progress.play(timeline: timeline); isPlaying = progress.isPlaying
        lastTick = CACurrentMediaTime(); startTimer()
    }
    func pause() {
        countdownTask?.cancel(); countdownTask = nil; countdown = nil
        openAfterVoiceStarts = false
        voice?.stop(); voice = nil; voiceState = .paused
        progress.pause(); isPlaying = false; lastTick = CACurrentMediaTime()
        if !isOpen { releaseAudio() }
        savePosition(); draw(force: true)
    }
    func seek(_ position: Int) {
        guard let timeline else { return }
        progress.seek(offset: max(0, position), timeline: timeline)
        offset = timeline.offset(at: progress.elapsed); pause()
    }

    func startPictureInPicture() {
        guard supported, controller != nil, validate?() == true, timeline?.units.isEmpty == false else { return }
        guard !isOpen else { return }
        message = nil
        if mode == .voice {
            if voice?.model.isRecording == true { beginNativeWindow() }
            else { openAfterVoiceStarts = true; startVoice() }
        } else { pause(); beginNativeWindow() }
    }
    private func configureAudio() throws {
        let audio = AVAudioSession.sharedInstance()
        if mode == .voice {
            try audio.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
        } else {
            try audio.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try audio.setActive(true); ownsAudio = true
    }
    private func beginNativeWindow() {
        guard validate?() == true else { end(save: false); return }
        do {
            if !ownsAudio { try configureAudio() }
        } catch {
            state = .failed
            message = t("暂时无法准备小窗，请在通话或录制结束后重试。阅读位置已保留。", "Could not prepare the floating prompt. Try again after the call or recording. Your position is kept.")
            return
        }
        state = .starting; log("pip.start.request"); startTimer(); draw(force: true)
        let id = sessionID
        startTimeout?.cancel()
        startTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.sessionID == id, self.state == .starting else { return }
            self.failStart()
        }
        startIfReady()
    }
    func retryVoice(downloadModels: Bool = false, compatibility: Bool = false) {
        guard mode == .voice, !isOpen else { return }
        pause(); useCompatibility = compatibility; startVoice(downloadModels: downloadModels)
    }
    private func startVoice(downloadModels: Bool = false) {
        guard mode == .voice, voice == nil, validate?() == true, let document else { return }
        // Start microphone capture while foregrounded. Never fight another app's
        // recording session with background activation/retry loops.
        guard UIApplication.shared.applicationState == .active else {
            interruptVoice(); return
        }
        do {
            try configureAudio()
            let session = try FloatingSpeechSession(document: document, offset: offset, compatibility: useCompatibility)
            voice = session; voiceState = .preparing; needsModel = false; message = nil
            log("voice.prepare"); startTimer()
            session.signal = { [weak self, weak session] signal in
                guard let self, let session, self.voice === session else { return }
                switch signal {
                case .started:
                    self.voiceState = .listening; self.isPlaying = true
                    self.log("voice.started")
                    if self.openAfterVoiceStarts { self.openAfterVoiceStarts = false; self.beginNativeWindow() }
                case .recognized(_, let holding): self.voiceState = holding ? .holding : .listening
                case .unavailable:
                    let needsModel = session.model.needsModel
                    let error = session.model.lastError.map(AppCopy.text)
                    self.pause(); self.needsModel = needsModel; self.voiceState = .unavailable
                    self.message = error; self.log("voice.unavailable"); self.draw(force: true)
                case .renewing: self.voiceState = .preparing; self.log("voice.renewing")
                case .audio: self.audioBufferCount += 1
                default: break
                }
            }
            session.start(downloadModels: downloadModels)
        } catch {
            pause(); voiceState = .unavailable; message = AppCopy.error(error); log("voice.prepare.failed")
        }
    }
    private func interruptVoice() {
        guard mode == .voice else { return }
        pause(); voiceState = .interrupted
        message = t("收音被中断，位置已保留。返回 Oralo 后可重试语音跟随，或选择定速滚动。", "Microphone input was interrupted. Your position is kept. Return to Oralo to retry voice following or choose fixed pace.")
        log("voice.interrupted"); draw(force: true)
    }
    private func startIfReady() {
        guard state == .starting, let controller, controller.isPictureInPicturePossible,
              !controller.isPictureInPictureActive, !startRequested, validate?() == true else { return }
        startRequested = true
        controller.startPictureInPicture()
    }
    private func failStart() {
        startTimeout?.cancel(); state = .failed; pause(); releaseAudio()
        // Retire this attempt so a late callback cannot affect a later retry.
        possibleObservation = nil
        controller?.delegate = nil; controller?.stopPictureInPicture(); controller?.contentSource = nil; controller = nil
        startRequested = false
        configureController()
        message = t("系统暂未开启小窗。请检查设备的画中画设置，保持预览可见后重试。", "The system did not open Picture in Picture. Check its device setting, keep this preview visible, then retry.")
    }
    func closeWindow() {
        startTimeout?.cancel(); pause()
        if controller?.isPictureInPictureActive == true {
            state = .stopping
            controller?.stopPictureInPicture()
        } else {
            state = supported ? .ready : .unavailable
        }
        releaseAudio()
    }
    /// Release all snapshot and frame references before another audio session or deletion.
    func end(save: Bool = true) {
        if save { savePosition() }
        sessionID = UUID(); startRequested = false; startTimeout?.cancel(); startTimeout = nil
        openAfterVoiceStarts = false; voice?.stop(); voice = nil; voiceState = .paused
        progress.pause(); isPlaying = false
        timer?.invalidate(); timer = nil; possibleObservation = nil
        controller?.delegate = nil; controller?.stopPictureInPicture(); controller?.contentSource = nil; controller = nil
        countdownTask?.cancel(); countdownTask = nil; countdown = nil
        liveContent?.surface.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true); liveContent = nil
        releaseAudio(); surface.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true)
        renderer?.clear(); renderer = nil; document = nil; timeline = nil; validate = nil; didReturn = nil
        state = .idle; offset = 0; previewVisible = false
    }
    func removeData(_ operation: LocalDataRemoval.Operation) {
        switch operation {
        case .all:
            end(save: false); checkpoints = [:]
            defaults.removeObject(forKey: Self.positionsKey); defaults.removeObject(forKey: Self.preferencesKey)
            preferences = Preferences(); speed = 1; scale = 1; mode = .fixed
            diagnosticEvents = []; message = nil; needsModel = false; useCompatibility = false
        case .script(let id):
            if document?.id == id { end(save: false) }
            checkpoints[id.uuidString] = nil; writePositions()
        case .rehearsals: break
        }
    }
    func prune(liveIDs: Set<UUID>) {
        checkpoints = checkpoints.filter { UUID(uuidString: $0.key).map(liveIDs.contains) == true }
        writePositions()
    }
    private func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.preferencesKey) }
    }
    private func savePosition() {
        guard validate?() == true, let document, timeline != nil else { return }
        checkpoints[document.id.uuidString] = Checkpoint(revision: document.revision, offset: offset)
        writePositions()
    }
    private func writePositions() {
        if let data = try? JSONEncoder().encode(checkpoints) { defaults.set(data, forKey: Self.positionsKey) }
    }
    private func releaseAudio() {
        guard ownsAudio else { return }; ownsAudio = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
    private func startTimer() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func tick() {
        let now = CACurrentMediaTime(), delta = now - lastTick; lastTick = now
        guard let timeline else { return }
        guard validate?() == true else { end(save: false); return }
        let visible = UIApplication.shared.applicationState == .active && previewVisible || state == .floating
        if visible {
            if mode == .voice {
                if let voice, voice.model.isRecording {
                    if now - voice.lastAudioAt > 2.5 { interruptVoice() }
                    else if let position = voice.offset {
                        offset = position
                        progress.seek(offset: position, timeline: timeline)
                    }
                }
            } else {
                progress.advance(delta: delta, speed: speed, timeline: timeline)
                offset = timeline.offset(at: progress.elapsed)
                if isPlaying != progress.isPlaying { isPlaying = progress.isPlaying; savePosition() }
            }
            draw(force: isPlaying)
            if now - lastSave >= 3 { lastSave = now; savePosition() }
        }
    }
    private func draw(force: Bool) {
        let now = CACurrentMediaTime()
        guard force || now - lastFrame >= 1, let timeline,
              let frame = renderer?.frame(elapsed: progress.elapsed, timeline: timeline, timestamp: now,
                  voiceOffset: mode == .voice ? offset : nil, caption: countdown.map { t("\($0) 秒后开始", "Starting in \($0)…") } ?? (mode == .voice ? voiceStatusText : nil)) else { return }
        let display = surface.displayLayer.sampleBufferRenderer
        if display.status == .failed || display.requiresFlushToResumeDecoding {
            guard now - lastRenderRecovery >= 1 else { return }
            lastRenderRecovery = now
            let code = (display.error as NSError?)?.code ?? 0
            log("render.flush.\(code)")
            display.flush()
        }
        if display.isReadyForMoreMediaData { display.enqueue(frame); lastFrame = now }
        if let liveContent {
            let target = liveContent.surface.displayLayer.sampleBufferRenderer
            if target.status == .failed { target.flush() }
            if target.isReadyForMoreMediaData { target.enqueue(frame) }
        }
    }
    @objc private func backgrounded() {
        log("app.background.audioBuffers.\(audioBufferCount)")
        if !isOpen { pause() }
    }
    @objc private func foregrounded() {
        if document != nil {
            log("app.foreground")
            log("render.ready.\(liveContent?.surface.displayLayer.isReadyForDisplay ?? surface.displayLayer.isReadyForDisplay).audioBuffers.\(audioBufferCount).voice.\(voiceState)")
        }
        if state == .floating { pause(); closeWindow(); didReturn?(offset) }
        lastTick = CACurrentMediaTime()
    }
    @objc private func interrupted(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: value) == .began else { return }
        guard document != nil else { return }
        log("audio.interruption.began")
        // Silent manuscript frames do not depend on audio playback. Keep the
        // window and fixed pace alive; only microphone-driven progress stops.
        if mode == .voice, voice != nil { interruptVoice() }
    }
    @objc private func routeChanged(_ notification: Notification) {
        guard document != nil,
              let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: value) else { return }
        log("audio.route.\(value)")
        if voice != nil, [.oldDeviceUnavailable, .noSuitableRouteForCategory].contains(reason) { interruptVoice() }
    }
    @objc private func mediaReset() {
        guard document != nil else { return }; end(); state = .failed
        message = t("系统媒体服务已重置，请关闭此页后重试。位置已保留。", "Media services restarted. Reopen this page to retry. Your position is kept.")
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pip: AVPictureInPictureController) {
        guard pip === controller, state == .starting else { pip.stopPictureInPicture(); return }
        startTimeout?.cancel(); state = .floating; log("pip.started")
        if mode == .fixed {
            let id = sessionID
            countdownTask = Task { [weak self] in
                for seconds in (1...3).reversed() {
                    guard let self, self.sessionID == id, self.state == .floating else { return }
                    self.countdown = seconds; self.draw(force: true)
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
                guard let self, self.sessionID == id, self.state == .floating else { return }
                self.countdown = nil; self.countdownTask = nil; self.play(); self.draw(force: true)
            }
        }
        draw(force: true)
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pip: AVPictureInPictureController) {
        guard pip === controller else { return }
        log("pip.stopped"); startRequested = false; pause(); releaseAudio(); state = .ready
        didReturn?(offset)
        if !previewVisible { timer?.invalidate(); timer = nil }
    }
    func pictureInPictureController(_ pip: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        guard pip === controller else { return }
        let failure = error as NSError
        log("pip.failed.\(failure.domain).\(failure.code)"); failStart()
    }
    func pictureInPictureController(_ pip: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        guard pip === controller else { completionHandler(false); return }
        pause(); didReturn?(offset); completionHandler(true)
    }
}

final class FloatingSurfaceView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    override init(frame: CGRect) { super.init(frame: frame); displayLayer.videoGravity = .resizeAspect; backgroundColor = .black }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
}

struct FloatingPreview: UIViewRepresentable {
    let controller: FloatingPromptController
    func makeUIView(context: Context) -> FloatingSurfaceView { controller.surface }
    func updateUIView(_ view: FloatingSurfaceView, context: Context) {}
}
