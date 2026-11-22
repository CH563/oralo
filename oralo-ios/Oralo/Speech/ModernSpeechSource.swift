import AVFoundation
import OraloCore
import Speech

@available(iOS 26, *)
@MainActor
final class ModernSpeechSource: SpeechSource {
    private let microphone: MicrophoneCapture
    init(sessionPolicy: MicrophoneCapture.SessionPolicy = .exclusive) {
        microphone = MicrophoneCapture(sessionPolicy: sessionPolicy)
    }
    private var download: AssetInstallationRequest?
    private var input: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
    private var capturedSeconds: TimeInterval = 0

    func run(locale: Locale, downloadModels: Bool,
             event: @escaping @MainActor @Sendable (SpeechEvent) -> Void) async throws {
        defer { stop() }
        event(.preparing("Checking on-device speech support…"))
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechFailure.unavailable("This device or language does not support the new speech model. Try Compatibility mode, or use manual cue selection.")
        }
        try Task.checkCancellation()
        // Keep progressive/time-indexed output and ask for responsive partials. Apple documents
        // a speed/accuracy tradeoff for fastResults; alignment still rejects ambiguous jumps.
        var preset = SpeechTranscriber.Preset.timeIndexedProgressiveTranscription
        preset.reportingOptions.insert(.fastResults)
        let transcriber = SpeechTranscriber(locale: supported, preset: preset)
        let status = await AssetInventory.status(forModules: [transcriber])
        try Task.checkCancellation()
        if status != .installed {
            guard status != .unsupported else {
                throw SpeechFailure.unavailable("The speech model is unavailable for this language on this device.")
            }
            guard downloadModels else { throw SpeechFailure.modelRequired }
            event(.preparing("Downloading speech model… You can cancel and use manual mode."))
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try Task.checkCancellation()
                download = request
                try await request.downloadAndInstall()
                download = nil
            }
        }
        try Task.checkCancellation()
        event(.preparing("Preparing microphone…"))
        try await MicrophoneCapture.authorize()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw CaptureFailure.conversion
        }
        try Task.checkCancellation()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        try Task.checkCancellation()
        let converter = SpeechAudioConverter(destination: format)
        capturedSeconds = 0
        let (inputs, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingNewest(16))
        input = continuation
        let chunks = try microphone.start()
        let requestID = UUID()
        event(.started(id: requestID, engine: "SpeechAnalyzer · fast partials · on-device"))

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.feed(chunks, converter: converter, output: continuation, event: event)
            }
            group.addTask {
                _ = try await analyzer.analyzeSequence(inputs)
            }
            group.addTask {
                try await self.read(transcriber, requestID: requestID, event: event)
            }
            do {
                try await group.next()
                throw SpeechFailure.ended
            } catch {
                group.cancelAll()
                microphone.stop()
                continuation.finish()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        }
    }

    private func feed(_ chunks: AsyncThrowingStream<PCMChunk, Error>, converter: SpeechAudioConverter,
                      output: AsyncThrowingStream<AnalyzerInput, Error>.Continuation,
                      event: @escaping @MainActor @Sendable (SpeechEvent) -> Void) async throws {
        for try await chunk in chunks {
            try Task.checkCancellation()
            event(.level(chunk.level, duration: Double(chunk.samples.count) / chunk.sampleRate))
            if let buffer = try converter.convert(chunk) {
                capturedSeconds += Double(buffer.frameLength) / buffer.format.sampleRate
                if case .dropped = output.yield(AnalyzerInput(buffer: buffer)) {
                    throw CaptureFailure.overloaded
                }
            }
        }
    }

    private func read(_ transcriber: SpeechTranscriber, requestID: UUID,
                      event: @escaping @MainActor @Sendable (SpeechEvent) -> Void) async throws {
        var window = TranscriptWindow()
        for try await result in transcriber.results {
            try Task.checkCancellation()
            if let text = window.replace(start: result.range.start.seconds, end: result.range.end.seconds,
                                         text: String(result.text.characters)) {
                let audioEnd = result.text.runs.compactMap { $0.audioTimeRange?.end.seconds }.last
                let delay = result.range.end.seconds >= window.latestEnd
                    ? audioEnd.map { capturedSeconds - $0 } : nil
                // A finalized older range must not confirm a newer, still-volatile transcript tail.
                event(.transcript(id: requestID, text: text,
                                  isFinal: result.isFinal && result.range.end.seconds >= window.latestEnd,
                                  deliveryDelay: delay))
            }
            if result.isFinal {
                let spans = result.text.runs.compactMap { run -> FinalSpeechSpan? in
                    guard let range = run.audioTimeRange else { return nil }
                    return FinalSpeechSpan(text: String(result.text[run.range].characters),
                                           start: range.start.seconds, end: range.end.seconds)
                }
                event(.finalized(id: requestID, spans: spans.isEmpty
                    ? [FinalSpeechSpan(text: String(result.text.characters), start: result.range.start.seconds, end: result.range.end.seconds)]
                    : spans))
            }
        }
    }

    func stop() {
        download?.progress.cancel()
        download = nil
        microphone.stop()
        input?.finish()
        input = nil
    }
}
