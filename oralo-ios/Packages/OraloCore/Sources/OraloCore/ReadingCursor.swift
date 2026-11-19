import Foundation

/// A display position, deliberately separate from FollowSession's recognized anchor.
public struct ReadingCursor: Sendable {
    public struct Position: Sendable, Equatable, Comparable {
        public let cueIndex: Int
        public let characterCount: Int

        public init(cueIndex: Int, characterCount: Int) {
            self.cueIndex = cueIndex
            self.characterCount = characterCount
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.cueIndex == rhs.cueIndex ? lhs.characterCount < rhs.characterCount : lhs.cueIndex < rhs.cueIndex
        }
    }

    public private(set) var position = Position(cueIndex: 0, characterCount: 0)
    private var anchorIndex: Int?
    private var context: UUID?

    public init() {}

    public mutating func update(engine: FollowEngine, at time: TimeInterval, voiceActive: Bool,
                                deliveryDelay: TimeInterval = 0.25) {
        let index = engine.session.currentIndex
        let confirmed = Position(cueIndex: index, characterCount: engine.reading.confirmedCharacterCount)
        if context != engine.session.contextToken || (anchorIndex != index && position.cueIndex != index) {
            position = confirmed
        } else {
            position = max(position, confirmed)
        }
        context = engine.session.contextToken
        anchorIndex = index
        guard engine.session.mode == .following, voiceActive else { return }
        let lead = engine.reading.predictedLead(at: time, deliveryDelay: deliveryDelay)
        guard lead > 0 else { return } // Freeze the visible cursor; never flash back on timeout/silence.

        var targetIndex = index
        var progress = engine.reading
        var end = progress.confirmedTokenCount
        var englishWords = 0
        for step in 0..<lead {
            if end == progress.tokens.count {
                // Preview only the immediate next sentence. Never skip a cue on a timer.
                guard targetIndex == index, targetIndex + 1 < engine.cues.count else { break }
                targetIndex += 1
                progress = ReadingProgress(text: engine.cues[targetIndex].text)
                end = 0
            }
            guard end < progress.tokens.count else { break }
            let token = progress.tokens[end].value
            let han = token.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0x20000...0x3134F).contains($0.value) }
            if !han {
                // A Chinese projection stops at a language/number boundary; English gets ≤2 words.
                if step > 0 && englishWords == 0 { break }
                englishWords += 1
                if englishWords > 2 || (token.hasPrefix("#") && step > 0) { break }
            } else if englishWords > 0 { break }
            end += 1
            position = max(position, Position(cueIndex: targetIndex, characterCount: progress.characterEnd(for: end)))
            if token.hasPrefix("#") { break }
        }
    }
}
