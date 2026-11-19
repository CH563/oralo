import Foundation

/// UTF-16 coordinates match UITextView without adding reading text to the manuscript.
public struct TextSpan: Codable, Equatable, Sendable {
    public var location: Int
    public var length: Int
    public var nsRange: NSRange { NSRange(location: location, length: length) }
    public init(_ range: NSRange) { location = range.location; length = range.length }
    public func isValid(in text: String) -> Bool {
        location >= 0 && length > 0 && location <= text.utf16.count && length <= text.utf16.count - location
            && Range(nsRange, in: text) != nil
    }
}

public struct Pronunciation: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case pinyin, ipa }
    public let id: UUID
    public var span: TextSpan?
    public var term: String
    public var reading: String
    public var kind: Kind
    public var referenceReading: String?
    public var source: String
    public var showInPresentation: Bool
    public var context: String
    public var needsReview: Bool { span == nil }
    public var isCustom: Bool { referenceReading != reading }

    public init(id: UUID = UUID(), span: TextSpan, term: String, reading: String, kind: Kind,
                referenceReading: String? = nil, source: String = "manual", showInPresentation: Bool = true,
                context: String = "") {
        self.id = id; self.span = span; self.term = term; self.reading = reading; self.kind = kind
        self.referenceReading = referenceReading; self.source = source
        self.showInPresentation = showInPresentation; self.context = context
    }

    public func isAnchored(in text: String) -> Bool {
        guard let span, span.isValid(in: text), let range = Range(span.nsRange, in: text) else { return false }
        return String(text[range]) == term
    }

    /// An edit overlapping a term invalidates that occurrence. Never relocate by searching
    /// for the same spelling: it may be a different occurrence with a different reading.
    public mutating func migrate(replacing edit: NSRange, with replacement: String) {
        guard var span else { return }
        let end = NSMaxRange(edit), termEnd = NSMaxRange(span.nsRange)
        if end <= span.location {
            span.location += replacement.utf16.count - edit.length
            self.span = span
        } else if edit.location < termEnd {
            self.span = nil
        }
    }
}

public enum PronunciationError: LocalizedError {
    case invalidSelection, overlap, invalidReading, splitInsideReading
    public var errorDescription: String? {
        switch self {
        case .invalidSelection: "Select up to 40 characters within one sentence."
        case .overlap: "This selection overlaps an existing pronunciation. Edit or remove that hint first."
        case .invalidReading: "Enter a reading of 1–80 characters on one line."
        case .splitInsideReading: "Move the break outside the annotated word, or remove its reading first."
        }
    }
}

public extension ScriptDocument {
    func pronunciation(at range: NSRange) -> Pronunciation? {
        pronunciations.first { $0.span.map { NSIntersectionRange($0.nsRange, range).length > 0 } ?? false }
    }

    func pronunciationSelection(_ range: NSRange) throws -> String {
        let span = TextSpan(range)
        guard span.isValid(in: text), let swiftRange = Range(range, in: text) else { throw PronunciationError.invalidSelection }
        let term = String(text[swiftRange])
        guard term.count <= 40, !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !term.contains(where: { $0.isNewline }),
              segmentSpans().contains(where: { NSIntersectionRange($0.1, range) == range }) else {
            throw PronunciationError.invalidSelection
        }
        return term
    }

    mutating func setPronunciation(_ value: Pronunciation) throws {
        let reading = value.reading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reading.isEmpty, reading.count <= 80, !reading.contains(where: { $0.isNewline }) else {
            throw PronunciationError.invalidReading
        }
        guard value.isAnchored(in: text), let span = value.span else { throw PronunciationError.invalidSelection }
        _ = try pronunciationSelection(span.nsRange)
        guard !pronunciations.contains(where: {
            $0.id != value.id && $0.span.map { NSIntersectionRange($0.nsRange, span.nsRange).length > 0 } == true
        }) else { throw PronunciationError.overlap }
        var saved = value; saved.reading = reading
        pronunciations.removeAll { $0.id == value.id }
        pronunciations.append(saved)
    }

    mutating func removePronunciation(_ id: UUID) { pronunciations.removeAll { $0.id == id } }

    /// Segment IDs may change after edits; snapshot projection always uses the original
    /// manuscript coordinates. Splits and merges don't duplicate or change a reading.
    func segmentSpans() -> [(UUID, NSRange)] {
        var offset = text.startIndex
        return segments.compactMap { segment in
            guard let range = text.range(of: segment.text, range: offset..<text.endIndex) else { return nil }
            offset = range.upperBound
            return (segment.id, NSRange(range, in: text))
        }
    }

    func presentationPronunciations() -> [UUID: [Pronunciation]] {
        var result: [UUID: [Pronunciation]] = [:]
        for (id, cueRange) in segmentSpans() {
            for reading in pronunciations where reading.showInPresentation && reading.isAnchored(in: text) {
                guard let span = reading.span, NSIntersectionRange(cueRange, span.nsRange) == span.nsRange else { continue }
                var local = reading
                local.span = TextSpan(NSRange(location: span.location - cueRange.location, length: span.length))
                result[id, default: []].append(local)
            }
        }
        return result
    }
}
