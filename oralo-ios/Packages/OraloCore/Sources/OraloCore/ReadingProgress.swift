import Foundation

/// Display-only progress. A short visual lead can never change the recognized cue or mark it read.
public struct ReadingProgress: Sendable {
    public let tokens: [CueMatcher.TextToken]
    public let characterCount: Int
    public private(set) var confirmedTokenCount = 0
    public private(set) var lastAdvanceTime: TimeInterval?
    public private(set) var tokensPerSecond: Double
    private let hasHan: Bool

    public init(text: String, initialRate: Double? = nil) {
        tokens = CueMatcher.tokenize(text)
        characterCount = text.count
        hasHan = text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0x20000...0x3134F).contains($0.value) }
        tokensPerSecond = min(hasHan ? 8 : 4, max(1, initialRate ?? (hasHan ? 4.5 : 2.4)))
    }

    public var fraction: Double {
        tokens.isEmpty ? 0 : Double(confirmedTokenCount) / Double(tokens.count)
    }

    public var confirmedCharacterCount: Int { characterEnd(for: confirmedTokenCount) }

    public mutating func suspendPrediction() { lastAdvanceTime = nil }

    public mutating func observe(tokenEnd: Int, at time: TimeInterval) {
        let end = min(tokens.count, max(0, tokenEnd))
        guard time.isFinite, lastAdvanceTime.map({ time >= $0 }) ?? true,
              end > confirmedTokenCount else { return }
        if let previous = lastAdvanceTime {
            let elapsed = time - previous
            if elapsed >= 0.08 && elapsed <= 2 {
                let measured = min(hasHan ? 8 : 4, max(1, Double(end - confirmedTokenCount) / elapsed))
                tokensPerSecond = tokensPerSecond * 0.7 + measured * 0.3
            }
        }
        confirmedTokenCount = end
        lastAdvanceTime = time
    }

    /// Include bounded recognition delivery delay, rather than starting the visual clock
    /// only when an already-late callback arrives. This is estimation, never recognition.
    public func predictedLead(at time: TimeInterval, deliveryDelay: TimeInterval = 0.25) -> Int {
        guard time.isFinite, deliveryDelay.isFinite, confirmedTokenCount > 0,
              let lastAdvanceTime, time >= lastAdvanceTime, time - lastAdvanceTime <= 1 else { return 0 }
        let duration = min(0.9, max(0, min(0.8, deliveryDelay)) + time - lastAdvanceTime)
        return min(hasHan ? 6 : 2, Int(duration * tokensPerSecond))
    }

    public func displayedTokenCount(at time: TimeInterval, microphoneActive: Bool, allowPrediction: Bool,
                                   deliveryDelay: TimeInterval = 0.25) -> Int {
        guard allowPrediction, microphoneActive else { return confirmedTokenCount }
        let lead = predictedLead(at: time, deliveryDelay: deliveryDelay)
        var end = confirmedTokenCount
        for _ in 0..<lead where end < tokens.count {
            let token = tokens[end].value
            let isHan = token.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0x20000...0x3134F).contains($0.value) }
            // A mixed-language cue must not treat English words as Han characters.
            if !isHan && hasHan { return end == confirmedTokenCount ? end + 1 : end }
            end += 1
        }
        return end
    }

    public func characterEnd(for tokenCount: Int) -> Int {
        let count = min(tokens.count, max(0, tokenCount))
        guard count > 0 else { return 0 }
        return count == tokens.count ? characterCount : tokens[count - 1].characters.upperBound
    }
}
