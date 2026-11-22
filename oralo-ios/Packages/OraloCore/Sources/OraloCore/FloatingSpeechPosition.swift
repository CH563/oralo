import Foundation

/// Maps the shared reading cursor (graphemes within a cue) back into the saved
/// manuscript (UTF-16). Pronunciation hints never enter this coordinate space.
public struct FloatingSpeechPosition: Sendable {
    private let passages: [(String, NSRange)]
    public init(document: ScriptDocument) {
        let text = document.text as NSString
        passages = document.segmentSpans().map { (_, range) in (text.substring(with: range), range) }
    }
    public func offset(cueIndex: Int, charactersRead: Int) -> Int? {
        guard passages.indices.contains(cueIndex) else { return nil }
        let (text, range) = passages[cueIndex]
        // Anchor the most recently spoken character, including at line endings.
        let count = min(max(1, charactersRead) - 1, max(0, text.count - 1))
        return range.location + text.prefix(count).utf16.count
    }
}
