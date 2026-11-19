import Foundation
import Testing
@testable import OraloCore

struct ReadingProgressTests {
    @Test func originalGraphemeOffsetsSurviveMixedTextAndWidthFolding() {
        let text = "🎙️ 今天，Ｗｅ résumé roadmap！"
        let tokens = CueMatcher.tokenize(text)
        #expect(tokens.map(\.value) == ["今", "天", "we", "résumé", "roadmap"])
        let characters = Array(text)
        #expect(tokens.map { String(characters[$0.characters]) } == ["今", "天", "Ｗｅ", "résumé", "roadmap"])
        var progress = ReadingProgress(text: text)
        progress.observe(tokenEnd: 3, at: 10)
        #expect(String(text.prefix(progress.confirmedCharacterCount)) == "🎙️ 今天，Ｗｅ")
        progress.observe(tokenEnd: 5, at: 11)
        #expect(progress.confirmedCharacterCount == text.count)
    }

    @Test func partialRevisionsNeverMoveConfirmedCharactersBackward() {
        var progress = ReadingProgress(text: "大家好今天汇报本季度的团队进展")
        progress.observe(tokenEnd: 7, at: 10)
        progress.observe(tokenEnd: 4, at: 10.4)
        #expect(progress.confirmedTokenCount == 7)
        #expect(progress.lastAdvanceTime == 10)
        progress.observe(tokenEnd: 9, at: 9) // Out-of-order observation.
        #expect(progress.confirmedTokenCount == 7)
    }

    @Test func predictedLeadIsBoundedFreshAndNeverAuthoritative() {
        var progress = ReadingProgress(text: "大家好今天汇报本季度的团队进展")
        progress.observe(tokenEnd: 4, at: 10)
        #expect(progress.displayedTokenCount(at: 10.5, microphoneActive: true, allowPrediction: true) == 7)
        #expect(progress.confirmedTokenCount == 4)
        #expect(progress.displayedTokenCount(at: 10.5, microphoneActive: false, allowPrediction: true) == 4)
        #expect(progress.displayedTokenCount(at: 10.5, microphoneActive: true, allowPrediction: false) == 4)
        progress.observe(tokenEnd: 4, at: 10.6) // Duplicate callbacks cannot extend prediction.
        #expect(progress.displayedTokenCount(at: 11.1, microphoneActive: true, allowPrediction: true) == 4)
        #expect(progress.displayedTokenCount(at: .infinity, microphoneActive: true, allowPrediction: true) == 4)
        progress.suspendPrediction()
        #expect(progress.displayedTokenCount(at: 10.5, microphoneActive: true, allowPrediction: true) == 4)
    }

    @Test func englishPredictsAtMostTwoWholeWords() {
        var progress = ReadingProgress(text: "We reviewed our quarterly results and celebrated progress.")
        progress.observe(tokenEnd: 3, at: 10)
        #expect(progress.displayedTokenCount(at: 10.6, microphoneActive: true, allowPrediction: true) == 5)
        #expect(String("We reviewed our quarterly results and celebrated progress.".prefix(progress.characterEnd(for: 4))) == "We reviewed our quarterly")
    }

    @Test func mixedLanguagePredictionStopsAtWordBoundaries() {
        var progress = ReadingProgress(text: "接下来完善 our product roadmap 再继续讨论")
        progress.observe(tokenEnd: 5, at: 10)
        #expect(progress.displayedTokenCount(at: 10.6, microphoneActive: true, allowPrediction: true) == 6)
        var beforeBoundary = ReadingProgress(text: "接下来完善 our product roadmap 再继续讨论")
        beforeBoundary.observe(tokenEnd: 4, at: 10)
        #expect(beforeBoundary.displayedTokenCount(at: 10.6, microphoneActive: true, allowPrediction: true) == 5)
    }

