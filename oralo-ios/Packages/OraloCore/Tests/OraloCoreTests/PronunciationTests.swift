import Foundation
import Testing
@testable import OraloCore

struct PronunciationTests {
    private func hint(_ text: String, _ term: String, backwards: Bool = false) -> Pronunciation {
        let range = (text as NSString).range(of: term, options: backwards ? .backwards : [])
        return Pronunciation(span: TextSpan(range), term: term, reading: "/ˈroʊdmæp/", kind: .ipa)
    }

    @Test func annotationsDoNotChangeRecognitionOrOriginalText() throws {
        var doc = ScriptDocument(text: "完善 roadmap。\nThen a milestone.")
        let before = try doc.snapshot()
        try doc.setPronunciation(hint(doc.text, "roadmap"))
        let after = try doc.snapshot()
        #expect(before.cues == after.cues)
        #expect(doc.text == doc.originalText)
        #expect(after.pronunciations[after.cues[0].id]?.first?.span?.location == 3)
    }

    @Test func repeatedWordsKeepTheirOwnReadingsAcrossExactEdits() throws {
        var doc = ScriptDocument(text: "roadmap and roadmap.")
        let first = hint(doc.text, "roadmap"), last = hint(doc.text, "roadmap", backwards: true)
        try doc.setPronunciation(first); try doc.setPronunciation(last)
        try doc.applyTextEdit(NSRange(location: 0, length: 0), replacement: "👩🏽‍💻 ")
        #expect(doc.pronunciations.allSatisfy { $0.isAnchored(in: doc.text) })
        let lastBefore = try #require(doc.pronunciations.last?.span)
        try doc.applyTextEdit(try #require(doc.pronunciations.first?.span).nsRange, replacement: "strategy")
        #expect(doc.pronunciations.first?.needsReview == true)
        #expect(doc.pronunciations.last?.span?.location == lastBefore.location + 1)
        #expect(doc.pronunciations.last?.isAnchored(in: doc.text) == true)
        #expect(doc.pronunciations.first?.reading == first.reading)
    }

    @Test func boundaryEditsAndUnicodeAreSafe() throws {
        var doc = ScriptDocument(text: "👨‍👩‍👧‍👦 夯实基础。")
        var reading = hint(doc.text, "夯实"); reading.reading = "hāng shí"; reading.kind = .pinyin
        try doc.setPronunciation(reading)
        let start = try #require(reading.span).location
        try doc.applyTextEdit(NSRange(location: start + 2, length: 0), replacement: "，")
        #expect(doc.pronunciations.first?.isAnchored(in: doc.text) == true)
        try doc.applyTextEdit(NSRange(location: start + 1, length: 0), replacement: "强")
        #expect(doc.pronunciations.first?.needsReview == true)
        #expect(try doc.snapshot().pronunciations.isEmpty)
    }

    @Test func splitMergeHideAndWholeReplacement() throws {
        var doc = ScriptDocument(text: "Plan the roadmap today.")
        try doc.setPronunciation(hint(doc.text, "roadmap"))
        #expect(throws: PronunciationError.self) { try doc.split(doc.segments[0].id, at: 12) }
        try doc.split(doc.segments[0].id, at: 9)
        let snapshot = try doc.snapshot()
        #expect(snapshot.pronunciations[snapshot.cues[1].id]?.first?.span?.location == 0)
        doc.mergeWithNext(doc.segments[0].id)
        #expect(try doc.snapshot().pronunciations.values.flatMap { $0 }.count == 1)
        var hidden = doc.pronunciations[0]; hidden.showInPresentation = false
        try doc.setPronunciation(hidden)
        #expect(try doc.snapshot().pronunciations.isEmpty)
        doc.replaceText("Another roadmap.")
        #expect(doc.pronunciations[0].needsReview)
        #expect(doc.pronunciations[0].reading == hidden.reading)
    }

    @Test func overlapAndMalformedReadingsAreRejected() throws {
        var doc = ScriptDocument(text: "roadmap milestone.")
        try doc.setPronunciation(hint(doc.text, "roadmap"))
        #expect(throws: PronunciationError.self) { try doc.setPronunciation(hint(doc.text, "road")) }
        var bad = hint(doc.text, "milestone"); bad.reading = "\n"
        #expect(throws: PronunciationError.self) { try doc.setPronunciation(bad) }
        #expect(doc.pronunciations.count == 1)
    }

    @Test func legacyDocumentsDecodeAndReadingsSurviveDiskRoundTrip() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = ScriptLibraryRepository(directory: folder)
        var doc = try await repository.save(ScriptDocument(text: "A roadmap."))
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as? [String: Any])
        legacy.removeValue(forKey: "pronunciations")
        let decoded = try JSONDecoder().decode(ScriptDocument.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.pronunciations.isEmpty)
        try doc.setPronunciation(hint(doc.text, "roadmap"))
        let saved = try await repository.save(doc)
        let reopened = try await ScriptLibraryRepository(directory: folder).load().documents
        #expect(reopened.first?.pronunciations == saved.pronunciations)
        #expect(reopened.first?.text == doc.text)
    }
}
