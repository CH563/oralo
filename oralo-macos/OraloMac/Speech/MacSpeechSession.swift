import AppKit
import Foundation
import Observation
import OraloCore

enum PromptMode: String, CaseIterable, Identifiable {
    case voice, manual, fixed
    var id: Self { self }
    var title: String { switch self {
    case .voice: MacCopy.text("语音", "Voice")
    case .manual: MacCopy.text("手动", "Manual")
    case .fixed: MacCopy.text("定速", "Paced")
    } }
}

/// One session is shared by the reader and floating window. Window lifecycle never owns capture.
@MainActor @Observable
final class MacSpeechSession {
    let snapshot: ScriptSnapshot
    let recorder: RehearsalRecorder?
    private(set) var mode: PromptMode
    private(set) var playing = false
    var fixedSpeed = 1.0
    @ObservationIgnored private let paceTimeline: FloatingReadingTimeline
    @ObservationIgnored private let spans: [(UUID, NSRange)]
    @ObservationIgnored private var paceProgress = FloatingReadingProgress()
    @ObservationIgnored private var lastPaceTick = 0.0
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    private(set) var follower: FollowEngine
    private(set) var readingPosition = ReadingCursor.Position(cueIndex: 0, characterCount: 0)
    private(set) var preparing = false
    private(set) var recording = false
    private(set) var levels: [Float] = Array(repeating: 0, count: 23)
    private(set) var status = MacCopy.text("已暂停 · 可手动选句", "Paused · select a sentence")
    private(set) var error: String?
    private(set) var needsModel = false
    var compatibility = false
    @ObservationIgnored private var source: (any SpeechSource)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var displayTask: Task<Void, Never>?
    @ObservationIgnored private var cursor = ReadingCursor()
    @ObservationIgnored private var runID = UUID()
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var token: UUID?
    @ObservationIgnored private var sequence: UInt64 = 0
    @ObservationIgnored private var lastVoice = Date.distantPast
    @ObservationIgnored private var lastMeter = Date.distantPast
    @ObservationIgnored private var transcript = ""
    @ObservationIgnored private var deliveryDelay = 0.25
    var busy: Bool { preparing || recording || playing }
    var currentIndex: Int { follower.session.currentIndex }
    init(snapshot: ScriptSnapshot, document: ScriptDocument? = nil, mode: PromptMode = .voice,
         preferences: MacPreferences? = nil, recorder: RehearsalRecorder? = nil) throws {
        self.snapshot = snapshot; self.mode = mode; self.recorder = recorder
        let document = document ?? ScriptDocument(text: snapshot.cues.map(\.text).joined(separator: "\n"))
        paceTimeline = FloatingReadingTimeline(document: document, chineseRate: preferences?.chineseRate ?? 240, englishRate: preferences?.englishRate ?? 140)
        spans = document.segmentSpans()
        fixedSpeed = preferences?.fixedSpeed ?? 1
        follower = try FollowEngine(cues: snapshot.cues)
        sleepTask = Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.willSleepNotification) {
                guard let self, !Task.isCancelled else { return }
                self.pause()
            }
        }
    }
    func end() { pause(); sleepTask?.cancel(); sleepTask = nil }
    func changeMode(_ value: PromptMode) {
        guard mode != value else { return }
        let resume = busy
        pause(); mode = value
        if value != .voice, recorder?.record != nil {
            recorder?.switchToManual(cueID: snapshot.cues[currentIndex].id)
            if !resume { recorder?.pause() }
        }
        seekPace()
        if resume { start() }
    }
    private func seekPace() {
        if spans.indices.contains(currentIndex) { paceProgress.seek(offset: spans[currentIndex].1.location, timeline: paceTimeline) }
    }
    private func startWithoutMicrophone() {
        playing = true
        recorder?.startOrResume(cueID: snapshot.cues[currentIndex].id)
        status = mode == .fixed ? MacCopy.text("定速滚动 · 麦克风关闭", "Paced scrolling · microphone off") : MacCopy.text("手动提词 · 麦克风关闭", "Manual · microphone off")
        guard mode == .fixed else { return }
        paceProgress.play(timeline: paceTimeline)
        if !paceProgress.isPlaying { playing = false; recorder?.pause(); return }
        lastPaceTick = ProcessInfo.processInfo.systemUptime
        displayTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                self?.advancePace()
            }
        }
    }
    private func advancePace() {
        guard playing, mode == .fixed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        paceProgress.advance(delta: now - lastPaceTick, speed: fixedSpeed, timeline: paceTimeline)
        lastPaceTick = now
        let offset = paceTimeline.offset(at: paceProgress.elapsed)
        if let index = spans.lastIndex(where: { $0.1.location <= offset }), snapshot.cues.indices.contains(index) {
            if currentIndex != index { follower.selectCue(snapshot.cues[index].id) }
            let range = spans[index].1
            let local = min(range.length, max(0, offset - range.location))
            let text = snapshot.cues[index].text as NSString
            let prefix = text.substring(to: min(local, text.length))
            readingPosition = ReadingCursor.Position(cueIndex: index, characterCount: prefix.count)
        }
        if !paceProgress.isPlaying { pause() }
    }
    func start(downloadModels: Bool = false) {
        guard !busy else { return }
        error = nil; needsModel = false
        if mode != .voice { startWithoutMicrophone(); return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-silent") { return }
        #endif
        let generation = UUID(); runID = generation
        preparing = true
        status = MacCopy.text("准备设备端识别…", "Preparing on-device recognition…")
        let selected: any SpeechSource
        if !compatibility, #available(macOS 26, *) { selected = ModernSpeechSource() }
        else {
            let terms = CueMatcher.tokens(snapshot.cues.map(\.text).joined(separator: " ")).filter {
                $0.count >= 3 && $0.unicodeScalars.allSatisfy { (97...122).contains($0.value) }
            }
            selected = LegacySpeechSource(vocabulary: Array(Set(terms)).sorted())
        }
        source = selected
        task = Task { [weak self] in
            do {
                try await selected.run(locale: Locale(identifier: self?.snapshot.localeID ?? "en-US"), downloadModels: downloadModels) { [weak self] event in
                    guard let self, self.runID == generation else { return }
                    self.receive(event)
                }
            } catch {
                guard let self, self.runID == generation, !Task.isCancelled else { return }
                self.pause()
                self.error = MacCopy.error(error)
                if case SpeechFailure.modelRequired = error { self.needsModel = true }
            }
        }
    }
    func pause() {
        recorder?.pause(); paceProgress.pause(); playing = false
        runID = UUID()
        task?.cancel(); task = nil
        displayTask?.cancel(); displayTask = nil
        source?.stop(); source = nil
        follower.pause(); requestID = nil; token = nil
        preparing = false; recording = false
        levels = Array(repeating: 0, count: 23)
        lastVoice = .distantPast
        status = MacCopy.text("已暂停 · 位置已保留", "Paused · position held")
    }
    func toggle() { if busy { pause() } else { start() } }
    func select(index: Int, reason: RehearsalEvent.Kind = .selection) {
        guard snapshot.cues.indices.contains(index) else { return }
        let resume = busy
        pause(); follower.selectCue(snapshot.cues[index].id)
        recorder?.move(to: snapshot.cues[index].id, reason: reason)
        advanceDisplay(); seekPace()
        if resume { start() }
    }
    func pickUp() { select(index: currentIndex) }
    func advanceDisplay(at date: Date = .now) {
        cursor.update(engine: follower, at: date.timeIntervalSinceReferenceDate,
            voiceActive: recording && date.timeIntervalSince(lastVoice) < 0.25, deliveryDelay: deliveryDelay)
        if readingPosition != cursor.position { readingPosition = cursor.position }
    }
    // Same evidence gate, timing, EMA delay bound and 50 ms display cadence as build 14.
    func receive(_ event: SpeechEvent) {
        switch event {
        case .preparing(let message): status = MacCopy.text(message)
        case .started(let id, _):
            follower.pause(); follower.resume()
            requestID = id; token = follower.session.contextToken; sequence = 0
            transcript = ""; deliveryDelay = 0.25; lastVoice = .distantPast
            preparing = false; recording = true
            recorder?.startVoiceRequest(cueID: snapshot.cues[currentIndex].id)
            status = MacCopy.text("正在聆听 · 位置保留", "Listening · position held")
            advanceDisplay()
            displayTask?.cancel()
            displayTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                    self?.advanceDisplay()
                }
            }
        case .transcript(let id, let text, let final, let delay):
            guard id == requestID, let token, recording else { return }
            if text != transcript, Date().timeIntervalSince(lastVoice) < 0.25,
               let delay, delay.isFinite, (0...5).contains(delay) {
                deliveryDelay = min(0.8, delay) * 0.6 + deliveryDelay * 0.4
            }
            transcript = text
            let previous = currentIndex
            follower.ingest(text, isFinal: final, token: token, sequence: sequence, observedAt: Date().timeIntervalSinceReferenceDate)
            sequence += 1; advanceDisplay()
            recorder?.observe(cueID: snapshot.cues[currentIndex].id, holding: follower.session.mode == .holding)
            status = follower.session.mode == .holding ? MacCopy.text("自由发挥 · 保持位置", "Off-script · position held")
                : MacCopy.text("跟随你的声音", "Following your voice")
            if previous != currentIndex, snapshot.pauseAfter.contains(snapshot.cues[previous].id) { pause() }
        case .level(let value, let duration):
            guard recording else { return }
            recorder?.observeAudio(level: value, duration: duration)
            if value > 0.2 { lastVoice = .now }
            if Date().timeIntervalSince(lastMeter) >= 0.1 {
                lastMeter = .now; levels.removeFirst(); levels.append(value)
            }
        case .restarting(let message):
            recorder?.pause(interrupted: true)
            follower.pause(); recording = false; preparing = true
            requestID = nil; token = nil; status = MacCopy.text(message)
            displayTask?.cancel(); displayTask = nil
            levels = Array(repeating: 0, count: 23)
        case .finalized(let id, let spans):
            if id == requestID, recording { recorder?.observeFinalized(spans) }
        }
    }
}
