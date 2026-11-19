import Foundation
import Testing
@testable import OraloCore

struct ReadingCursorTests {
    private let texts = ["大家好今天汇报本季度的团队进展", "本季度收入增长交付周期缩短", "欢迎提出建议一起讨论未来计划"]

    private func engine() throws -> FollowEngine {
        var engine = try FollowEngine(cues: texts.map { ScriptCue(text: $0) })
        engine.resume()
        return engine
    }

    @Test func delayedCallbackGetsImmediateBoundedLeadWithoutChangingRecognition() throws {
        var engine = try engine()
        engine.ingest("大家好今天", isFinal: false, token: engine.session.contextToken, sequence: 0, observedAt: 10)
        var cursor = ReadingCursor()
        cursor.update(engine: engine, at: 10, voiceActive: true, deliveryDelay: 0.6)
        #expect(engine.reading.confirmedTokenCount == 5)
        #expect(cursor.position == .init(cueIndex: 0, characterCount: 7))
        cursor.update(engine: engine, at: 10.8, voiceActive: true, deliveryDelay: 12)
        #expect(cursor.position.characterCount <= 11)
        #expect(engine.session.currentIndex == 0)
    }

    @Test func silenceAndExpiredEvidenceFreezeInsteadOfRetractingOrRunningAway() throws {
        var engine = try engine()
        engine.ingest("大家好今天", isFinal: false, token: engine.session.contextToken, sequence: 0, observedAt: 10)
        var cursor = ReadingCursor()
        cursor.update(engine: engine, at: 10.5, voiceActive: true)
        let position = cursor.position
        cursor.update(engine: engine, at: 10.8, voiceActive: false)
        #expect(cursor.position == position)
        engine.ingest("大家好今天", isFinal: false, token: engine.session.contextToken, sequence: 1, observedAt: 12)
        cursor.update(engine: engine, at: 12, voiceActive: true)
        #expect(cursor.position == position)
        cursor.update(engine: engine, at: 100, voiceActive: true)
        #expect(cursor.position == position)
    }

    @Test func endOfCueCanPreviewNextOpeningWithoutWaitingForSentenceConfirmation() throws {
        var engine = try engine()
        engine.ingest(texts[0], isFinal: false, token: engine.session.contextToken, sequence: 0, observedAt: 10)
        var cursor = ReadingCursor()
        cursor.update(engine: engine, at: 10.3, voiceActive: true)
        #expect(cursor.position == .init(cueIndex: 1, characterCount: 2))
        #expect(engine.session.currentIndex == 0)
        engine.ingest(texts[0] + "本季度收", isFinal: false, token: engine.session.contextToken, sequence: 1, observedAt: 10.6)
        cursor.update(engine: engine, at: 10.6, voiceActive: false)
        #expect(cursor.position == .init(cueIndex: 1, characterCount: 4))
    }

    @Test func improvisationFreezesAndManualBacktrackingReplacesPrediction() throws {
        var engine = try engine()
        engine.ingest(texts[0], isFinal: false, token: engine.session.contextToken, sequence: 0, observedAt: 10)
        var cursor = ReadingCursor()
        cursor.update(engine: engine, at: 10.3, voiceActive: true)
        let position = cursor.position
        engine.ingest("我想起昨天乘坐火车看望老朋友的经历", isFinal: false, token: engine.session.contextToken, sequence: 1, observedAt: 10.4)
        cursor.update(engine: engine, at: 10.8, voiceActive: true)
        #expect(engine.session.mode == .holding)
        #expect(cursor.position == position)
        engine.selectCue(engine.cues[0].id)
        cursor.update(engine: engine, at: 11, voiceActive: true)
        #expect(cursor.position == .init(cueIndex: 0, characterCount: 0))
    }

    @Test func unmatchedFirstSpeechCannotStartAnimation() throws {
        var engine = try engine()
        engine.ingest("今天的天气有点冷啊", isFinal: false, token: engine.session.contextToken, sequence: 0, observedAt: 10)
        var cursor = ReadingCursor()
        cursor.update(engine: engine, at: 10.5, voiceActive: true, deliveryDelay: 3)
        #expect(cursor.position == .init(cueIndex: 0, characterCount: 0))
    }
}
