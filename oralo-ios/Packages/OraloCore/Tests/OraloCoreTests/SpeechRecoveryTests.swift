import Foundation
import Testing
@testable import OraloCore

struct SpeechRecoveryTests {
    let lines = [
        "大家好，今天汇报本季度的团队进展。",
        "本季度收入增长18%，交付周期缩短到12天。",
        "接下来，我们继续夯实基础，完善 roadmap。",
        "下一步，优先改善交付，明确每个 milestone 的负责人。",
        "客户反馈说明，稳定的交付比增加功能更加重要。",
        "我们计划先解决三个最影响体验的问题。",
        "第一个是减少等待，第二个是提高质量，第三个是及时反馈。",
        "现在我想分享一个真实的团队合作故事。",
        "回到计划，下个月我们将完成第一轮客户验证。",
        "验证之后，我们会根据反馈调整实施顺序。",
        "最后重申，优先改善交付，同时守住质量底线。",
        "谢谢大家，接下来欢迎提问和讨论。"
    ]

    @Test func naturalSpeechAndSkippedSentenceCannotLockAtFirstCue() throws {
        var engine = try FollowEngine(cues: lines.map { ScriptCue(text: $0) })
        engine.resume()
        let token = engine.session.contextToken
        let steps: [(String, Int)] = [
            (lines[0], 0),
            (lines[0] + "本季度呢", 1),
            (lines[0] + "本季度呢收入有百分之十八", 1),
            ("本季度呢收入有百分之十八就护周期缩短到十二天", 1),
            ("本季度呢收入有百分之十八就护周期缩短到十二天下一步", 3),
            ("下一步我们会优先改善交交付明确每个mistime的负责人", 3),
            ("客户返回说明", 4),
            ("客户返回说明稳定的交付比增加功能更重要", 4),
            ("稳定的交付比增加功能更重要我们计划先解决", 5),
            ("我们计划先解决三个最影响体验的问题第一个呢", 6)
        ]
        for (sequence, step) in steps.enumerated() {
            engine.ingest(step.0, isFinal: false, token: token, sequence: UInt64(sequence), observedAt: Double(sequence))
            #expect(engine.session.currentIndex == step.1, "Failed at transcript: \(step.0)")
        }
    }

    @Test func recoverySearchesBeyondThreeCuesAndCanReadBack() throws {
        var engine = try FollowEngine(cues: lines.map { ScriptCue(text: $0) })
        engine.resume()
        let token = engine.session.contextToken
        engine.ingest("现在我想分享一个真实的团队合作故事", isFinal: false, token: token, sequence: 0)
        #expect(engine.session.currentIndex == 7)
        engine.ingest("本季度收入增长百分之十八交付周期缩短到十二天", isFinal: false, token: token, sequence: 1)
        #expect(engine.session.currentIndex == 1)
        engine.ingest("谢谢大家接下来欢迎提问和讨论", isFinal: false, token: token, sequence: 2)
        #expect(engine.session.currentIndex == 11)
    }

    @Test func oldCumulativeTextAndDuplicateFinalCannotBounceBackward() throws {
        var engine = try FollowEngine(cues: lines.map { ScriptCue(text: $0) })
        engine.resume()
        let token = engine.session.contextToken
        let first = lines[0]
        let jumped = first + lines[7]
        engine.ingest(first, isFinal: false, token: token, sequence: 0)
        engine.ingest(jumped, isFinal: false, token: token, sequence: 1)
        #expect(engine.session.currentIndex == 7)
        engine.ingest(jumped, isFinal: true, token: token, sequence: 2)
        engine.ingest("大家好今天汇报这个季度的团队进展" + lines[7], isFinal: false, token: token, sequence: 3)
        #expect(engine.session.currentIndex == 7)
        engine.ingest(lines[7] + "这是一个天气很好的周末我们去郊外旅行", isFinal: false, token: token, sequence: 4)
        #expect(engine.session.currentIndex == 7)
        #expect(engine.session.mode == .holding)
    }

    @Test func repeatedShortConclusionDoesNotChooseBetweenDistantCopies() {
        let matcher = CueMatcher(cues: lines.map { ScriptCue(text: $0) })
        #expect(matcher.match("优先改善交付", currentIndex: 0) == nil)
        #expect(matcher.match("最后重申优先改善交付", currentIndex: 0)?.index == 10)
        #expect(matcher.match("下一步优先改善交付", currentIndex: 0)?.index == 3)
    }

    @Test func staleRelocationCannotOverrideManualChoiceOrPause() throws {
        let cues = lines.map { ScriptCue(text: $0) }
        var engine = try FollowEngine(cues: cues)
        engine.resume()
        let old = engine.session.contextToken
        engine.selectCue(cues[2].id)
        engine.ingest(lines[11], isFinal: true, token: old, sequence: 100)
        #expect(engine.session.currentIndex == 2)
        engine.pause()
        engine.ingest(lines[11], isFinal: true, token: engine.session.contextToken, sequence: 101)
        #expect(engine.session.currentIndex == 2)
    }

    @Test func clearOpeningWorksAfterUncertainPartialAtStartup() throws {
        var engine = try FollowEngine(cues: lines.map { ScriptCue(text: $0) })
        engine.resume()
        let token = engine.session.contextToken
        engine.ingest("大家", isFinal: false, token: token, sequence: 0)
        #expect(engine.session.mode == .holding)
        engine.ingest("本季度收入", isFinal: false, token: token, sequence: 1)
        #expect(engine.session.currentIndex == 1)
        #expect(engine.session.mode == .following)
    }

    @Test func latestOffScriptWordsCannotBeDiscardedToKeepFollowingOldSentence() throws {
        var engine = try FollowEngine(cues: lines.map { ScriptCue(text: $0) })
        engine.resume()
        let token = engine.session.contextToken
        engine.ingest(lines[0], isFinal: false, token: token, sequence: 0)
        engine.ingest(lines[0] + "我突然想起昨天公园门口的咖啡店", isFinal: false, token: token, sequence: 1)
        #expect(engine.session.mode == .holding)
        #expect(engine.session.currentIndex == 0)
    }

    @Test(arguments: [("增长18%缩短到12天", "增长百分之十八缩短到十二天"),
                      ("增长１８％，2.50天", "增长百分之十八，两点五天"),
                      ("第3个问题", "第三个问题"), ("12000人", "一万二千人")])
    func numericReadingsMatch(pair: (String, String)) {
        #expect(CueMatcher.tokens(pair.0) == CueMatcher.tokens(pair.1))
    }

    @Test func normalizedNumbersKeepOriginalHighlightRanges() {
        let text = "增长百分之十八，交付十二天。"
        let tokens = CueMatcher.tokenize(text)
        let percent = tokens.first { $0.value == "#18%" }
        #expect(percent != nil)
        if let percent { #expect(String(Array(text)[percent.characters]) == "百分之十八") }
        var progress = ReadingProgress(text: text)
        progress.observe(tokenEnd: 3, at: 1)
        #expect(String(text.prefix(progress.confirmedCharacterCount)) == "增长百分之十八")
    }

    @Test func indexCanLocateAUniqueCueInALargeScript() {
        let cues = (0..<500).map { ScriptCue(text: "编号\($0)专项团队正在进行客户体验验证工作") }
        let matcher = CueMatcher(cues: cues)
        #expect(matcher.match("编号347专项团队正在进行客户体验验证工作", currentIndex: 0)?.index == 347)
        #expect(matcher.match("正在进行客户体验验证工作", currentIndex: 0) == nil)
    }
}
