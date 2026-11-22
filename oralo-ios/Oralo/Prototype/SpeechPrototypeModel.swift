import AVFoundation
import Observation
import OraloCore
import UIKit

@MainActor
@Observable
final class SpeechPrototypeModel {
    enum SessionSignal {
        case started, recognized(UUID, Bool), interrupted, unavailable, renewing
        case audio(Float, TimeInterval), finalized([FinalSpeechSpan])
    }
    @ObservationIgnored var sessionSignal: ((SessionSignal) -> Void)?

    enum Backend: String, CaseIterable, Identifiable {
        case automatic = "System", compatibility = "Compatibility"
        var id: String { rawValue }
    }

    var localeID = "zh-CN"
    var backend: Backend = .automatic
    private(set) var draft = PrototypeSamples.chinese
    private(set) var follower: FollowEngine
    private(set) var isPreparing = false
    private(set) var isRecording = false
    private(set) var status = "Ready for a test"
    private(set) var lastError: String?
    private(set) var needsModel = false
    private(set) var permissionDenied = false
    private(set) var engineName = "Not started"
    private(set) var transcript = ""
    private(set) var lastTranscriptAt: Date?
    private(set) var audioLevel: Float = 0
    private(set) var audioLevels: [Float] = Array(repeating: 0, count: 23)
    private(set) var automaticMoves = 0
    private(set) var holdReturns = 0
    private(set) var manualSelections = 0
    private(set) var requestStarts = 0
    private(set) var restarts = 0
    private(set) var markedWrongJumps = 0
    private(set) var markedMisses = 0
    private(set) var interruptions = 0
    private(set) var transcriptUpdates = 0
    private(set) var distinctTranscriptUpdates = 0
    private(set) var unmatchedUpdates = 0
    private(set) var pendingMatchUpdates = 0
    private(set) var globalMoves = 0
    private(set) var events: [String] = []
    private(set) var readingPosition = ReadingCursor.Position(cueIndex: 0, characterCount: 0)

    @ObservationIgnored private var capturePolicy: MicrophoneCapture.SessionPolicy = .exclusive
    @ObservationIgnored private var source: (any SpeechSource)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var displayTask: Task<Void, Never>?
    @ObservationIgnored private var cursor = ReadingCursor()
    @ObservationIgnored private var deliveryDelay: TimeInterval = 0.25
    @ObservationIgnored private var deliverySamples: [Double] = []
    @ObservationIgnored private var runID = UUID()
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var requestToken: UUID?
    @ObservationIgnored private var sequence: UInt64 = 0
    @ObservationIgnored private var lastMeterAt = Date.distantPast
    @ObservationIgnored private var lastVoiceAt = Date.distantPast
    @ObservationIgnored private var processingMS: [Double] = []
    @ObservationIgnored private var callbackGaps: [Double] = []
    @ObservationIgnored private var activeSince: Date?
    private(set) var accumulatedSeconds: TimeInterval = 0
    private(set) var testStartedAt: Date?
    @ObservationIgnored private var startBattery: Float?
    @ObservationIgnored private var renewalStartedAt: Date?
    @ObservationIgnored private var longestRenewalGap: TimeInterval = 0

