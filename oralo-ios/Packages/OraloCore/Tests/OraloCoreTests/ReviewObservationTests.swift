import Foundation
import Testing
@testable import OraloCore

struct ReviewObservationTests {
    private let text = "接下来继续夯实基础，完善 roadmap。"
    private func document() -> ScriptDocument { ScriptDocument(text: text + "\nNext we improve delivery quality.") }

    @Test func quietRequiresContinuousCapturedAudioAndSpeechBeforeAndAfter() {
        let doc = document(), cue = doc.segments[0].id
        var detector = RehearsalObservations(document: doc)
        var time = 0.0
        func feed(_ level: Float, count: Int) -> [RehearsalObservations.Finding] {
            (0..<count).compactMap { _ in
                time += 0.05
                return detector.audio(level: level, duration: 0.05, at: time, activeOffset: time, cueID: cue)
            }
        }
        #expect(feed(0.01, count: 120).isEmpty) // startup silence is not a speaking pause
        #expect(feed(0.6, count: 10).isEmpty)
        #expect(feed(0.01, count: 120).isEmpty) // wait for resumed sound
        let events = feed(0.5, count: 10)
        #expect(events.count == 1)
        #expect(events.first?.kind == .silence && events.first?.cueID == cue)
        #expect(abs((events.first?.duration ?? 0) - 6) < 0.01)
        #expect(abs((events.first?.offset ?? 0) - 6.5) < 0.01)
    }

