import Foundation

extension RehearsalSnapshot {
    /// A literal, unique occurrence is safe to emphasize in the read-only initial draft.
    /// Do not fuzzy-match rewritten or repeated passages to an arbitrary occurrence.
    public func originalRange(cueID: UUID) -> TextSpan? {
        guard let original = document.originalText,
              let segment = document.segments.first(where: { $0.id == cueID }),
              !segment.text.isEmpty else { return nil }
        if original == document.text {
            return document.segmentSpans().first(where: { $0.0 == cueID }).map { TextSpan($0.1) }
        }
        let source = original as NSString
        let first = source.range(of: segment.text, options: .literal)
        guard first.location != NSNotFound else { return nil }
        let remaining = NSRange(location: first.location + 1, length: source.length - first.location - 1)
        guard source.range(of: segment.text, options: .literal, range: remaining).location == NSNotFound else { return nil }
        // Also refuse ambiguity introduced into the speaking version.
        guard document.segments.filter({ $0.text == segment.text }).count == 1 else { return nil }
        return TextSpan(first)
    }
}
