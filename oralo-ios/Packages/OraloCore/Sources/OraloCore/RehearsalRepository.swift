import Foundation

public enum RehearsalStorageError: Error, LocalizedError, Equatable {
    case unreadable, newerVersion, invalidRecord, staleRecord
    public var errorDescription: String? {
        switch self {
        case .unreadable: "Rehearsal records could not be read. Existing files have been kept."
        case .newerVersion: "These records need a newer version of Oralo. Existing files have not been changed."
        case .invalidRecord: "The rehearsal and its script version do not match."
        case .staleRecord: "A newer rehearsal record has already been saved."
        }
    }
}

/// Independent, versioned local storage; no changes to the build 9 manuscript schema.
/// Synchronous actor transactions keep disk work off the UI/audio actor without reentrant writes.
public actor RehearsalRepository {
    public struct Archive: Codable, Sendable {
        public var schemaVersion = 3
        public var records: [RehearsalRecord] = []
        public var snapshots: [RehearsalSnapshot] = []
    }
    public struct LoadResult: Sendable {
        public let archive: Archive
        public let recovered: Bool
    }
    private let directory: URL
    private let write: @Sendable (Data, URL) throws -> Void
    private var writeGeneration = UUID()
    private var writesSuspended = false
    public func generation() -> UUID { writeGeneration }
    public func suspendWrites() { writesSuspended = true; writeGeneration = UUID() }
    public func resumeWrites() { writesSuspended = false }
    private var deletion: ArchiveDeletion { ArchiveDeletion(directory: directory, name: "rehearsals") }
    private var cache: Archive?
    private var validData: Data?
    private var primary: URL { directory.appendingPathComponent("rehearsals.json") }
    private var backup: URL { directory.appendingPathComponent("rehearsals.backup.json") }
    public init(directory: URL) { self.directory = directory; write = { try $0.write(to: $1, options: .atomic) } }
    init(directory: URL, write: @escaping @Sendable (Data, URL) throws -> Void) { self.directory = directory; self.write = write }

    public func load() throws -> LoadResult {
        if let pending = try deletion.staged() {
            let archive = try decode(pending)
            try deletion.finish(pending, write: write)
            cache = archive; validData = pending
        }
        if let cache { return LoadResult(archive: cache, recovered: false) }
        let fm = FileManager.default
        if !fm.fileExists(atPath: primary.path), !fm.fileExists(atPath: backup.path) {
            let empty = Archive(); cache = empty; return LoadResult(archive: empty, recovered: false)
        }
        do {
            let data = try Data(contentsOf: primary), archive = try decode(data)
            cache = archive; validData = data; return LoadResult(archive: archive, recovered: false)
        } catch RehearsalStorageError.newerVersion { throw RehearsalStorageError.newerVersion }
        catch {
            if let cocoa = error as? CocoaError, cocoa.code != .fileReadNoSuchFile { throw error }
            do {
                let data = try Data(contentsOf: backup), archive = try decode(data)
                if fm.fileExists(atPath: primary.path) {
                    try fm.copyItem(at: primary, to: directory.appendingPathComponent("unreadable-\(UUID()).json"))
                }
                try write(data, primary); cache = archive; validData = data
                return LoadResult(archive: archive, recovered: true)
            } catch RehearsalStorageError.newerVersion { throw RehearsalStorageError.newerVersion }
            catch { throw RehearsalStorageError.unreadable }
        }
    }
    public func save(_ record: RehearsalRecord, snapshot: RehearsalSnapshot, generation: UUID? = nil) throws {
        guard !writesSuspended, generation == nil || generation == writeGeneration else { throw LocalDataError.staleWriter }
        var archive = try load().archive
        guard snapshot.id == record.snapshotID, snapshot.document.id == record.scriptID else { throw RehearsalStorageError.invalidRecord }
        if let index = archive.records.firstIndex(where: { $0.id == record.id }) {
            let old = archive.records[index]
            guard record.sequence >= old.sequence, !old.isFinished || record.isFinished else { throw RehearsalStorageError.staleRecord }
            archive.records[index] = record
        } else { archive.records.append(record) }
        if let existing = archive.snapshots.first(where: { $0.id == snapshot.id }) {
            guard existing == snapshot else { throw RehearsalStorageError.invalidRecord }
        } else { archive.snapshots.append(snapshot) }
        try commit(archive)
    }
    public func recoverInterruptedSessions() throws -> LoadResult {
        let loaded = try load()
        var archive = loaded.archive
        if archive.records.contains(where: { !$0.isFinished }) {
            archive.records = archive.records.map { $0.recoveringInterrupted() }
            try commit(archive)
        }
        return LoadResult(archive: archive, recovered: loaded.recovered)
    }
    public func delete(id: UUID) throws {
        var archive = try load().archive
        archive.records.removeAll { $0.id == id }
        try deleteUnreferencedSnapshots(&archive)
    }
    public func delete(scriptID: UUID) throws {
        var archive = try load().archive
        archive.records.removeAll { $0.scriptID == scriptID }
        try deleteUnreferencedSnapshots(&archive)
    }
    public func removeOrphans(liveScriptIDs: Set<UUID>) throws {
        var archive = try load().archive
        guard archive.records.contains(where: { !liveScriptIDs.contains($0.scriptID) }) else { return }
        archive.records.removeAll { !liveScriptIDs.contains($0.scriptID) }
        try deleteUnreferencedSnapshots(&archive)
    }
    private func deleteUnreferencedSnapshots(_ archive: inout Archive) throws {
        let used = Set(archive.records.map(\.snapshotID))
        archive.snapshots.removeAll { !used.contains($0.id) }
        try commit(archive, deleting: true)
    }
    public func clearRehearsals() throws {
        var archive = try load().archive
        archive.records.removeAll { $0.kind == .rehearsal }
        try deleteUnreferencedSnapshots(&archive)
    }
    public func removeAll() throws { try commit(Archive(), deleting: true) }
    private func commit(_ archive: Archive, deleting: Bool = false) throws {
        let data = try JSONEncoder().encode(archive)
        _ = try decode(data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if deleting {
            writeGeneration = UUID()
            try deletion.perform(data, write: write)
        } else {
            try write(validData ?? JSONEncoder().encode(Archive()), backup)
            try write(data, primary)
        }
        cache = archive; validData = data
    }
    private func decode(_ data: Data) throws -> Archive {
        struct Version: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        guard [1, 2, 3].contains(try decoder.decode(Version.self, from: data).schemaVersion) else { throw RehearsalStorageError.newerVersion }
        var archive = try decoder.decode(Archive.self, from: data)
        // Older builds must reject the new event kinds as a newer format, rather than
        // treating them as corruption and restoring an older recovery copy.
        archive.schemaVersion = 3
        guard Set(archive.records.map(\.id)).count == archive.records.count,
              Set(archive.snapshots.map(\.id)).count == archive.snapshots.count else { throw RehearsalStorageError.unreadable }
        for record in archive.records {
            guard let snapshot = archive.snapshots.first(where: { $0.id == record.snapshotID }), snapshot.document.id == record.scriptID,
                  record.activeDuration.isFinite, record.activeDuration >= 0, record.pausedDuration.isFinite, record.pausedDuration >= 0 else { throw RehearsalStorageError.unreadable }
            let ids = Set(snapshot.document.segments.map(\.id))
            let reviews = record.pronunciationReviews ?? []
            guard Set(reviews.map(\.cueID)).count == reviews.count,
                  reviews.allSatisfy({ review in
                      guard ids.contains(review.cueID) else { return false }
                      guard let span = review.span else { return true }
                      guard let cue = snapshot.document.segmentSpans().first(where: { $0.0 == review.cueID })?.1,
                            span.location >= cue.location, span.length > 0,
                            span.location <= NSMaxRange(cue), span.length <= NSMaxRange(cue) - span.location else { return false }
                      return Range(span.nsRange, in: snapshot.document.text) != nil
                  }) else { throw RehearsalStorageError.unreadable }
            guard ids.contains(record.currentCueID), record.events.allSatisfy({ ids.contains($0.cueID) && $0.activeOffset >= 0 && $0.activeOffset.isFinite && $0.duration >= 0 && $0.duration.isFinite }) else { throw RehearsalStorageError.unreadable }
        }
        return archive
    }
}