    init() {
        do { follower = try FollowEngine(cues: ScriptCue.parse(PrototypeSamples.chinese)) }
        catch { preconditionFailure("The built-in sample must contain valid cues: \(error)") }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-reading-replay") {
            try? applyScript(Self.layoutTestScript)
        }
        #endif
    }

    /// One saved revision per presentation. The build 5 matching and display paths are reused.
    init(snapshot: ScriptSnapshot, capturePolicy: MicrophoneCapture.SessionPolicy = .exclusive) throws {
        self.capturePolicy = capturePolicy
        follower = try FollowEngine(cues: snapshot.cues)
        draft = snapshot.cues.map(\.text).joined(separator: "\n")
        localeID = snapshot.localeID
        status = "Ready to speak"
    }

    #if DEBUG
    // Deterministic UI-only transcription fixture. Never opens the microphone and cannot
    // measure recognition latency; it exercises the real matcher, cursor and text layout.
    private static let layoutTestScript = """
    大家好今天汇报本季度的团队进展我们会逐步介绍客户反馈交付质量以及接下来需要完成的重点任务希望每个成员都能够清楚了解目标并且一起把计划落实到日常工作之中
    最后重申优先改善交付同时守住质量底线
    谢谢大家接下来欢迎提问和讨论
    """

    func startLayoutReplayIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-reading-replay") else { return }
        follower.resume()
        let token = follower.session.contextToken
        let first = follower.cues[0].text
        let updates = [String(first.prefix(6)), String(first.prefix(36)), first,
                       follower.cues.last!.text, String(first.prefix(12))]
        task = Task { [weak self] in
            for (sequence, text) in updates.enumerated() {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                guard let self else { return }
                self.follower.ingest(text, isFinal: true, token: token, sequence: UInt64(sequence),
                                     observedAt: Date().timeIntervalSinceReferenceDate)
                self.advanceDisplay()
            }
        }
    }
    #endif

    #if DEBUG
    /// Exercises production matching -> session events without microphone or stored transcription.
    /// Only available in isolated UI-test libraries; excluded from Release.
    private func startSessionReplayIfRequested() -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--ui-session-speech-replay"),
              ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-library=") }),
              follower.cues.count > 2 else { return false }
        let generation = UUID(), request = UUID()
        runID = generation
        let opening = follower.cues[0].text, next = follower.cues[2].text
        receive(.started(id: request, engine: "UI fixture · no microphone"))
        if ProcessInfo.processInfo.arguments.contains("--ui-review-observations") {
            task = Task { [weak self] in
                guard let self else { return }
                self.receive(.transcript(id: request, text: opening, isFinal: true, deliveryDelay: nil))
                for (level, count) in [(Float(0.6), 10), (Float(0.02), 100), (Float(0.6), 10)] {
                    for _ in 0..<count {
                        do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                        guard self.runID == generation else { return }
                        self.receive(.level(level, duration: 0.05))
                    }
                }
                self.receive(.finalized(id: request, spans: [
                    FinalSpeechSpan(text: opening, start: 0, end: 0.5),
                    FinalSpeechSpan(text: opening, start: 5.5, end: 6)
                ]))
                self.receive(.transcript(id: request, text: next, isFinal: true, deliveryDelay: nil))
            }
            return true
        }
        let steps: [(Double, String)] = [(0.2, opening), (0.5, "紫色火星山谷中的宇宙旅行"),
            (1.1, "紫色火星山谷中的宇宙旅行者"), (1.1, "紫色火星山谷中的宇宙旅行者正在漫步"), (1.1, next)]
        task = Task { [weak self] in
            for (delay, text) in steps {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, self.runID == generation else { return }
                self.receive(.level(0.5))
                self.receive(.transcript(id: request, text: text, isFinal: true, deliveryDelay: nil))
            }
        }
        return true
    }
    #endif

    var currentIndex: Int { follower.session.currentIndex }
    var busy: Bool { isRecording || isPreparing }

    private func advanceDisplay(at date: Date = .now) {
        cursor.update(engine: follower, at: date.timeIntervalSinceReferenceDate,
                      voiceActive: isRecording && date.timeIntervalSince(lastVoiceAt) < 0.25,
                      deliveryDelay: deliveryDelay)
        if readingPosition != cursor.position { readingPosition = cursor.position }
    }

    private func startDisplayClock() {
        displayTask?.cancel()
        displayTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self else { return }
                self.advanceDisplay()
            }
        }
    }

    func stateLabel(at now: Date) -> String {
        if isPreparing { return status }
        guard isRecording else { return status }
        guard lastTranscriptAt != nil else { return "Listening · position held" }
        if let lastTranscriptAt, now.timeIntervalSince(lastTranscriptAt) > 5 {
            return "Waiting · position held"
        }
        return follower.session.mode == .holding ? "Off-script / uncertain · position held" : "Following your voice"
    }

    func activeSeconds(at now: Date) -> TimeInterval {
        accumulatedSeconds + (activeSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    func start(downloadModels: Bool = false) {
        guard !busy else { return }
        #if DEBUG
        if startSessionReplayIfRequested() { return }
        #endif
        let generation = UUID()
        runID = generation
        lastError = nil
        permissionDenied = false
        needsModel = false
        isPreparing = true
        status = "Preparing…"
        transcript = ""
        lastTranscriptAt = nil
        lastVoiceAt = .distantPast
        let selected: any SpeechSource
        if backend == .automatic, #available(iOS 26, *) {
            selected = ModernSpeechSource(sessionPolicy: capturePolicy)
        } else {
            let terms = CueMatcher.tokens(draft).filter { token in
                token.count >= 3 && token.unicodeScalars.allSatisfy { (97...122).contains($0.value) }
            }
            selected = LegacySpeechSource(vocabulary: Array(Set(terms)).sorted(), sessionPolicy: capturePolicy)
        }
        source = selected
        let locale = Locale(identifier: localeID)
        task = Task { [weak self] in
            do {
                try await selected.run(locale: locale, downloadModels: downloadModels) { [weak self] event in
                    guard let self, self.runID == generation else { return }
                    self.receive(event)
                }
            } catch {
                guard let self, self.runID == generation, !Task.isCancelled else { return }
                self.pause(reason: "Paused · manual selection available")
                self.lastError = error.localizedDescription
                if case SpeechFailure.modelRequired = error { self.needsModel = true }
                if case SpeechFailure.permission = error { self.permissionDenied = true }
                self.sessionSignal?(.unavailable)
                let nsError = error as NSError
                self.log("Error \(nsError.domain) / \(nsError.code)")
            }
        }
    }

    func pause(reason: String = "Paused · position held") {
        runID = UUID() // Invalidate callbacks before cancellation can deliver final results.
        task?.cancel()
        task = nil
        displayTask?.cancel()
        displayTask = nil
        source?.stop()
        source = nil
        endActiveInterval()
        follower.pause()
        requestID = nil
        requestToken = nil
        renewalStartedAt = nil
        isPreparing = false
        isRecording = false
        audioLevel = 0
        audioLevels = Array(repeating: 0, count: 23)
        lastVoiceAt = .distantPast
        status = reason
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func select(_ cue: ScriptCue, resume: Bool? = nil) {
        let shouldResume = resume ?? busy
        pause()
        follower.selectCue(cue.id)
        advanceDisplay()
        manualSelections += 1
        transcript = ""
        lastTranscriptAt = nil
        log("Manual selection → cue \(currentIndex + 1)")
        if shouldResume { start() }
    }

    func interrupt(_ reason: String) {
        guard busy else { return }
        interruptions += 1
        sessionSignal?(.interrupted)
        pause(reason: "Paused · \(reason). Tap Resume when ready.")
        log("Interruption: \(reason)")
    }

    func applyScript(_ text: String) throws {
        guard text.count <= 50_000 else { throw SpeechFailure.unavailable("Keep this prototype script under 50,000 characters.") }
        let cues = ScriptCue.parse(text)
        guard !cues.isEmpty, cues.count <= 500, cues.allSatisfy({ $0.text.count <= 400 }) else {
            throw SpeechFailure.unavailable("Use 1–500 sentences, with no sentence longer than 400 characters. Add punctuation or line breaks to split long passages.")
        }
        let engine = try FollowEngine(cues: cues)
        pause(reason: "Ready for a test")
        draft = text
        follower = engine
        cursor = ReadingCursor()
        advanceDisplay()
        resetMetrics()
        transcript = ""
        lastError = nil
        needsModel = false
        permissionDenied = false
    }

    func resetTest() {
        try? applyScript(draft) // Existing draft already passed the same validation.
    }

    func markWrongJump() { markedWrongJumps += 1; log("Tester marked wrong jump at cue \(currentIndex + 1)") }
    func markMiss() { markedMisses += 1; log("Tester marked missed follow at cue \(currentIndex + 1)") }

    func handleAudioInterruption(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: value) == .began else { return }
        interrupt("audio interrupted")
    }

    func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
              [.oldDeviceUnavailable, .newDeviceAvailable, .noSuitableRouteForCategory, .override].contains(reason) else { return }
        interrupt("microphone route changed")
    }

    var report: String {
        let sorted = processingMS.sorted()
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]
        let gaps = callbackGaps.sorted()
        let gapP95 = gaps.isEmpty ? 0 : gaps[min(gaps.count - 1, Int(Double(gaps.count - 1) * 0.95))]
        let delays = deliverySamples.sorted()
        let delayNote = delays.isEmpty ? "Unavailable (no valid active-speech time codes)"
            : "\(delays[min(delays.count - 1, Int(Double(delays.count - 1) * 0.95))].formatted(.number.precision(.fractionLength(2)))) s / \(delays.count) samples"
        let battery = UIDevice.current.batteryLevel
        let batteryNote: String
        if let startBattery, startBattery >= 0, battery >= 0 {
            batteryNote = "\(Int(startBattery * 100))% → \(Int(battery * 100))% (charging state: \(UIDevice.current.batteryState.rawValue))"
        } else { batteryNote = "Unavailable" }
        return """
        Oralo voice-following prototype / build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")
        Generated: \(Date().ISO8601Format())
        Device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion) (add exact model when sharing)
        Engine: \(engineName); locale: \(localeID)
        Active microphone time: \(Int(activeSeconds(at: .now))) s
        Current cue: \(currentIndex + 1) / \(follower.cues.count)
        Recognition requests: \(requestStarts); automatic renewals/retries: \(restarts)
        Longest measured renewal gap: \(longestRenewalGap.formatted(.number.precision(.fractionLength(2)))) s (request lifecycle only)
        Automatic position changes: \(automaticMoves)
        Whole-script relocations: \(globalMoves)
        Transcript callbacks: \(transcriptUpdates); changed text: \(distinctTranscriptUpdates)
        Changed-text outcomes: no match / ambiguous \(unmatchedUpdates); pending confirmation \(pendingMatchUpdates)
        Callback interval P95: \(gapP95.formatted(.number.precision(.fractionLength(2)))) s (includes pauses; not speech latency)
        Audio-tail age P95: \(delayNote) (input timeline minus latest word end; estimate, not measured highlight latency)
        Hold → match transitions: \(holdReturns) (not a verified recovery success rate)
        Manual selections: \(manualSelections)
        Tester-marked wrong jumps: \(markedWrongJumps); missed follows: \(markedMisses)
        Interruptions: \(interruptions)
        Match processing P95: \(p95.formatted(.number.precision(.fractionLength(2)))) ms (last \(sorted.count) updates; not end-to-end speech latency)
        Battery: \(batteryNote); thermal state: \(ProcessInfo.processInfo.thermalState.rawValue)
        Policy: latest-word anchor; nearby +3 responsive; whole-script fresh-evidence recovery; ambiguous evidence holds. Chinese numbers and common fillers normalized.
        Display: upper-third actual-line anchor; bounded delivery-delay compensation + pace estimate ≤0.9 s, ≤6 Han tokens / 2 English words; freezes after 1 s without advancing matches, on silence or off-script. May preview only the next cue; recognized position stays evidence-based.
        Raw audio is not saved. Script and transcription are excluded from this report.
        Recent events (max 40):
        \(events.joined(separator: "\n"))
        """
    }

    private func receive(_ event: SpeechEvent) {
        switch event {
        case .preparing(let message): status = message
        case .started(let id, let engine):
            if let renewalStartedAt {
                longestRenewalGap = max(longestRenewalGap, Date().timeIntervalSince(renewalStartedAt))
            }
            renewalStartedAt = nil
            follower.pause()
            follower.resume()
            requestID = id
            requestToken = follower.session.contextToken
            sequence = 0
            deliveryDelay = 0.25
            transcript = ""
            lastTranscriptAt = nil
            lastVoiceAt = .distantPast
            engineName = engine
            requestStarts += 1
            isPreparing = false
            isRecording = true
            advanceDisplay()
            startDisplayClock()
            status = "Listening · position held"
            activeSince = .now
            if testStartedAt == nil {
                testStartedAt = .now
                UIDevice.current.isBatteryMonitoringEnabled = true
                startBattery = UIDevice.current.batteryLevel
            }
            UIApplication.shared.isIdleTimerDisabled = true
            log("Recognition started at cue \(currentIndex + 1)")
            sessionSignal?(.started)
        case .transcript(let id, let text, let isFinal, let measuredDelay):
            guard id == requestID, let token = requestToken, isRecording else { return }
            let oldIndex = currentIndex
            let oldMode = follower.session.mode
            let changed = text != transcript
            if changed, Date().timeIntervalSince(lastVoiceAt) < 0.25,
               let measuredDelay, measuredDelay.isFinite, (0...5).contains(measuredDelay) {
                deliverySamples.append(measuredDelay)
                if deliverySamples.count > 300 { deliverySamples.removeFirst() }
                // Bound the estimate: a stale recognizer must never run the script away.
                deliveryDelay = min(0.8, measuredDelay) * 0.6 + deliveryDelay * 0.4
            }
            transcriptUpdates += 1
            if changed { distinctTranscriptUpdates += 1 }
            if let lastTranscriptAt {
                callbackGaps.append(Date().timeIntervalSince(lastTranscriptAt))
                if callbackGaps.count > 300 { callbackGaps.removeFirst() }
            }
            transcript = text
            lastTranscriptAt = .now
            let start = ContinuousClock.now
            follower.ingest(text, isFinal: isFinal, token: token, sequence: sequence,
                            observedAt: Date().timeIntervalSinceReferenceDate)
            sequence += 1
            advanceDisplay()
            let duration = start.duration(to: .now).components
            processingMS.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            if processingMS.count > 300 { processingMS.removeFirst() }
            if changed {
                if follower.lastMatch == nil { unmatchedUpdates += 1 }
                else if follower.session.mode == .holding { pendingMatchUpdates += 1 }
            }
            if currentIndex != oldIndex, follower.lastMatch?.isRecovery == true { globalMoves += 1 }
            if currentIndex != oldIndex { automaticMoves += 1; log("Auto cue \(oldIndex + 1) → \(currentIndex + 1)") }
            if oldMode == .holding, follower.session.mode == .following { holdReturns += 1 }
            sessionSignal?(.recognized(follower.session.currentCueID, follower.session.mode == .holding))
        case .finalized(let id, let spans):
            guard id == requestID, isRecording else { return }
            sessionSignal?(.finalized(spans))
        case .level(let value, let duration):
            guard isRecording else { return }
            sessionSignal?(.audio(value, duration))
            if value > 0.2 { lastVoiceAt = .now }
            guard Date().timeIntervalSince(lastMeterAt) >= 0.1 else { return }
            lastMeterAt = .now
            audioLevel = value
            audioLevels.removeFirst()
            audioLevels.append(value)
        case .restarting(let message):
            sessionSignal?(.renewing)
            displayTask?.cancel()
            displayTask = nil
            endActiveInterval()
            follower.pause()
            requestID = nil
            requestToken = nil
            restarts += 1
            if renewalStartedAt == nil { renewalStartedAt = .now }
            isRecording = false
            audioLevel = 0
            audioLevels = Array(repeating: 0, count: 23)
            isPreparing = true
            status = message
            log("Compatibility recognition renewal / retry")
        }
    }

    private func endActiveInterval() {
        if let activeSince { accumulatedSeconds += Date().timeIntervalSince(activeSince) }
        activeSince = nil
    }

    private func resetMetrics() {
        automaticMoves = 0; holdReturns = 0; manualSelections = 0; requestStarts = 0
        restarts = 0; markedWrongJumps = 0; markedMisses = 0; interruptions = 0
        transcriptUpdates = 0; distinctTranscriptUpdates = 0; unmatchedUpdates = 0; pendingMatchUpdates = 0; globalMoves = 0
        accumulatedSeconds = 0; testStartedAt = nil; startBattery = nil; processingMS = []; events = []
        renewalStartedAt = nil; longestRenewalGap = 0
        callbackGaps = []
        deliverySamples = []; deliveryDelay = 0.25
        engineName = "Not started"
    }

    private func log(_ text: String) {
        events.append("\(Int(activeSeconds(at: .now)))s · \(text)")
        if events.count > 40 { events.removeFirst(events.count - 40) }
    }
}
