import Foundation
import Testing
@testable import OraloCore

struct ReadingToolsTests {
    @Test func countsContentAndUnicodeRatherThanMarkup() {
        let metrics = ScriptMetrics(text: "夯实 18% roadmap，don't re-enter. 👨‍👩‍👧‍👦 𠮷 é")
        #expect(metrics.characters == 5)
        #expect(metrics.words == 4)
        #expect(ScriptMetrics(text: " — … 👩🏽‍💻 ").isEmpty)
    }
    @Test func estimatesAreExplicitAndBounded() {
        let short = ScriptMetrics(text: "Hello.")
        #expect(short.duration(preferences: ReadingPreferences()) == .underOneMinute)
        let mixed = ScriptMetrics(text: String(repeating: "字", count: 240) + String(repeating: " word", count: 140))
        #expect(mixed.duration(preferences: ReadingPreferences()) == .minutes(2))
        let long = ScriptMetrics(text: String(repeating: "字", count: 2400))
        #expect(long.duration(preferences: ReadingPreferences()) == .range(9, 11))
        #expect(ScriptMetrics(text: "").duration(preferences: ReadingPreferences()) == .empty)
    }
    @Test func legacyPreferencesPreserveExistingChoices() throws {
        let data = Data(#"{"fontSize":40,"appearance":"dark","followsVoice":false,"localeID":"en-US"}"#.utf8)
        let value = try JSONDecoder().decode(ReadingPreferences.self, from: data)
        #expect(value.fontSize == 40 && value.appearance == .dark && !value.followsVoice)
        #expect(value.localeID == "en-US" && !value.mirrorsText)
        #expect(value.chineseCharactersPerMinute == 240 && value.englishWordsPerMinute == 140)
        let invalid = ReadingPreferences(chineseCharactersPerMinute: .nan, englishWordsPerMinute: 0)
        #expect(invalid.chineseCharactersPerMinute == 240 && invalid.englishWordsPerMinute == 100)
        #expect(try JSONDecoder().decode(ReadingPreferences.self, from: JSONEncoder().encode(value)) == value)
    }
    @Test func sampleLanguagesAndCountsAgree() {
        let en = QuickScript.sample(localization: "en")
        let zh = QuickScript.sample(localization: "zh-Hans")
        let tw = QuickScript.sample(localization: "zh-Hant")
        #expect(en.localeID == "en-US" && ScriptMetrics(text: en.text).words == 134)
        #expect(zh.localeID == "zh-CN" && ScriptMetrics(text: zh.text).characters == 210)
        #expect(tw.localeID == "zh-CN" && ScriptMetrics(text: tw.text).characters == 208)
        #expect(tw.text.contains("品質") && !en.text.contains("大家好"))
        #expect(QuickScript.sample(localization: "fr") == en)
    }
    @Test func localEditsKeepSplitsPausesAndOtherReadings() throws {
        var doc = ScriptDocument(text: "夯实基础，完善 roadmap。\n下一步继续。")
        try doc.split(doc.segments[0].id, at: 5)
        let first = doc.segments[0].id, second = doc.segments[1].id, last = doc.segments.last!.id
        doc.togglePause(first)
        let range = (doc.text as NSString).range(of: "roadmap")
        try doc.setPronunciation(Pronunciation(span: TextSpan(range), term: "roadmap", reading: "/ˈroʊdmæp/", kind: .ipa))
        try doc.applyTextEdit(NSRange(location: 0, length: 2), replacement: "打牢")
        #expect(doc.segments.map(\.id) == [first, second, last])
        #expect(doc.segments[0].pauseAfter && doc.hasCustomLayout && !doc.layoutNeedsReview)
        #expect(doc.pronunciations[0].isAnchored(in: doc.text))
        #expect(doc.originalText?.hasPrefix("夯实") == true)
    }
    @Test func crossingBoundariesOnlyRebuildsAffectedRegion() throws {
        var doc = ScriptDocument(text: "开头。相同。相同。结尾。")
        doc.togglePause(doc.segments[0].id); doc.togglePause(doc.segments[3].id)
        let prefix = doc.segments[0], suffix = doc.segments[3]
        try doc.applyTextEdit(NSRange(location: 4, length: 4), replacement: "👩🏽‍💻新的内容")
        #expect(doc.layoutNeedsReview && doc.hasCustomLayout)
        #expect(doc.segments.first?.id == prefix.id && doc.segments.first?.pauseAfter == true)
        #expect(doc.segments.last?.id == suffix.id && doc.segments.last?.pauseAfter == true)
        #expect(doc.segmentSpans().count == doc.segments.count)
        #expect(Set(doc.segments.map(\.id)).count == doc.segments.count)
        let reopened = try JSONDecoder().decode(ScriptDocument.self, from: JSONEncoder().encode(doc))
        #expect(reopened == doc)
        doc.confirmLayout(); #expect(!doc.layoutNeedsReview)
    }
    @Test func deletingEntireCueDoesNotResurrectIt() throws {
        var doc = ScriptDocument(text: "First. Second. Third.")
        doc.togglePause(doc.segments[2].id)
        let last = doc.segments[2].id
        try doc.applyTextEdit((doc.text as NSString).range(of: "Second."), replacement: "")
        #expect(doc.segments.count == 2 && doc.segments.last?.id == last)
        #expect(doc.layoutNeedsReview && doc.segments.last?.pauseAfter == true)
        try doc.applyTextEdit(NSRange(location: 0, length: doc.text.utf16.count), replacement: "")
        #expect(doc.segments.isEmpty && doc.text.isEmpty)
        #expect(throws: ScriptLibraryError.self) { try doc.snapshot() }
    }
    @Test func separatorAndBoundaryInsertionRetainOccurrences() throws {
        var doc = ScriptDocument(text: "Same.\nSame.")
        doc.togglePause(doc.segments[0].id)
        let ids = doc.segments.map(\.id)
        try doc.applyTextEdit(NSRange(location: 5, length: 1), replacement: "\n\n")
        #expect(doc.segments.map(\.id) == ids)
        #expect(doc.segments[0].separatorAfter == "\n\n")
        try doc.applyTextEdit(NSRange(location: 7, length: 0), replacement: "New ")
        #expect(doc.segments.last?.id == ids.last)
        #expect(doc.segments.last?.text == "New Same.")
    }
    @Test func uncertainWholeReplacementKeepsUserReadingsForReview() throws {
        var doc = ScriptDocument(text: "A roadmap.")
        doc.togglePause(doc.segments[0].id)
        try doc.setPronunciation(Pronunciation(span: TextSpan((doc.text as NSString).range(of: "roadmap")), term: "roadmap", reading: "/test/", kind: .ipa))
        doc.replaceText("A different roadmap.")
        #expect(doc.layoutNeedsReview && doc.pronunciations[0].needsReview)
        #expect(doc.pronunciations[0].reading == "/test/")
    }
    @Test func repeatedEditsKeepEveryVisibleWordAndStableOuterPauses() throws {
        var doc = ScriptDocument(text: "First passage. Middle passage. Last passage.")
        doc.togglePause(doc.segments[0].id)
        var seed: UInt64 = 12345
        let replacements = ["字", "👩🏽‍💻", "", " ", "\n", "new", "。"]
        for _ in 0..<200 {
            seed = seed &* 6364136223846793005 &+ 1
            let count = doc.text.count, start = Int(seed % UInt64(count + 1))
            seed = seed &* 6364136223846793005 &+ 1
            let length = min(Int(seed % 4), count - start)
            let lower = doc.text.index(doc.text.startIndex, offsetBy: start)
            let upper = doc.text.index(lower, offsetBy: length)
            let replacement = replacements[Int(seed % UInt64(replacements.count))]
            let expected = doc.text.replacingCharacters(in: lower..<upper, with: replacement)
            try doc.applyTextEdit(NSRange(lower..<upper, in: doc.text), replacement: replacement)
            #expect(doc.text == expected)
            #expect(doc.segmentSpans().count == doc.segments.count)
            #expect(doc.segments.map { $0.text + $0.separatorAfter }.joined().trimmingCharacters(in: .whitespacesAndNewlines) == doc.text.trimmingCharacters(in: .whitespacesAndNewlines))
            #expect(Set(doc.segments.map(\.id)).count == doc.segments.count)
        }
    }

    @Test func traditionalSampleMatchesMandarinSimplifiedTranscripts() throws {
        let sample = QuickScript.sample(localization: "zh-Hant")
        let cues = ScriptCue.parse(sample.text)
        for (index, cue) in cues.enumerated() {
            let transcript = try #require(cue.text.applyingTransform(StringTransform("Hant-Hans"), reverse: false))
            #expect(SpeechText.tokenize(cue.text).map(\.value) == SpeechText.tokenize(transcript).map(\.value))
            var engine = try FollowEngine(cues: cues); engine.resume()
            engine.ingest(transcript, isFinal: true, token: engine.session.contextToken, sequence: 0)
            #expect(engine.session.currentIndex == index)
            #expect(cue.text == cues[index].text)
        }
    }

    @Test func typingAtSentenceEndDoesNotCreateOneCuePerKeystroke() throws {
        var doc = ScriptDocument(text: "First line.\nSecond line.")
        doc.togglePause(doc.segments[0].id)
        let ids = doc.segments.map(\.id)
        var cursor = doc.segments[0].text.utf16.count
        for character in " updated" {
            let value = String(character)
            try doc.applyTextEdit(NSRange(location: cursor, length: 0), replacement: value)
            cursor += value.utf16.count
        }
        #expect(doc.segments.map(\.id) == ids)
        #expect(doc.segments[0].text == "First line. updated")
        #expect(doc.segments[0].pauseAfter && !doc.layoutNeedsReview)
    }

}
