import Foundation
import Testing
@testable import OraloCore

struct FloatingReadingTests {
    @Test func unicodeOffsetsAreOriginalManuscriptRanges() throws {
        let text = "𠮷 18% don't re-enter 👨‍👩‍👧‍👦 夯实 roadmap é"
        var document = ScriptDocument(text: text)
        let range = (text as NSString).range(of: "roadmap")
        let original = FloatingReadingTimeline(document: document)
        try document.setPronunciation(Pronunciation(span: TextSpan(range), term: "roadmap", reading: "/ˈroʊdmæp/", kind: .ipa))
        let annotated = FloatingReadingTimeline(document: document)
        let units = original.units.map { (text as NSString).substring(with: $0.range) }
        #expect(units == ["𠮷", "1", "8", "don't", "re-enter", "夯", "实", "roadmap", "é"])
        #expect(original.duration == annotated.duration)
        for unit in original.units {
            #expect(Range(unit.range, in: text) != nil)
            #expect(original.offset(at: original.time(atOffset: unit.range.location)) == unit.range.location)
        }
    }
    @Test func firstFrameIsPausedAndLongGapsDoNotSkipText() {
        let timeline = FloatingReadingTimeline(document: ScriptDocument(text: "一二三四五六七八九十"))
        var progress = FloatingReadingProgress()
        progress.advance(delta: 0.2, speed: 1, timeline: timeline)
        #expect(progress.elapsed == 0 && !progress.isPlaying)
        progress.play(timeline: timeline); progress.advance(delta: 0.2, speed: 1, timeline: timeline)
        #expect(abs(progress.elapsed - 0.2) < 0.0001)
        for gap in [30.0, Double.nan, .infinity, -1] { progress.advance(delta: gap, speed: 1, timeline: timeline) }
        #expect(abs(progress.elapsed - 0.2) < 0.0001)
        progress.pause(); progress.advance(delta: 0.2, speed: 1, timeline: timeline)
        #expect(abs(progress.elapsed - 0.2) < 0.0001)
    }
    @Test func speedAndResizeAreIndependentOfPosition() {
        let timeline = FloatingReadingTimeline(document: ScriptDocument(text: "一二三四五六七八九十"))
        var progress = FloatingReadingProgress()
        progress.seek(offset: 4, timeline: timeline)
        #expect(timeline.offset(at: progress.elapsed) == 4 && !progress.isPlaying)
        progress.play(timeline: timeline); progress.advance(delta: 0.25, speed: 2, timeline: timeline)
        #expect(timeline.offset(at: progress.elapsed) == 6)
        progress.seek(offset: timeline.offset(at: progress.elapsed), timeline: timeline)
        #expect(timeline.offset(at: progress.elapsed) == 6 && !progress.isPlaying)
    }
    @Test func pauseMarksPauseOnceAndExplicitResumeContinues() {
        var document = ScriptDocument(text: "一二。三四。")
        document.togglePause(document.segments[0].id)
        let timeline = FloatingReadingTimeline(document: document)
        var progress = FloatingReadingProgress(); progress.play(timeline: timeline)
        progress.advance(delta: 0.5, speed: 1, timeline: timeline)
        #expect(progress.elapsed == 0.5 && !progress.isPlaying)
        progress.play(timeline: timeline); progress.advance(delta: 0.25, speed: 1, timeline: timeline)
        #expect(progress.elapsed == 0.75 && progress.isPlaying)
        progress.advance(delta: 0.5, speed: 1, timeline: timeline)
        #expect(progress.elapsed == timeline.duration && !progress.isPlaying)
        progress.play(timeline: timeline); #expect(!progress.isPlaying)
    }
    @Test func emptyAndBadInputCannotStartOrAdvanceForever() {
        let timeline = FloatingReadingTimeline(document: ScriptDocument(text: " — 👨‍👩‍👧‍👦 "))
        var progress = FloatingReadingProgress(); progress.play(timeline: timeline)
        #expect(!progress.isPlaying && timeline.duration == 0)
        let safe = FloatingReadingTimeline(document: ScriptDocument(text: "中文 words"), chineseRate: .nan, englishRate: .infinity)
        #expect(safe.duration.isFinite && safe.duration > 0)
        progress.seek(offset: Int.max, timeline: safe)
        #expect(progress.elapsed == safe.duration && !progress.isPlaying)
    }
}
