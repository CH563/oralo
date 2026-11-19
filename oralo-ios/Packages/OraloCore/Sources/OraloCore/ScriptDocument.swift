import Foundation

public struct ScriptSegment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public var pauseAfter: Bool
    public var separatorAfter: String

    public init(id: UUID = UUID(), text: String, pauseAfter: Bool = false, separatorAfter: String = "") {
        self.id = id; self.text = text; self.pauseAfter = pauseAfter; self.separatorAfter = separatorAfter
    }
}

/// The original is retained separately; sentence boundaries never change the spoken words.
public struct ScriptDocument: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public private(set) var originalText: String?
    public private(set) var text: String
    public private(set) var segments: [ScriptSegment]
    public private(set) var hasCustomLayout = false
    public internal(set) var pronunciations: [Pronunciation] = []
    public var localeID: String
    public internal(set) var revision: Int
    public let createdAt: Date
    public internal(set) var updatedAt: Date

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled script" : trimmed
    }

    public init(id: UUID = UUID(), title: String = "Untitled script", text: String = "",
                localeID: String = "zh-CN", now: Date = .now) {
        self.id = id; self.title = title; self.text = text
        originalText = text.isEmpty ? nil : text
        segments = Self.parseSegments(text)
        self.localeID = localeID; revision = 0; createdAt = now; updatedAt = now
    }

    public mutating func captureOriginalIfNeeded() {
        if originalText == nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            originalText = text
        }
    }

    public mutating func replaceText(_ value: String) {
        guard value != text else { return }
        // Whole-document replacements have no reliable occurrence identity. Exact editor
        // operations use applyTextEdit instead; retain uncertain hints for review.
        for index in pronunciations.indices { pronunciations[index].span = nil }
        text = value
        rebuildSentences()
    }

    public mutating func applyTextEdit(_ range: NSRange, replacement: String) throws {
        guard range.location >= 0, range.length >= 0, range.location <= text.utf16.count,
              range.length <= text.utf16.count - range.location, let swiftRange = Range(range, in: text) else {
            throw PronunciationError.invalidSelection
        }
        let value = text.replacingCharacters(in: swiftRange, with: replacement)
        guard value != text else { return }
        for index in pronunciations.indices { pronunciations[index].migrate(replacing: range, with: replacement) }
        text = value
        rebuildSentences()
    }

    public mutating func rebuildSentences() {
        let parsed = Self.parseSegments(text)
        // Preserve unchanged sentences, including repeated sentences, in sequence order.
        let difference = parsed.map(\.text).difference(from: segments.map(\.text))
        let removed = Set(difference.compactMap { change -> Int? in
            if case .remove(let offset, _, _) = change { return offset }; return nil
        })
        let inserted = Set(difference.compactMap { change -> Int? in
            if case .insert(let offset, _, _) = change { return offset }; return nil
        })
        var retained = segments.enumerated().filter { !removed.contains($0.offset) }.map(\.element).makeIterator()
        segments = parsed.enumerated().map { index, cue in
            if !inserted.contains(index), let old = retained.next() {
                return ScriptSegment(id: old.id, text: cue.text, separatorAfter: cue.separatorAfter)
            }
            return cue
        }
        hasCustomLayout = false
    }

    public mutating func split(_ id: UUID, at characterOffset: Int) throws {
        guard let index = segments.firstIndex(where: { $0.id == id }),
              characterOffset > 0, characterOffset < segments[index].text.count else {
            throw ScriptLibraryError.invalidSplit
        }
        let old = segments[index]
        let boundary = old.text.index(old.text.startIndex, offsetBy: characterOffset)
        if let (_, global) = segmentSpans().first(where: { $0.0 == id }) {
            let position = global.location + old.text[..<boundary].utf16.count
            if pronunciations.contains(where: { reading in
                guard let span = reading.span else { return false }
                return position > span.location && position < NSMaxRange(span.nsRange)
            }) { throw PronunciationError.splitInsideReading }
        }
        let left = String(old.text[..<boundary]), right = String(old.text[boundary...])
        guard !left.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !right.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ScriptLibraryError.invalidSplit }
        segments.replaceSubrange(index...index, with: [ScriptSegment(id: old.id, text: left),
                                                       ScriptSegment(text: right, pauseAfter: old.pauseAfter, separatorAfter: old.separatorAfter)])
        hasCustomLayout = true
    }

    public mutating func mergeWithNext(_ id: UUID) {
        guard let index = segments.firstIndex(where: { $0.id == id }), index + 1 < segments.count else { return }
        let next = segments[index + 1]
        segments[index].text += segments[index].separatorAfter + next.text
        segments[index].pauseAfter = next.pauseAfter
        segments[index].separatorAfter = next.separatorAfter
        segments.remove(at: index + 1)
        hasCustomLayout = true
    }

    public mutating func togglePause(_ id: UUID) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[index].pauseAfter.toggle()
        hasCustomLayout = true
    }

    /// Editing state may advance while a disk save is in flight; only adopt its metadata.
    public mutating func adoptSaveMetadata(from saved: ScriptDocument) {
        revision = saved.revision; updatedAt = saved.updatedAt
        if let original = saved.originalText { originalText = original }
    }

    private static func parseSegments(_ text: String) -> [ScriptSegment] {
        var result: [ScriptSegment] = []
        var previousEnd = text.startIndex
        for cue in ScriptCue.parse(text) {
            if let range = text.range(of: cue.text, range: previousEnd..<text.endIndex) {
                if !result.isEmpty { result[result.count - 1].separatorAfter = String(text[previousEnd..<range.lowerBound]) }
                previousEnd = range.upperBound
            }
            result.append(ScriptSegment(id: cue.id, text: cue.text))
        }
        return result
    }

    public func snapshot() throws -> ScriptSnapshot {
        guard !segments.isEmpty else { throw ScriptLibraryError.emptyScript }
        guard text.count <= 50_000, segments.count <= 500,
              segments.allSatisfy({ $0.text.count <= 400 }) else { throw ScriptLibraryError.speakingLimit }
        return ScriptSnapshot(scriptID: id, revision: revision, title: displayTitle, localeID: localeID,
                              cues: segments.map { ScriptCue(id: $0.id, text: $0.text) },
                              pauseAfter: Set(segments.filter(\.pauseAfter).map(\.id)),
                              pronunciations: presentationPronunciations())
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, originalText, text, segments, hasCustomLayout, pronunciations, localeID, revision, createdAt, updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        originalText = try values.decodeIfPresent(String.self, forKey: .originalText)
        text = try values.decode(String.self, forKey: .text)
        segments = try values.decode([ScriptSegment].self, forKey: .segments)
        hasCustomLayout = try values.decode(Bool.self, forKey: .hasCustomLayout)
        pronunciations = try values.decodeIfPresent([Pronunciation].self, forKey: .pronunciations) ?? []
        localeID = try values.decode(String.self, forKey: .localeID)
        revision = try values.decode(Int.self, forKey: .revision)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        // Malformed/stale locations remain recoverable but are never painted on other text.
        for index in pronunciations.indices where !pronunciations[index].isAnchored(in: text) {
            pronunciations[index].span = nil
        }
    }
}

