import Foundation
import Testing
@testable import OraloCore

struct PronunciationReviewTests {
    private func fixture() -> (RehearsalSnapshot, RehearsalRecord) {
        let doc = ScriptDocument(text: "Check this roadmap. Next passage.")
        let snapshot = RehearsalSnapshot(document: doc)
        var timeline = RehearsalTimeline(snapshot: snapshot, kind: .rehearsal, input: .manual, cueID: doc.segments[0].id, date: .now, uptime: 0)
        timeline.finish(completed: true, date: .now, uptime: 30)
        return (snapshot, timeline.record)
    }
    @Test func decisionsAreScopedToOneRecordAndNeverAlterHistory() async throws {
        let dir = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (snapshot, original) = fixture(), repo = RehearsalRepository(directory: dir)
        var record = original
        let cueID = snapshot.document.segments[0].id
        let mark = PronunciationReview(cueID: cueID, span: TextSpan((snapshot.document.text as NSString).range(of: "roadmap")), pronunciationID: UUID(), status: .added)
        record.setPronunciationReview(mark, cueID: cueID)
        #expect(record.sequence > original.sequence && original.pronunciationReviews == nil)
        try await repo.save(record, snapshot: snapshot)
        let loaded = try await RehearsalRepository(directory: dir).load().archive
        #expect(loaded.records[0].pronunciationReviews == [mark])
        #expect(loaded.snapshots == [snapshot] && snapshot.document.pronunciations.isEmpty)
        record.setPronunciationReview(nil, cueID: cueID)
        try await repo.save(record, snapshot: snapshot)
        #expect(try await repo.load().archive.records[0].pronunciationReviews == nil)
    }
    @Test func oldRecordsDecodeAndOldArchivesUpgrade() async throws {
        let dir = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (snapshot, record) = fixture()
        var archive = RehearsalRepository.Archive(); archive.schemaVersion = 2
        archive.records = [record]; archive.snapshots = [snapshot]
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: dir.appendingPathComponent("rehearsals.json"))
        let loaded = try await RehearsalRepository(directory: dir).load().archive
        #expect(loaded.schemaVersion == 3 && loaded.records[0].pronunciationReviews == nil)
        #expect(loaded.records[0] == record && loaded.snapshots == [snapshot])
    }
    @Test func deletedDecisionsAreRemovedFromBackupAndLateWritesRejected() async throws {
        let dir = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (snapshot, original) = fixture(), repo = RehearsalRepository(directory: dir)
        var record = original
        let cue = snapshot.document.segments[0].id
        record.setPronunciationReview(PronunciationReview(cueID: cue, status: .ignored), cueID: cue)
        let generation = await repo.generation()
        try await repo.save(record, snapshot: snapshot, generation: generation)
        try await repo.delete(id: record.id)
        await #expect(throws: LocalDataError.staleWriter) { try await repo.save(record, snapshot: snapshot, generation: generation) }
        for name in ["rehearsals.json", "rehearsals.backup.json"] {
            let archive = try JSONDecoder().decode(RehearsalRepository.Archive.self, from: Data(contentsOf: dir.appendingPathComponent(name)))
            #expect(archive.records.isEmpty && archive.snapshots.isEmpty)
        }
    }
    @Test func invalidWordCoordinatesCannotOverwriteValidArchive() async throws {
        let dir = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (snapshot, original) = fixture(), repo = RehearsalRepository(directory: dir)
        try await repo.save(original, snapshot: snapshot)
        var invalid = original
        let cue = snapshot.document.segments[0].id
        invalid.setPronunciationReview(PronunciationReview(cueID: cue, span: TextSpan(NSRange(location: Int.max, length: 20)), status: .added), cueID: cue)
        await #expect(throws: RehearsalStorageError.self) { try await repo.save(invalid, snapshot: snapshot) }
        #expect(try await repo.load().archive.records == [original])
    }
}