    @Test func chineseAdvancesInsideCueAndPreparesNextWithoutMovingAnchor() throws {
        let cues = ["大家好今天汇报本季度的团队进展", "本季度收入增长百分之十八交付周期缩短到十二天"].map { ScriptCue(text: $0) }
        var engine = try FollowEngine(cues: cues)
        engine.resume()
        let token = engine.session.contextToken
        engine.ingest("大家好今", isFinal: false, token: token, sequence: 0, observedAt: 10)
        #expect(engine.reading.confirmedTokenCount == 4)
        engine.ingest("大家好今天汇报本季度的团", isFinal: false, token: token, sequence: 1, observedAt: 11)
        #expect(engine.reading.confirmedTokenCount == 12)
        #expect(engine.preparedCueIndex == 1)
        #expect(engine.session.currentIndex == 0)
        engine.ingest(cues[0].text + "本季度收", isFinal: false, token: token, sequence: 2, observedAt: 12)
        #expect(engine.session.currentIndex == 1)
        #expect(engine.reading.confirmedTokenCount == 4)
    }

    @Test func shortAdjacentOpeningWinsOverLongPreviousTranscript() throws {
        let cues = ["We reviewed our quarterly results and celebrated progress.",
                    "Revenue grew by eighteen percent and delivery now takes twelve days."].map { ScriptCue(text: $0) }
        var engine = try FollowEngine(cues: cues)
        engine.resume()
        let token = engine.session.contextToken
        engine.ingest(cues[0].text, isFinal: false, token: token, sequence: 0, observedAt: 10)
        engine.ingest(cues[0].text + " Revenue grew by", isFinal: false, token: token, sequence: 1, observedAt: 11)
        #expect(engine.session.currentIndex == 1)
        #expect(engine.reading.confirmedTokenCount == 3)
        engine.ingest(cues[0].text + " Revenue grew by", isFinal: true, token: token, sequence: 2, observedAt: 12)
        #expect(engine.reading.confirmedTokenCount == 3)
        #expect(engine.reading.lastAdvanceTime == 11)
    }

    @Test func ambiguousAdjacentOpeningsStillHold() {
        let cues = ["今天我们汇报进展谢谢大家", "接下来我们讨论质量问题", "接下来我们讨论速度问题"].map { ScriptCue(text: $0) }
        let matcher = CueMatcher(cues: cues)
        #expect(matcher.match("接下来我们", currentIndex: 0) == nil)
    }

    @Test func manualSelectionAndRequestRestartInvalidateOldProgress() throws {
        let cues = ["大家好今天汇报本季度的团队进展", "本季度收入增长百分之十八交付周期缩短到十二天"].map { ScriptCue(text: $0) }
        var engine = try FollowEngine(cues: cues)
        engine.resume()
        let oldToken = engine.session.contextToken
        engine.ingest("大家好今天", isFinal: false, token: oldToken, sequence: 0, observedAt: 10)
        engine.pause()
        engine.resume()
        #expect(engine.reading.confirmedTokenCount == 5)
        #expect(engine.reading.lastAdvanceTime == nil)
        engine.selectCue(cues[1].id)
        #expect(engine.reading.confirmedTokenCount == 0)
        engine.ingest(cues[0].text, isFinal: true, token: oldToken, sequence: 99, observedAt: 11)
        #expect(engine.reading.confirmedTokenCount == 0)
        #expect(engine.session.currentIndex == 1)
    }

    @Test func improvisationStopsPredictionAndNextCuePreview() throws {
        let cues = ["大家好今天汇报本季度的团队进展", "本季度收入增长百分之十八交付周期缩短到十二天"].map { ScriptCue(text: $0) }
        var engine = try FollowEngine(cues: cues)
        engine.resume()
        let token = engine.session.contextToken
        engine.ingest(cues[0].text, isFinal: false, token: token, sequence: 0, observedAt: 10)
        #expect(engine.preparedCueIndex == 1)
        engine.ingest("我想起昨天乘坐火车去看望一位老朋友的经历", isFinal: false, token: token, sequence: 1, observedAt: 10.2)
        #expect(engine.session.mode == .holding)
        #expect(engine.preparedCueIndex == nil)
        #expect(engine.reading.lastAdvanceTime == nil)
        engine.ingest("本季度收", isFinal: false, token: token, sequence: 2, observedAt: 11)
        #expect(engine.session.currentIndex == 1) // A brief hold must not lock out a clear nearby opening.
    }
}
