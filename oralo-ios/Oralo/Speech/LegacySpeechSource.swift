import AVFoundation
import OraloCore
import Speech

nonisolated private struct LegacySnapshot: Sendable {
    let text: String
    let isFinal: Bool
    let audioEnd: TimeInterval?
    let finalizedSpans: [FinalSpeechSpan]
}

/// Explicit on-device-only path. Short recognition requests are renewed without replaying old text.
@MainActor
final class LegacySpeechSource: SpeechSource {
    private let vocabulary: [String]
    private let microphone: MicrophoneCapture
    private var recognitionTask: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var output: AsyncThrowingStream<LegacySnapshot, Error>.Continuation?
    private var capturedSeconds: TimeInterval = 0

    init(vocabulary: [String] = [], sessionPolicy: MicrophoneCapture.SessionPolicy = .exclusive) {
        self.vocabulary = Array(vocabulary.prefix(100))
        microphone = MicrophoneCapture(sessionPolicy: sessionPolicy)
    }

    func run(locale: Locale, downloadModels: Bool,
             event: @escaping @MainActor @Sendable (SpeechEvent) -> Void) async throws {
        defer { stop() }
        event(.preparing("Checking compatibility speech recognition…"))
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
        }
        try Task.checkCancellation()
        guard authorization == .authorized else {
            throw SpeechFailure.permission("Speech recognition access is off. Enable it in Settings, or use manual cue selection.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw SpeechFailure.unavailable("On-device recognition is unavailable for this device or language. No audio will be sent to a server; manual cue selection is available.")
        }
        // Apple's default is the main queue. Copy snapshots on a dedicated serial queue so
        // text layout and scrolling cannot delay the recognition callback itself.
        let callbackQueue = OperationQueue()
        callbackQueue.name = "Oralo.speech-results"
        callbackQueue.qualityOfService = .userInitiated
        callbackQueue.maxConcurrentOperationCount = 1
        recognizer.queue = callbackQueue
        try await MicrophoneCapture.authorize()
        var consecutiveFailures = 0
        while !Task.isCancelled {
            do {
                try await runSegment(recognizer: recognizer, event: event)
                consecutiveFailures = 0
                try Task.checkCancellation()
                event(.restarting("Renewing compatibility recognition…"))
            } catch {
                try Task.checkCancellation()
                consecutiveFailures += 1
                guard consecutiveFailures <= 2 else { throw error }
                event(.restarting("Recognition interrupted. Retrying (\(consecutiveFailures)/2)…"))
                try await Task.sleep(for: .milliseconds(600))
            }
        }
        throw CancellationError()
    }

    private func runSegment(recognizer: SFSpeechRecognizer,
                            event: @escaping @MainActor @Sendable (SpeechEvent) -> Void) async throws {
        defer { stop() }
        try Task.checkCancellation()
        guard recognizer.isAvailable else { throw SpeechFailure.ended }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.contextualStrings = vocabulary
        self.request = request
        capturedSeconds = 0
        let (results, continuation) = AsyncThrowingStream<LegacySnapshot, Error>.makeStream(bufferingPolicy: .bufferingNewest(32))
        output = continuation
        recognitionTask = recognizer.recognitionTask(with: request) { @Sendable result, error in
            if let result {
                // Preserve formatting/word boundaries. Partial segment time ranges are not
                // needed to select the newest text and must not filter out in-flight words.
                let text = String(result.bestTranscription.formattedString.suffix(768))
                let segment = result.bestTranscription.segments.last
                let audioEnd = segment.flatMap { $0.duration > 0 ? $0.timestamp + $0.duration : nil }
                let spans = result.isFinal ? result.bestTranscription.segments.suffix(256).map {
                    FinalSpeechSpan(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
                } : []
                if case .dropped = continuation.yield(LegacySnapshot(text: text, isFinal: result.isFinal, audioEnd: audioEnd, finalizedSpans: spans)) {
                    continuation.finish(throwing: CaptureFailure.overloaded)
                }
                if result.isFinal { continuation.finish(); return }
            }
            if let error { continuation.finish(throwing: error) }
        }
        let chunks = try microphone.start()
        let requestID = UUID()
        event(.started(id: requestID, engine: "SFSpeechRecognizer · on-device"))
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.feed(chunks, event: event)
            }
            group.addTask {
                try await self.read(results, requestID: requestID, event: event)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(55))
            }
            do {
                try await group.next()
                group.cancelAll()
                stop()
            } catch {
                group.cancelAll()
                stop()
                throw error
            }
        }
    }

    private func feed(_ chunks: AsyncThrowingStream<PCMChunk, Error>,
                      event: @escaping @MainActor @Sendable (SpeechEvent) -> Void) async throws {
        guard let request else { throw SpeechFailure.ended }
        for try await chunk in chunks {
            try Task.checkCancellation()
            request.append(try MicrophoneCapture.buffer(for: chunk))
            capturedSeconds += Double(chunk.samples.count) / chunk.sampleRate
            event(.level(chunk.level, duration: Double(chunk.samples.count) / chunk.sampleRate))
        }
        throw SpeechFailure.ended
    }

    private func read(_ results: AsyncThrowingStream<LegacySnapshot, Error>, requestID: UUID,
                      event: @escaping @MainActor @Sendable (SpeechEvent) -> Void) async throws {
        for try await result in results {
            try Task.checkCancellation()
            let delay = result.audioEnd.map { capturedSeconds - $0 }
            event(.transcript(id: requestID, text: result.text, isFinal: result.isFinal, deliveryDelay: delay))
            if result.isFinal { event(.finalized(id: requestID, spans: result.finalizedSpans)) }
        }
    }

    func stop() {
        microphone.stop()
        request?.endAudio()
        request = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        output?.finish()
        output = nil
    }
}
