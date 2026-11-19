import Foundation
import Synchronization
import Testing
@testable import OraloCore

struct RehearsalTests {
    private func snapshot() throws -> RehearsalSnapshot {
        var document = ScriptDocument(title: "Quarterly report", text: "本季度收入增长18%。\n接下来夯实基础，完善 roadmap。\n谢谢大家。")
        document.revision = 1
        let range = (document.text as NSString).range(of: "夯实")
        try document.setPronunciation(Pronunciation(span: TextSpan(range), term: "夯实", reading: "hāng shí", kind: .pinyin))
        return RehearsalSnapshot(document: document)
    }
    private var date: Date { Date(timeIntervalSince1970: 1_800_000_000) }
    private func timeline(_ snapshot: RehearsalSnapshot, input: RehearsalRecord.Input = .manual) -> RehearsalTimeline {
        RehearsalTimeline(snapshot: snapshot, kind: .rehearsal, input: input, cueID: snapshot.document.segments[0].id, date: date, uptime: 100)
    }
    private func directory() -> URL { URL.temporaryDirectory.appendingPathComponent("oralo-rehearsal-\(UUID())") }

    @Test func activeTimeExcludesPauseInterruptionAndClockChanges() throws {
        let snapshot = try snapshot(); var value = timeline(snapshot)
        value.pause(interrupted: false, date: date.addingTimeInterval(600), uptime: 110)
        value.pause(interrupted: true, date: date, uptime: 120) // repeated notifications are not new events
        value.resume(date: date.addingTimeInterval(-500), uptime: 130)
        value.pause(interrupted: true, date: date, uptime: 140)
        value.finish(completed: false, date: date, uptime: 150)
        #expect(value.record.activeDuration == 20)
        #expect(value.record.pausedDuration == 30)
        #expect(value.record.events.filter { $0.kind == .interruption }.count == 1)
        #expect(value.record.status == .unfinished)
    }
    @Test func holdCallbacksFormOneIntervalAndManualModeDoesNotInventSpeechData() throws {
        let snapshot = try snapshot(); let cue = snapshot.document.segments[0].id
        var value = timeline(snapshot, input: .voice)
        for i in 0..<30 { value.observe(cueID: cue, holding: true, date: date, uptime: 100 + Double(i) / 10) }
        value.checkpoint(date: date, uptime: 104)
        value.checkpoint(date: date, uptime: 105)
        value.observe(cueID: cue, holding: false, date: date, uptime: 106)
        #expect(value.record.holdCount == 1)
        #expect(value.record.events[0].duration == 6)
        #expect(value.record.usedVoice)
        value.observe(cueID: cue, holding: true, date: date, uptime: 107)
        value.observe(cueID: cue, holding: false, date: date, uptime: 107.3)
        #expect(value.record.holdCount == 1) // transient partial hypotheses are omitted
        var manual = timeline(snapshot)
        manual.finish(completed: true, date: date, uptime: 160)
        #expect(manual.record.activeDuration == 60 && manual.record.holdCount == 0 && !manual.record.usedVoice)
    }
    @Test func onlyRealManualPositionChangesCountAndPausedMovesKeepTheirPosition() throws {
        let snapshot = try snapshot(), cues = snapshot.document.segments
        var value = timeline(snapshot)
        value.manualMove(to: cues[0].id, reason: .selection, date: date, uptime: 101)
        value.manualMove(to: cues[1].id, reason: .next, date: date, uptime: 103)
        value.pause(interrupted: false, date: date, uptime: 105)
        value.manualMove(to: cues[0].id, reason: .selection, date: date, uptime: 115)
        #expect(value.record.manualCount == 2)
        #expect(value.record.events.last?.activeOffset == 5)
        #expect(value.record.currentCueID == cues[0].id)
        value.finish(completed: true, date: date, uptime: 120)
        let ended = value.record
        value.resume(date: date, uptime: 130); value.checkpoint(date: date, uptime: 140)
        value.manualMove(to: cues[2].id, reason: .next, date: date, uptime: 150)
        #expect(value.record == ended)
    }
    @Test func revisionSnapshotKeepsReadingsAndRefusesChangedSplitOrDeletedPassages() throws {
        let snapshot = try snapshot(), cue = snapshot.document.segments[1]
        var current = snapshot.document
        #expect(snapshot.editRange(cueID: cue.id, in: current) != nil)
        current.title = "New name"; current.revision += 1
        #expect(snapshot.editRange(cueID: cue.id, in: current) != nil)
        try current.split(cue.id, at: 3)
        #expect(snapshot.editRange(cueID: cue.id, in: current) == nil)
        #expect(snapshot.document.pronunciations.first?.reading == "hāng shí")
        current.replaceText("A different draft.")
        #expect(snapshot.editRange(cueID: cue.id, in: current) == nil)
    }
    @Test func repeatedHistoricalPassageAfterTextChangeNeedsUserChoice() {
        var document = ScriptDocument(text: "Repeat this.\nRepeat this.\nClosing.")
        document.revision = 1
        let snapshot = RehearsalSnapshot(document: document)
        let cue = document.segments[0].id
        #expect(snapshot.editRange(cueID: cue, in: document) != nil)
        document.replaceText("Repeat this.\nRepeat this.\nUpdated ending.")
        #expect(snapshot.editRange(cueID: cue, in: document) == nil)
    }
    @Test func savedRecordsAndSnapshotsReopenWithOneSnapshotPerRevision() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let repo = RehearsalRepository(directory: dir), snapshot = try snapshot()
        var first = timeline(snapshot); first.finish(completed: true, date: date, uptime: 110)
        var second = timeline(snapshot); second.finish(completed: true, date: date, uptime: 120)
        try await repo.save(first.record, snapshot: snapshot); try await repo.save(second.record, snapshot: snapshot)
        let reopened = try await RehearsalRepository(directory: dir).load().archive
        #expect(reopened.records == [first.record, second.record])
        #expect(reopened.snapshots == [snapshot])
        try await repo.delete(id: first.record.id)
        #expect(try await repo.load().archive.snapshots.count == 1)
        try await repo.delete(id: second.record.id)
        #expect(try await RehearsalRepository(directory: dir).load().archive.snapshots.isEmpty)
        let backup = try String(contentsOf: dir.appendingPathComponent("rehearsals.backup.json"), encoding: .utf8)
        #expect(!backup.contains("roadmap"))
    }
    @Test func crashRecoveryUsesLastCheckpointAndNeverAddsTimeWhileClosed() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let repo = RehearsalRepository(directory: dir), snapshot = try snapshot()
        var value = timeline(snapshot)
        value.checkpoint(date: date.addingTimeInterval(6), uptime: 106)
        try await repo.save(value.record, snapshot: snapshot)
        let recovered = try await RehearsalRepository(directory: dir).recoverInterruptedSessions().archive.records[0]
        #expect(recovered.status == .unfinished && recovered.activeDuration == 6)
        #expect(recovered.endedAt == date.addingTimeInterval(6))
    }
    @Test func storageFailureKeepsExistingArchiveAndRetrySucceeds() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let fail = Mutex(false)
        let repo = RehearsalRepository(directory: dir) { data, url in
            if fail.withLock({ $0 }) && url.lastPathComponent == "rehearsals.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        let snapshot = try snapshot(); var value = timeline(snapshot)
        try await repo.save(value.record, snapshot: snapshot)
        let initial = value.record
        value.finish(completed: true, date: date, uptime: 110)
        fail.withLock { $0 = true }
        await #expect(throws: CocoaError.self) { try await repo.save(value.record, snapshot: snapshot) }
        #expect(try await repo.load().archive.records == [initial])
        #expect(try await RehearsalRepository(directory: dir).load().archive.records == [initial])
        fail.withLock { $0 = false }
        try await repo.save(value.record, snapshot: snapshot)
        #expect(try await repo.load().archive.records[0].status == .completed)
    }
    @Test func delayedCheckpointCannotOverwriteCompletedRecord() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let repo = RehearsalRepository(directory: dir), snapshot = try snapshot()
        var value = timeline(snapshot); let old = value.record
        value.finish(completed: true, date: date, uptime: 110)
        try await repo.save(value.record, snapshot: snapshot)
        await #expect(throws: RehearsalStorageError.staleRecord) { try await repo.save(old, snapshot: snapshot) }
    }
    @Test func corruptPrimaryRecoversAndUnknownSchemaIsNeverOverwritten() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let repo = RehearsalRepository(directory: dir), snapshot = try snapshot()
        var value = timeline(snapshot)
        try await repo.save(value.record, snapshot: snapshot)
        value.finish(completed: true, date: date, uptime: 110)
        try await repo.save(value.record, snapshot: snapshot)
        let primary = dir.appendingPathComponent("rehearsals.json")
        try Data("broken".utf8).write(to: primary)
        #expect(try await RehearsalRepository(directory: dir).load().recovered)
        let future = Data("{\"schemaVersion\":99}".utf8);try future.write(to: primary)
        await #expect(throws: RehearsalStorageError.newerVersion) { try await RehearsalRepository(directory: dir).save(value.record, snapshot: snapshot) }
        #expect(try Data(contentsOf: primary) == future)
    }
    @Test func contentFreeEventsAndOrphanCleanup() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let repo = RehearsalRepository(directory: dir), snapshot = try snapshot()
        var value = timeline(snapshot)
        value.manualMove(to: snapshot.document.segments[1].id, reason: .selection, date: date, uptime: 102)
        let encoded = String(decoding: try JSONEncoder().encode(value.record), as: UTF8.self)
        #expect(!encoded.contains("roadmap") && !encoded.contains("hāng") && !encoded.contains("夯实"))
        try await repo.save(value.record, snapshot: snapshot)
        try await repo.removeOrphans(liveScriptIDs: [])
        #expect(try await repo.load().archive.records.isEmpty)
        #expect(try await repo.load().archive.snapshots.isEmpty)
    }
}
