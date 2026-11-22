import Foundation

/// Counts spoken manuscript content, never titles or pronunciation annotations.
public struct ScriptMetrics: Equatable, Sendable {
    public let characters: Int
    public let words: Int
    public var isEmpty: Bool { characters == 0 && words == 0 }

    public init(text: String) {
        var characters = 0, words = 0, inWord = false
        let scalars = Array(text.unicodeScalars)
        func isHan(_ value: UInt32) -> Bool {
            (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value)
                || (0xF900...0xFAFF).contains(value) || (0x20000...0x323AF).contains(value)
        }
        func isWordLetter(_ scalar: Unicode.Scalar) -> Bool {
            CharacterSet.letters.contains(scalar) && !isHan(scalar.value)
        }
        for (index, scalar) in scalars.enumerated() {
            if isHan(scalar.value) || CharacterSet.decimalDigits.contains(scalar) {
                characters += 1; inWord = false
            } else if isWordLetter(scalar) {
                if !inWord { words += 1 }; inWord = true
            } else if CharacterSet.nonBaseCharacters.contains(scalar), inWord {
                continue
            } else if ["'", "’", "-", "‐", "‑"].contains(String(scalar)), inWord,
                      index + 1 < scalars.count, isWordLetter(scalars[index + 1]) {
                continue
            } else {
                inWord = false
            }
        }
        self.characters = characters; self.words = words
    }

    public func estimatedMinutes(preferences: ReadingPreferences) -> Double {
        var safe = preferences; safe.normalize()
        return Double(characters) / safe.chineseCharactersPerMinute + Double(words) / safe.englishWordsPerMinute
    }

    public enum Duration: Equatable, Sendable {
        case empty, underOneMinute, minutes(Int), range(Int, Int)
    }
    public func duration(preferences: ReadingPreferences) -> Duration {
        guard !isEmpty else { return .empty }
        let minutes = estimatedMinutes(preferences: preferences)
        if minutes < 0.5 { return .underOneMinute }
        if minutes <= 5 { return .minutes(max(1, Int(minutes.rounded()))) }
        return .range(Int((minutes * 0.9).rounded(.down)), Int((minutes * 1.1).rounded(.up)))
    }
}
