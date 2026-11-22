import Foundation

/// Serializes disk mutations. A failed write never publishes an unsaved library in memory.
public actor ScriptLibraryRepository {
    private struct Archive: Codable {
        var schemaVersion = 2
        var documents: [ScriptDocument]
    }
    public struct LoadResult: Sendable {
        public let documents: [ScriptDocument]
        public let recoveredFromBackup: Bool
    }
    private let directory: URL
    private let writeData: @Sendable (Data, URL) throws -> Void
    private var writeGeneration = UUID()
    private var writesSuspended = false
    public func generation() -> UUID { writeGeneration }
    public func suspendWrites() { writesSuspended = true; writeGeneration = UUID() }
    public func resumeWrites() { writesSuspended = false }
    private var deletion: ArchiveDeletion { ArchiveDeletion(directory: directory, name: "library") }
    private var cached: [ScriptDocument]?
    private var validatedData: Data?
    private var primary: URL { directory.appendingPathComponent("library.json") }
    private var backup: URL { directory.appendingPathComponent("library.backup.json") }

    public init(directory: URL) {
        self.directory = directory
        writeData = { try $0.write(to: $1, options: .atomic) }
    }

    init(directory: URL, writeData: @escaping @Sendable (Data, URL) throws -> Void) {
        self.directory = directory; self.writeData = writeData
    }

    public func load() throws -> LoadResult {
        if let pending = try deletion.staged() {
            let documents = try decode(pending)
            try deletion.finish(pending, write: writeData)
            cached = documents; validatedData = pending
        }
        if let cached { return LoadResult(documents: cached, recoveredFromBackup: false) }
        let manager = FileManager.default
        if !manager.fileExists(atPath: primary.path), !manager.fileExists(atPath: backup.path) {
            cached = []
            return LoadResult(documents: [], recoveredFromBackup: false)
        }
        do {
            let data = try Data(contentsOf: primary)
            let documents = try decode(data)
            cached = documents; validatedData = data
            return LoadResult(documents: documents, recoveredFromBackup: false)
        } catch ScriptLibraryError.newerVersion { throw ScriptLibraryError.newerVersion }
        catch {
            // Access/permission errors must not be interpreted as corruption and overwritten.
            if let cocoa = error as? CocoaError, cocoa.code != .fileReadNoSuchFile { throw error }
            do {
                let data = try Data(contentsOf: backup)
                let documents = try decode(data)
                if manager.fileExists(atPath: primary.path) {
                    let quarantined = directory.appendingPathComponent("unreadable-\(UUID().uuidString).json")
                    try manager.copyItem(at: primary, to: quarantined)
                }
                try data.write(to: primary, options: .atomic)
                cached = documents; validatedData = data
                return LoadResult(documents: documents, recoveredFromBackup: true)
            } catch ScriptLibraryError.newerVersion { throw ScriptLibraryError.newerVersion }
            catch { throw ScriptLibraryError.corruptLibrary }
        }
    }

    @discardableResult
    public func save(_ document: ScriptDocument, generation: UUID? = nil) throws -> ScriptDocument {
        guard !writesSuspended, generation == nil || generation == writeGeneration else { throw LocalDataError.staleWriter }
        var documents = try load().documents
        let index = documents.firstIndex(where: { $0.id == document.id })
        if let index {
            guard documents[index].revision == document.revision else { throw ScriptLibraryError.conflict }
        } else if document.revision != 0 { throw ScriptLibraryError.conflict }
        var saved = document
        saved.revision += 1; saved.updatedAt = .now
        if let index { documents[index] = saved } else { documents.append(saved) }
        try commit(documents)
        return saved
    }

    public func delete(id: UUID, revision: Int) throws {
        var documents = try load().documents
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        guard documents[index].revision == revision else { throw ScriptLibraryError.conflict }
        documents.remove(at: index)
        try commitDeletion(documents)
    }

    public func remove(id: UUID) throws {
        let documents = try load().documents.filter { $0.id != id }
        try commitDeletion(documents)
    }
    public func removeAll() throws {
        // Explicit clear-all can also clear an unreadable archive without guessing its data.
        try commitDeletion([])
    }
    private func commitDeletion(_ documents: [ScriptDocument]) throws {
        let data = try JSONEncoder().encode(Archive(documents: documents))
        _ = try decode(data)
        writeGeneration = UUID()
        try deletion.perform(data, write: writeData)
        cached = documents; validatedData = data
    }

    private func commit(_ documents: [ScriptDocument]) throws {
        let data = try JSONEncoder().encode(Archive(documents: documents))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Validate before rotating: never replace a good backup with corrupt bytes.
        let previous = try validatedData ?? JSONEncoder().encode(Archive(documents: cached ?? []))
        try writeData(previous, backup)
        try writeData(data, primary)
        cached = documents; validatedData = data
    }

    private func decode(_ data: Data) throws -> [ScriptDocument] {
        struct Version: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        guard (1...2).contains(try decoder.decode(Version.self, from: data).schemaVersion) else { throw ScriptLibraryError.newerVersion }
        let archive = try decoder.decode(Archive.self, from: data)
        guard Set(archive.documents.map(\.id)).count == archive.documents.count,
              archive.documents.allSatisfy({ doc in
                  doc.revision > 0 && Set(doc.segments.map(\.id)).count == doc.segments.count
                  && Set(doc.pronunciations.map(\.id)).count == doc.pronunciations.count
                  && doc.segments.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
              }) else { throw ScriptLibraryError.corruptLibrary }
        return archive.documents
    }
}
