import Testing
@testable import OraloCore

struct TranscriptWindowTests {
    @Test func partialRevisionsReplaceInsteadOfDuplicating() {
        var window = TranscriptWindow()
        let first = window.replace(start: 0, end: 2, text: "revenue grew")
        let revision = window.replace(start: 0, end: 3, text: "revenue grew by eighteen percent")
        let next = window.replace(start: 3, end: 5, text: "delivery takes twelve days")
        #expect(first == "revenue grew")
        #expect(revision == "revenue grew by eighteen percent")
        #expect(next == "revenue grew by eighteen percent delivery takes twelve days")
    }

    @Test func oldRangesAndInvalidTimesCannotReturnStaleScript() {
        var window = TranscriptWindow()
        _ = window.replace(start: 0, end: 3, text: "old script words")
        let current = window.replace(start: 20, end: 23, text: "an unrelated story")
        let stale = window.replace(start: 0, end: 3, text: "revised old words")
        let invalid = window.replace(start: .nan, end: 24, text: "invalid")
        #expect(current == "an unrelated story")
        #expect(stale == nil)
        #expect(invalid == nil)
        #expect(window.latestEnd == 23)
    }

    @Test func transcriptMemoryRemainsBounded() throws {
        var window = TranscriptWindow()
        var latest: String?
        for i in 0..<1_800 {
            latest = window.replace(start: Double(i), end: Double(i + 1), text: String(repeating: "x", count: 100))
        }
        #expect(try #require(latest).count <= 768)
    }
}