public struct ScriptSnapshot: Sendable {
    public let scriptID: UUID
    public let revision: Int
    public let title: String
    public let localeID: String
    public let cues: [ScriptCue]
    public let pauseAfter: Set<UUID>
    public let pronunciations: [UUID: [Pronunciation]]
}

public enum ScriptLibraryError: LocalizedError, Equatable {
    case emptyScript, speakingLimit, invalidSplit, conflict, corruptLibrary, newerVersion, fileTooLarge, unsupportedText, unsupportedFile

    public var errorDescription: String? {
        switch self {
        case .emptyScript: "Add some text before starting. Your draft can still be saved."
        case .speakingLimit: "Your full text is saved. To speak, use up to 50,000 characters and 500 sentences, with at most 400 characters per sentence. Split long sentences in Sentence layout."
        case .invalidSplit: "Place the cursor inside the sentence, with words on both sides."
        case .conflict: "This script changed elsewhere. Your edits are still here. Copy them before reopening the saved script."
        case .corruptLibrary: "The library and its backup could not be read. Existing files have been kept. Retry after restoring access; nothing has been overwritten."
        case .newerVersion: "This library was saved by a newer version of Oralo. Update the app to open it. Existing files have not been changed."
        case .fileTooLarge: "Choose a text file smaller than 2 MB. Nothing was imported or truncated; the original file is unchanged."
        case .unsupportedText: "This file is not readable UTF-8 or UTF-16 text. Export it as UTF-8 TXT and try again. Nothing was imported."
        case .unsupportedFile: "Choose a .txt or .md file. Markdown is imported as plain text."
        }
    }
}
