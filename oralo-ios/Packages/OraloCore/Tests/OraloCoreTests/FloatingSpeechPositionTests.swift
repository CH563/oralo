import Foundation
import Testing
@testable import OraloCore

struct FloatingSpeechPositionTests {
    @Test func repeatedCuesAndNonBMPCharactersKeepOriginalRanges() {
        let document = ScriptDocument(text: "第一句。\n𠮷é👨‍👩‍👧‍👦继续。\n第一句。")
        let positions = FloatingSpeechPosition(document: document)
        let spans = document.segmentSpans()
        #expect(positions.offset(cueIndex: 2, charactersRead: 1) == spans[2].1.location)
        #expect(positions.offset(cueIndex: 1, charactersRead: 2) == spans[1].1.location + 2)
        #expect(positions.offset(cueIndex: 1, charactersRead: 4) == spans[1].1.location + "𠮷é👨‍👩‍👧‍👦".utf16.count)
        #expect(positions.offset(cueIndex: -1, charactersRead: 0) == nil)
        #expect(positions.offset(cueIndex: 999, charactersRead: 0) == nil)
    }
    @Test func annotationsDoNotShiftSpeechPositions() throws {
        var document = ScriptDocument(text: "接下来夯实基础。完善 roadmap。")
        let before = FloatingSpeechPosition(document: document)
        let range = (document.text as NSString).range(of: "夯实")
        try document.setPronunciation(Pronunciation(span: TextSpan(range), term: "夯实", reading: "hāng shí", kind: .pinyin))
        let after = FloatingSpeechPosition(document: document)
        for index in document.segments.indices {
            for count in 0...document.segments[index].text.count {
                #expect(before.offset(cueIndex: index, charactersRead: count) == after.offset(cueIndex: index, charactersRead: count))
            }
        }
    }
}
