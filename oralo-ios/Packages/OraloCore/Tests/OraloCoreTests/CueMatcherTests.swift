import Foundation
import Testing
@testable import OraloCore

struct CueMatcherTests {
    let english = [
        "We reviewed our quarterly results and celebrated progress.",
        "Revenue grew by eighteen percent and delivery now takes twelve days.",
        "Next we will strengthen the foundation and refine our roadmap.",
        "Our next priority is delivery with an owner for every milestone.",
        "Customer feedback tells us reliable delivery matters more than adding features.",
        "Close the session and thank the team for their contributions."
    ].map { ScriptCue(text: $0) }

    @Test func followsSequentialCuesAfterFinalEvidence() throws {
        var engine = try FollowEngine(cues: english)
        engine.resume()
        let token = engine.session.contextToken
        for index in english.indices {
            engine.ingest(english[index].text, isFinal: true, token: token, sequence: UInt64(index))
            #expect(engine.session.currentIndex == index)
        }
    }

    @Test func improvisationCannotReuseEarlierScriptWords() throws {
        var engine = try FollowEngine(cues: english)
        engine.resume()
        let token = engine.session.contextToken
        engine.ingest(english[1].text, isFinal: true, token: token, sequence: 0)
        let offScript = english[2].text + " Let me tell you a story about a rainy weekend and losing my suitcase at a station."
        engine.ingest(offScript, isFinal: true, token: token, sequence: 1)
        #expect(engine.session.currentIndex == 1)
        #expect(engine.session.mode == .holding)
        engine.ingest(english[3].text, isFinal: true, token: token, sequence: 2)
        #expect(engine.session.currentIndex == 3)
        #expect(engine.session.mode == .following)
    }

    @Test func distantDistinctiveSpeechRecoversWhileShortGenericWordsHold() {
        let matcher = CueMatcher(cues: english)
        #expect(matcher.match(english[5].text, currentIndex: 0)?.index == 5)
        #expect(matcher.match("next priority", currentIndex: 0) == nil)
        #expect(matcher.match("", currentIndex: 0) == nil)
    }

    @Test func duplicatedPhraseDoesNotChooseAnArbitraryCue() {
        let cues = ["One opening sentence to begin the presentation.",
                    "Our next priority is delivery with an owner for every milestone.",
                    "Our next priority is delivery with an owner for every milestone and then a review."]
            .map { ScriptCue(text: $0) }
        let matcher = CueMatcher(cues: cues)
        #expect(matcher.match("our next priority is delivery with an owner for every milestone", currentIndex: 0) == nil)
    }

    @Test func identicalPartialsDoNotCountAsConfirmation() throws {
        var engine = try FollowEngine(cues: english)
        engine.resume()
        let token = engine.session.contextToken
        let partial = "close the meeting and thank"
        engine.ingest(partial, isFinal: false, token: token, sequence: 0)
        engine.ingest(partial, isFinal: false, token: token, sequence: 1)
        #expect(engine.session.currentIndex == 0)
        engine.ingest(partial + " the team for their contributions", isFinal: false, token: token, sequence: 2)
        #expect(engine.session.currentIndex == 5)
    }

    @Test func manualSelectionInvalidatesMatcherConsensusAndOldFinals() throws {
        var engine = try FollowEngine(cues: english)
        engine.resume()
        let oldToken = engine.session.contextToken
        engine.ingest("close the meeting and thank", isFinal: false, token: oldToken, sequence: 0)
        engine.selectCue(english[0].id)
        engine.ingest(english[5].text, isFinal: true, token: oldToken, sequence: 999)
        #expect(engine.session.currentIndex == 0)
        let newToken = engine.session.contextToken
        engine.ingest("close the meeting and thank", isFinal: false, token: newToken, sequence: 0)
        #expect(engine.session.currentIndex == 0)
    }

    @Test func chineseAndMixedLanguageCanRecoverNearby() throws {
        let cues = ["大家好今天汇报本季度的团队进展", "本季度收入增长百分之十八交付周期缩短到十二天",
                    "接下来我们继续夯实基础完善roadmap", "下一步优先改善交付明确每个milestone的负责人"]
            .map { ScriptCue(text: $0) }
        var engine = try FollowEngine(cues: cues)
        engine.resume()
        engine.ingest("接下来 我们 继续 夯实 基础 完善 roadmap", isFinal: true,
                      token: engine.session.contextToken, sequence: 0)
        #expect(engine.session.currentIndex == 2)
        #expect(CueMatcher(cues: cues).match("优先改善交付", currentIndex: 1)?.index == 3)
    }

    @Test func punctuationCaseAndWidthDoNotChangeWords() {
        #expect(CueMatcher.tokens("Ｗｅ refine the Roadmap！继续讲。") == ["we", "refine", "the", "roadmap", "继", "续", "讲"])
        #expect(ScriptCue.parse("\nFirst sentence. Second sentence!\n接下来继续。\n").count == 3)
    }
}
