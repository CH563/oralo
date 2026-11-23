import AVFoundation

nonisolated struct PCMChunk: Sendable {
    let samples: [Float]
    let sampleRate: Double
    var level: Float {
        guard !samples.isEmpty else { return 0 }
        let power = samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count)
        return min(1, max(0, (20 * log10(max(sqrt(power), 0.00001)) + 60) / 60))
    }
}

nonisolated enum CaptureFailure: Error, LocalizedError {
    case unavailable, overloaded, conversion, changed
    var errorDescription: String? {
        switch self {
        case .unavailable: "The microphone is unavailable. Check the system input device and resume."
        case .overloaded: "Audio processing fell behind. Your position is held; resume to retry."
        case .conversion: "The microphone format could not be converted."
        case .changed: "The audio device changed. Your position is held; check the system input and resume."
        }
    }
}

/// macOS Core Audio capture. Does not change the default device or a meeting app's audio session.
@MainActor final class MicrophoneCapture {
    enum SessionPolicy { case exclusive, externallyManaged }
    private var engine: AVAudioEngine?
    private var hasTap = false
    private var continuation: AsyncThrowingStream<PCMChunk, Error>.Continuation?
    private var configurationObserver: NSObjectProtocol?
    init(sessionPolicy: SessionPolicy = .exclusive) {}

    static func authorize() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw SpeechFailure.permission("Enable microphone access for Oralo in System Settings → Privacy & Security → Microphone, or use manual mode.")
        }
        try Task.checkCancellation()
    }

    func start() throws -> AsyncThrowingStream<PCMChunk, Error> {
        stop()
        let engine = AVAudioEngine()
        self.engine = engine
        do {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else { throw CaptureFailure.unavailable }
            let (stream, output) = AsyncThrowingStream<PCMChunk, Error>.makeStream(bufferingPolicy: .bufferingNewest(16))
            continuation = output
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
                guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
                let samples = Array(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
                if case .dropped = output.yield(PCMChunk(samples: samples, sampleRate: buffer.format.sampleRate)) {
                    output.finish(throwing: CaptureFailure.overloaded)
                }
            }
            hasTap = true
            engine.prepare()
            try engine.start()
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                object: engine, queue: nil) { _ in output.finish(throwing: CaptureFailure.changed) }
            return stream
        } catch { stop(); throw error }
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.stop()
        if hasTap { engine?.inputNode.removeTap(onBus: 0); hasTap = false }
        continuation?.finish(); continuation = nil
        engine = nil
    }

    static func buffer(for chunk: PCMChunk) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: chunk.sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw CaptureFailure.conversion }
        buffer.frameLength = buffer.frameCapacity
        chunk.samples.withUnsafeBufferPointer { samples in
            if let base = samples.baseAddress { channel.update(from: base, count: samples.count) }
        }
        return buffer
    }
}

@MainActor final class SpeechAudioConverter {
    private var converter: AVAudioConverter?
    private let destination: AVAudioFormat
    init(destination: AVAudioFormat) { self.destination = destination }
    func convert(_ chunk: PCMChunk) throws -> AVAudioPCMBuffer? {
        let input = try MicrophoneCapture.buffer(for: chunk)
        if input.format == destination { return input }
        if converter?.inputFormat != input.format { converter = AVAudioConverter(from: input.format, to: destination) }
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: destination,
            frameCapacity: AVAudioFrameCount(ceil(Double(input.frameLength) * destination.sampleRate / chunk.sampleRate)) + 64)
        else { throw CaptureFailure.conversion }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard !supplied else { inputStatus.pointee = .noDataNow; return nil }
            supplied = true; inputStatus.pointee = .haveData; return input
        }
        if let error { throw error }
        guard status != .error else { throw CaptureFailure.conversion }
        return output.frameLength > 0 ? output : nil
    }
}
