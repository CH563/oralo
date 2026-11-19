import Foundation
import Observation
import OraloCore

@MainActor @Observable
final class RehearsalStore {
    let repository: RehearsalRepository
    private(set) var records: [RehearsalRecord] = []
    private(set) var snapshots: [String: RehearsalSnapshot] = [:]
    private(set) var loaded = false
    var error: String?
    var recovered = false
    init(directory: URL) { repository = RehearsalRepository(directory: directory) }

    func load(liveScriptIDs: Set<UUID>) async {
        guard !loaded else { return }
        do {
            let result = try await repository.recoverInterruptedSessions()
            try await repository.removeOrphans(liveScriptIDs: liveScriptIDs)
            accept(try await repository.load().archive)
            loaded = true; error = nil; recovered = result.recovered
        } catch { self.error = error.localizedDescription }
    }
    func save(_ record: RehearsalRecord, snapshot: RehearsalSnapshot) async -> Bool {
        do {
            try await repository.save(record, snapshot: snapshot)
            records.removeAll { $0.id == record.id }; records.insert(record, at: 0)
            snapshots[snapshot.id] = snapshot; error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func delete(_ record: RehearsalRecord) async {
        do { try await repository.delete(id: record.id); accept(try await repository.load().archive); error = nil }
        catch { self.error = error.localizedDescription }
    }
    func delete(scriptID: UUID) async throws {
        try await repository.delete(scriptID: scriptID)
        accept(try await repository.load().archive)
    }
    private func accept(_ archive: RehearsalRepository.Archive) {
        records = archive.records.sorted { $0.startedAt > $1.startedAt }
        snapshots = Dictionary(uniqueKeysWithValues: archive.snapshots.map { ($0.id, $0) })
    }
}

/// Owns one live record. Persistence is ordered and batched, never called from an audio tap.
@MainActor @Observable
final class RehearsalRecorder {
    let snapshot: RehearsalSnapshot
    let kind: RehearsalRecord.Kind
    let input: RehearsalRecord.Input
    let store: RehearsalStore
    @ObservationIgnored private var timeline: RehearsalTimeline?
    private(set) var record: RehearsalRecord?
    private(set) var saving = false
    private(set) var saveError: String?
    private(set) var savedSequence: UInt64?
    @ObservationIgnored private var persistence: Task<Bool, Never>?
    @ObservationIgnored private var pendingRecord: RehearsalRecord?
    @ObservationIgnored private var timer: Task<Void, Never>?
    var running: Bool { record?.status == .running }
    var saved: Bool { if let record { return savedSequence == record.sequence && saveError == nil }; return false }

    init(document: ScriptDocument, kind: RehearsalRecord.Kind, input: RehearsalRecord.Input, store: RehearsalStore) {
        snapshot = RehearsalSnapshot(document: document); self.kind = kind; self.input = input; self.store = store
    }
    func startOrResume(cueID: UUID) {
        guard record?.isFinished != true else { return }
        if timeline == nil {
            timeline = RehearsalTimeline(snapshot: snapshot, kind: kind, input: input, cueID: cueID, date: .now, uptime: uptime)
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    self?.checkpoint()
                }
            }
        } else { timeline?.resume(date: .now, uptime: uptime) }
        enqueueSave()
    }
    func pause(interrupted: Bool = false) {
        guard running else { return }
        timeline?.pause(interrupted: interrupted, date: .now, uptime: uptime); enqueueSave()
    }
    func observe(cueID: UUID, holding: Bool) {
        timeline?.observe(cueID: cueID, holding: holding, date: .now, uptime: uptime)
    }
    func move(to cueID: UUID, reason: RehearsalEvent.Kind) {
        let before = record?.sequence
        timeline?.manualMove(to: cueID, reason: reason, date: .now, uptime: uptime)
        if before != timeline?.record.sequence { enqueueSave() }
    }
    func switchToManual(cueID: UUID) {
        if timeline == nil { startOrResume(cueID: cueID) }
        timeline?.switchToManual(date: .now, uptime: uptime)
        startOrResume(cueID: cueID)
    }
    func duration() -> TimeInterval { timeline?.activeDuration(at: uptime) ?? 0 }
    func checkpoint() {
        guard record?.isFinished == false else { return }
        timeline?.checkpoint(date: .now, uptime: uptime); enqueueSave()
    }
    func finish(completed: Bool) async {
        timer?.cancel(); timer = nil
        timeline?.finish(completed: completed, date: .now, uptime: uptime)
        await flush()
    }
    func leave() {
        timer?.cancel(); timer = nil
        guard record?.isFinished == false else { return }
        timeline?.finish(completed: false, date: .now, uptime: uptime); enqueueSave()
    }
    func flush() async {
        enqueueSave()
        _ = await persistence?.value
    }
    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private func enqueueSave() {
        record = timeline?.record
        guard let record else { return }
        // At most one write and one latest checkpoint: a slow disk cannot build a task backlog.
        pendingRecord = record
        guard persistence == nil else { return }
        saving = true
        persistence = Task { await persistPending() }
    }
    private func persistPending() async -> Bool {
        defer { persistence = nil; saving = false }
        var succeeded = false
        while let pending = pendingRecord {
            pendingRecord = nil
            succeeded = await store.save(pending, snapshot: snapshot)
            if succeeded { savedSequence = pending.sequence }
            saveError = succeeded ? nil : store.error
        }
        return succeeded
    }
}