    @Test func missingBuffersManualPauseAndNoisyLevelsDoNotInventPauses() {
        let doc = document(), cue = doc.segments[0].id
        for reset in [false, true] {
            var value = RehearsalObservations(document: doc)
            for i in 0..<10 { _ = value.audio(level: 0.6, duration: 0.05, at: Double(i) * 0.05, activeOffset: 1, cueID: cue) }
            for i in 0..<100 { _ = value.audio(level: 0, duration: 0.05, at: 0.5 + Double(i) * 0.05, activeOffset: 6, cueID: cue) }
            if reset { value.reset() }
            #expect(value.audio(level: 0.6, duration: 0.05, at: 100, activeOffset: 6, cueID: cue) == nil)
        }
        var value = RehearsalObservations(document: doc)
        for i in 0..<150 { #expect(value.audio(level: 0.25, duration: 0.05, at: Double(i) * 0.05, activeOffset: 9, cueID: cue) == nil) }
        #expect(value.audio(level: 0.6, duration: 0.05, at: 7.5, activeOffset: 9, cueID: cue) == nil)
    }

    @Test func finalDistinctAudioCanShowARepeatButDuplicateAndOverlappingRevisionsCannot() {
        let doc = document()
        var value = RehearsalObservations(document: doc)
        let first = FinalSpeechSpan(text: text, start: 0, end: 3)
        #expect(value.finalized([first], requestOffset: 10).isEmpty)
        #expect(value.finalized([first], requestOffset: 10).isEmpty)
        #expect(value.finalized([FinalSpeechSpan(text: text, start: 1, end: 4)], requestOffset: 10).isEmpty)
        let found = value.finalized([FinalSpeechSpan(text: text, start: 4, end: 7)], requestOffset: 10)
        #expect(found.count == 1 && found.first?.kind == .reread)
        #expect(found.first?.cueID == doc.segments[0].id && found.first?.offset == 14)
        #expect(value.finalized([FinalSpeechSpan(text: text, start: 4, end: 7)], requestOffset: 10).isEmpty)
        value.reset()
        #expect(value.finalized([first], requestOffset: 20).isEmpty)
    }

    @Test func oneRangeCannotProveARepeatButSeparateWordRangesCan() {
        let doc = document()
        var value = RehearsalObservations(document: doc)
        #expect(value.finalized([FinalSpeechSpan(text: text + text, start: 0, end: 6)], requestOffset: 0).isEmpty)
        value.reset()
        let words = "Next we improve delivery quality".split(separator: " ").map(String.init)
        let spans = (words + words).enumerated().map { FinalSpeechSpan(text: $0.element, start: Double($0.offset) * 0.3, end: Double($0.offset + 1) * 0.3) }
        let found = value.finalized(spans, requestOffset: 0)
        #expect(found.count == 1 && found.first?.cueID == doc.segments[1].id)
    }

    @Test func ambiguousScriptOccurrencesShortPhrasesAndPartialRestartsAreOmitted() {
        let repeated = ScriptDocument(text: text + "\n" + text + "\nThank you.")
        var value = RehearsalObservations(document: repeated)
        #expect(value.finalized([FinalSpeechSpan(text: text + text + "Thank you. Thank you.", start: 0, end: 10)], requestOffset: 0).isEmpty)
        value = RehearsalObservations(document: document())
        #expect(value.finalized([FinalSpeechSpan(text: "接下来继续夯实，接下来继续夯实", start: 0, end: 3)], requestOffset: 0).isEmpty)
        #expect(value.finalized([FinalSpeechSpan(text: text, start: .nan, end: 4)], requestOffset: 0).isEmpty)
    }

    @Test func originalMappingHandlesUnicodeSplitsAndRefusesAmbiguousOrRewrittenText() throws {
        var doc = ScriptDocument(text: "开场😀。\n" + text + "\n谢谢大家。")
        let cue = doc.segments[1].id
        var snapshot = RehearsalSnapshot(document: doc)
        let expected = (doc.text as NSString).range(of: text)
        #expect(snapshot.originalRange(cueID: cue)?.nsRange == expected)
        try doc.split(cue, at: 6)
        snapshot = RehearsalSnapshot(document: doc)
        #expect(snapshot.originalRange(cueID: cue)?.length == 6)
        doc.replaceText("全部改写的稿件。")
        #expect(RehearsalSnapshot(document: doc).originalRange(cueID: doc.segments[0].id) == nil)
        var repeated = ScriptDocument(text: "Repeat this passage.\nRepeat this passage.\nThe end.")
        let id = repeated.segments[0].id
        #expect(RehearsalSnapshot(document: repeated).originalRange(cueID: id) != nil)
        repeated.replaceText("Repeat this passage.\nA different ending.")
        #expect(RehearsalSnapshot(document: repeated).originalRange(cueID: repeated.segments[0].id) == nil)
    }

    @Test func newEventsPersistWithoutSpeechTextAndDeleteFromBothCopies() async throws {
        let dir = URL.temporaryDirectory.appendingPathComponent("oralo-observations-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = document(), snapshot = RehearsalSnapshot(document: doc), date = Date()
        let repo = RehearsalRepository(directory: dir)
        var timeline = RehearsalTimeline(snapshot: snapshot, kind: .rehearsal, input: .voice, cueID: doc.segments[0].id, date: date, uptime: 0)
        timeline.appendObservation(.init(kind: .silence, cueID: doc.segments[0].id, offset: 2, duration: 5), date: date, uptime: 8)
        timeline.appendObservation(.init(kind: .reread, cueID: doc.segments[0].id, offset: 8, duration: 2), date: date, uptime: 10)
        timeline.pause(interrupted: true, date: date, uptime: 11)
        timeline.appendObservation(.init(kind: .silence, cueID: doc.segments[0].id, offset: 10, duration: 5), date: date, uptime: 15)
        #expect(timeline.record.events.filter(\.isReviewable).count == 2)
        timeline.finish(completed: true, date: date, uptime: 15)
        try await repo.save(timeline.record, snapshot: snapshot)
        let loaded = try await RehearsalRepository(directory: dir).load().archive
        #expect(loaded.schemaVersion == 3 && loaded.records[0].events == timeline.record.events)
        let json = String(decoding: try JSONEncoder().encode(timeline.record), as: UTF8.self)
        #expect(!json.contains("roadmap") && !json.contains("夯实"))
        try await repo.delete(id: timeline.record.id)
        for name in ["rehearsals.json", "rehearsals.backup.json"] {
            let data = try Data(contentsOf: dir.appendingPathComponent(name))
            let archive = try JSONDecoder().decode(RehearsalRepository.Archive.self, from: data)
            #expect(archive.records.isEmpty && archive.snapshots.isEmpty)
        }
    }

    @Test func build11ArchiveUpgradesWithoutLosingRecords() async throws {
        let dir = URL.temporaryDirectory.appendingPathComponent("oralo-upgrade-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = document(), snapshot = RehearsalSnapshot(document: doc)
        var old = RehearsalRepository.Archive(); old.schemaVersion = 1
        let record = RehearsalRecord(snapshot: snapshot, kind: .rehearsal, input: .manual, cueID: doc.segments[0].id, date: .now)
        old.records = [record]; old.snapshots = [snapshot]
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(old).write(to: dir.appendingPathComponent("rehearsals.json"))
        let loaded = try await RehearsalRepository(directory: dir).load().archive
        #expect(loaded.schemaVersion == 3 && loaded.records == [record] && loaded.snapshots == [snapshot])
    }
}
