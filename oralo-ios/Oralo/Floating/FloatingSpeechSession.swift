import AVFoundation
import OraloCore

/// Adapts the existing recognition/matching/cursor pipeline to original script
/// positions. No separate matcher, cloud service or transcript persistence.
@MainActor final class FloatingSpeechSession {
    let model: SpeechPrototypeModel
    private let positions: FloatingSpeechPosition
    var signal: ((SpeechPrototypeModel.SessionSignal) -> Void)?
    private(set) var lastAudioAt = CACurrentMediaTime()
    private(set) var receivedTranscript = false

    init(document: ScriptDocument, offset: Int, compatibility: Bool) throws {
        model = try SpeechPrototypeModel(snapshot: document.snapshot(), capturePolicy: .externallyManaged)
        positions = FloatingSpeechPosition(document: document)
        if compatibility { model.backend = .compatibility }
        let spans = document.segmentSpans()
        if let index = spans.lastIndex(where: { $0.1.location <= offset }), model.follower.cues.indices.contains(index) {
            model.select(model.follower.cues[index], resume: false)
        }
        model.sessionSignal = { [weak self] signal in
            guard let self else { return }
            switch signal {
            case .audio: self.lastAudioAt = CACurrentMediaTime()
            case .recognized: self.receivedTranscript = true
            case .started: self.lastAudioAt = CACurrentMediaTime()
            default: break
            }
            self.signal?(signal)
        }
    }
    var offset: Int? {
        guard receivedTranscript else { return nil }
        return positions.offset(cueIndex: model.readingPosition.cueIndex,
                                charactersRead: model.readingPosition.characterCount)
    }
    func start(downloadModels: Bool) { model.start(downloadModels: downloadModels) }
    func stop() { signal = nil; model.sessionSignal = nil; model.pause() }
}
