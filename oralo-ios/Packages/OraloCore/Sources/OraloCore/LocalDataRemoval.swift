import Foundation

public enum LocalDataError: Error, LocalizedError, Sendable {
    case staleWriter, removalInProgress
    public var errorDescription: String? {
        switch self {
        case .staleWriter: "This data has changed or was deleted. Reopen the script before saving."
        case .removalInProgress: "Data removal is unfinished. Retry to finish before making changes."
        }
    }
}

/// A sanitized archive is durable before any old copy is replaced. A failed deletion
/// blocks normal loading until replay succeeds, so backup recovery cannot resurrect it.
struct ArchiveDeletion {
    let directory: URL
    let name: String
    var pending: URL { directory.appendingPathComponent("\(name).deletion.json") }
    func staged() throws -> Data? {
        guard FileManager.default.fileExists(atPath: pending.path) else { return nil }
        return try Data(contentsOf: pending)
    }
    func perform(_ data: Data, write: @Sendable (Data, URL) throws -> Void) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(data, pending)
        try finish(data, write: write)
    }
    func finish(_ data: Data, write: @Sendable (Data, URL) throws -> Void) throws {
        try write(data, directory.appendingPathComponent("\(name).backup.json"))
        try write(data, directory.appendingPathComponent("\(name).json"))
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where file.lastPathComponent.hasPrefix("unreadable-") {
            try FileManager.default.removeItem(at: file)
        }
        try FileManager.default.removeItem(at: pending)
    }
}

/// Coordinates deletion across the manuscript and rehearsal archives. The intent
/// contains no manuscript text. It stays until both archives and preferences finish.
public actor LocalDataRemoval {
    public enum Operation: Codable, Equatable, Sendable {
        case script(UUID), rehearsals, all
    }
    public let scripts: ScriptLibraryRepository
    public let rehearsals: RehearsalRepository
    private let directory: URL
    private var busy = false
    private var intent: URL { directory.appendingPathComponent("removal.json") }
    public init(directory: URL, scripts: ScriptLibraryRepository, rehearsals: RehearsalRepository) {
        self.directory = directory; self.scripts = scripts; self.rehearsals = rehearsals
    }
    public func pending() throws -> Operation? {
        guard FileManager.default.fileExists(atPath: intent.path) else { return nil }
        return try JSONDecoder().decode(Operation.self, from: Data(contentsOf: intent))
    }
    public func prepare(_ operation: Operation, revision: Int? = nil) async throws {
        guard !busy else { throw LocalDataError.removalInProgress }
        busy = true; defer { busy = false }
        await scripts.suspendWrites(); await rehearsals.suspendWrites()
        do {
            if let pending = try pending() {
                guard pending == operation else { throw LocalDataError.removalInProgress }
            } else {
                if case .script(let id) = operation, let revision {
                    let documents = try await scripts.load().documents
                    guard documents.first(where: { $0.id == id })?.revision == revision else { throw ScriptLibraryError.conflict }
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(operation).write(to: intent, options: .atomic)
            }
            switch operation {
            case .script(let id):
                try await scripts.remove(id: id)
                try await rehearsals.delete(scriptID: id)
            case .rehearsals: try await rehearsals.clearRehearsals()
            case .all:
                try await scripts.removeAll()
                try await rehearsals.removeAll()
            }
        } catch {
            // An accepted intent keeps writers suspended until its retry finishes.
            if !FileManager.default.fileExists(atPath: intent.path) {
                await scripts.resumeWrites(); await rehearsals.resumeWrites()
            }
            throw error
        }
    }
    public func finish() async throws {
        guard !busy else { throw LocalDataError.removalInProgress }
        busy = true; defer { busy = false }
        if FileManager.default.fileExists(atPath: intent.path) { try FileManager.default.removeItem(at: intent) }
        await scripts.resumeWrites(); await rehearsals.resumeWrites()
    }
}
