import AVFoundation
import Observation

@MainActor @Observable
final class PronunciationPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var playing = false
    private(set) var error: String?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var current: ObjectIdentifier?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    var available: Bool { AVSpeechSynthesisVoice(language: "en-US") != nil }

    override init() {
        super.init()
        synthesizer.delegate = self
        // A system-managed playback session avoids changing the microphone's session.
        synthesizer.usesApplicationAudioSession = false
    }

    func play(_ term: String) {
        stop(); error = nil
        guard let voice = AVSpeechSynthesisVoice(language: "en-US") else {
            error = PronunciationCopy.text("美式语音暂不可用，仍可保存音标。", "US voice unavailable. You can still save the reading.")
            return
        }
        let utterance = AVSpeechUtterance(string: term)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        current = ObjectIdentifier(utterance)
        playing = true
        synthesizer.speak(utterance)
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.playing else { return }
            self.stop()
            self.error = PronunciationCopy.text("试听未完成，请重试。读音仍可保存。", "Playback did not finish. Try again; your reading can still be saved.")
        }
    }

    func stop() {
        timeout?.cancel(); timeout = nil
        current = nil; playing = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }
    private nonisolated func finished(_ id: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, self.current == id else { return }
            self.timeout?.cancel(); self.timeout = nil
            self.current = nil; self.playing = false
        }
    }
}
