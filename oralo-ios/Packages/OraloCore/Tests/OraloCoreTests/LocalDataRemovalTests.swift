import Foundation
import Synchronization
import Testing
@testable import OraloCore

struct LocalDataRemovalTests {
    private func directory() -> URL { URL.temporaryDirectory.appendingPathComponent("removal-\(UUID())") }
    private func record(_ document: ScriptDocument, kind: RehearsalRecord.Kind = .rehearsal) -> RehearsalRecord {
        RehearsalRecord(snapshot: RehearsalSnapshot(document: document), kind: kind, input: .manual, cueID: document.segments[0].id, date: .now)
    }
    @Test func deletedScriptCannotReturnFromBackupOrQuarantineAndOtherScriptsSurvive() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let repo = ScriptLibraryRepository(directory: dir)
        let secret = try await repo.save(ScriptDocument(text: "Private deleted sentence."))
        let kept = try await repo.save(ScriptDocument(text: "Keep this talk."))
        try Data("Private deleted sentence.".utf8).write(to: dir.appendingPathComponent("unreadable-old.json"))
        let lease = await repo.generation()
        try await repo.delete(id: secret.id, revision: secret.revision)
        await #expect(throws: LocalDataError.self) { try await repo.save(secret, generation: lease) }
        try Data("broken".utf8).write(to: dir.appendingPathComponent("library.json"))
        let result = try await ScriptLibraryRepository(directory: dir).load()
        #expect(result.documents == [kept])
        for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("Private deleted"))
        }
    }
    @Test func failedDeletionIsResumedBeforeLoadingStalePrimary() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let fail = Mutex(false)
        let repo = ScriptLibraryRepository(directory: dir) { data, url in
            if fail.withLock({ $0 }) && url.lastPathComponent == "library.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        let doc = try await repo.save(ScriptDocument(text: "Erase this."))
        fail.withLock { $0 = true }
        await #expect(throws: CocoaError.self) { try await repo.delete(id: doc.id, revision: doc.revision) }
        await #expect(throws: CocoaError.self) { try await repo.load() }
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("library.deletion.json").path))
        let fresh = ScriptLibraryRepository(directory: dir)
        #expect(try await fresh.load().documents.isEmpty)
        try Data("broken".utf8).write(to: dir.appendingPathComponent("library.json"))
        #expect(try await ScriptLibraryRepository(directory: dir).load().documents.isEmpty)
    }
    @Test func rejectedIntentWriteDoesNotDeleteSavedData() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let repo = ScriptLibraryRepository(directory: dir) { data, url in
            if url.lastPathComponent == "library.deletion.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        let doc = try await repo.save(ScriptDocument(text: "Keep until deletion is accepted."))
        await #expect(throws: CocoaError.self) { try await repo.delete(id: doc.id, revision: doc.revision) }
        #expect(try await ScriptLibraryRepository(directory: dir).load().documents == [doc])
    }
    @Test func clearingRehearsalsKeepsPresentationAndSharedSnapshotButRejectsOldCheckpoint() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let scripts = ScriptLibraryRepository(directory: dir)
        let doc = try await scripts.save(ScriptDocument(text: "Annotated talk."))
        let repo = RehearsalRepository(directory: dir.appendingPathComponent("Rehearsals"))
        let snapshot = RehearsalSnapshot(document: doc), rehearsal = record(doc), presentation = record(doc, kind: .presentation)
        try await repo.save(rehearsal, snapshot: snapshot); try await repo.save(presentation, snapshot: snapshot)
        let lease = await repo.generation()
        try await repo.clearRehearsals()
        await #expect(throws: LocalDataError.self) { try await repo.save(rehearsal, snapshot: snapshot, generation: lease) }
        try Data("broken".utf8).write(to: dir.appendingPathComponent("Rehearsals/rehearsals.json"))
        let result = try await RehearsalRepository(directory: dir.appendingPathComponent("Rehearsals")).load()
        #expect(result.archive.records == [presentation]); #expect(result.archive.snapshots == [snapshot])
    }
    @Test func crossArchiveInterruptedScriptRemovalResumesWithoutRestoringSnapshots() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let fail = Mutex(false), scripts = ScriptLibraryRepository(directory: dir)
        let rehearsalDir = dir.appendingPathComponent("Rehearsals")
        let rehearsals = RehearsalRepository(directory: rehearsalDir) { data, url in
            if fail.withLock({ $0 }) && url.lastPathComponent == "rehearsals.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        let doc = try await scripts.save(ScriptDocument(text: "Gone from every archive."))
        try await rehearsals.save(record(doc), snapshot: RehearsalSnapshot(document: doc))
        let removal = LocalDataRemoval(directory: dir, scripts: scripts, rehearsals: rehearsals)
        let lease = await scripts.generation()
        fail.withLock { $0 = true }
        await #expect(throws: CocoaError.self) { try await removal.prepare(.script(doc.id), revision: doc.revision) }
        #expect(try await removal.pending() == .script(doc.id))
        await #expect(throws: LocalDataError.self) { try await scripts.save(ScriptDocument(text: "Late queued create"), generation: lease) }
        let reopenedScripts = ScriptLibraryRepository(directory: dir), reopenedRehearsals = RehearsalRepository(directory: rehearsalDir)
        let reopened = LocalDataRemoval(directory: dir, scripts: reopenedScripts, rehearsals: reopenedRehearsals)
        try await reopened.prepare(try #require(await reopened.pending())); try await reopened.finish()
        #expect(try await reopened.pending() == nil)
        #expect(try await reopenedScripts.load().documents.isEmpty)
        #expect(try await reopenedRehearsals.load().archive.snapshots.isEmpty)
    }
    @Test func explicitClearAllCanRemoveUnreadableFilesAndOldWritersCannotRepopulate() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let scripts = ScriptLibraryRepository(directory: dir)
        let rehearsals = RehearsalRepository(directory: dir.appendingPathComponent("Rehearsals"))
        let doc = try await scripts.save(ScriptDocument(text: "Private roadmap."))
        let snapshot = RehearsalSnapshot(document: doc), event = record(doc)
        try await rehearsals.save(event, snapshot: snapshot)
        let scriptLease = await scripts.generation(), rehearsalLease = await rehearsals.generation()
        for name in ["library.json", "library.backup.json", "unreadable-content.json"] {
            try Data("Unreadable private roadmap".utf8).write(to: dir.appendingPathComponent(name))
        }
        let removal = LocalDataRemoval(directory: dir, scripts: scripts, rehearsals: rehearsals)
        try await removal.prepare(.all)
        #expect(try await removal.pending() == .all) // preferences must be reset before acknowledging
        try await removal.finish()
        await #expect(throws: LocalDataError.self) { try await scripts.save(ScriptDocument(text: "Stale new draft"), generation: scriptLease) }
        await #expect(throws: LocalDataError.self) { try await rehearsals.save(event, snapshot: snapshot, generation: rehearsalLease) }
        #expect(try await ScriptLibraryRepository(directory: dir).load().documents.isEmpty)
        #expect(try await RehearsalRepository(directory: dir.appendingPathComponent("Rehearsals")).load().archive.snapshots.isEmpty)
        let files = try #require(FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]))
        let urls: [URL] = { files.allObjects.compactMap { $0 as? URL } }()
        for file in urls {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("roadmap"))
            }
        }
        let current = await scripts.generation()
        _ = try await scripts.save(ScriptDocument(text: "A fresh talk."), generation: current)
        #expect(try await scripts.load().documents.count == 1)
    }
    @Test func normalizedPreferencesRoundTripAndRejectInvalidValues() throws {
        var value = ReadingPreferences(fontSize: 1000, appearance: .dark, followsVoice: false, localeID: "en-US")
        #expect(value.fontSize == 48)
        let copy = try JSONDecoder().decode(ReadingPreferences.self, from: JSONEncoder().encode(value))
        #expect(copy == value)
        value.fontSize = .nan; value.localeID = "unsupported"; value.normalize()
        #expect(value.fontSize == 32 && value.localeID == "zh-CN")
    }
}
