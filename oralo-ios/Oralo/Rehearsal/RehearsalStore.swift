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
    private(set) var generation = UUID()
    private(set) var validity = UUID()
    var activeSessions: Set<UUID> = []
    func reload(liveScriptIDs: Set<UUID>) async {
        loaded = false; validity = UUID()
        await load(liveScriptIDs: liveScriptIDs)
    }
    init(directory: URL) { repository = RehearsalRepository(directory: directory) }

    func load(liveScriptIDs: Set<UUID>) async {
        guard !loaded else { return }
        do {
            let result = try await repository.recoverInterruptedSessions()
            try await repository.removeOrphans(liveScriptIDs: liveScriptIDs)
            accept(try await repository.load().archive)
            generation = await repository.generation()
            loaded = true; error = nil; recovered = result.recovered
        } catch { self.error = AppCopy.error(error) }
    }
    func save(_ record: RehearsalRecord, snapshot: RehearsalSnapshot, generation lease: UUID, validity expected: UUID) async -> Bool {
        guard expected == validity else { error = AppCopy.error(LocalDataError.staleWriter); return false }
        do {
            try await repository.save(record, snapshot: snapshot, generation: lease)
            guard expected == validity else { return false }
            records.removeAll { $0.id == record.id }; records.insert(record, at: 0)
            snapshots[snapshot.id] = snapshot; error = nil
            return true
        } catch { self.error = AppCopy.error(error); return false }
    }
    func setPronunciationReview(_ value: PronunciationReview?, cueID: UUID, recordID: UUID) async -> Bool {
        guard let index = records.firstIndex(where: { $0.id == recordID }),
              records[index].isFinished, records[index].kind == .rehearsal,
              let snapshot = snapshots[records[index].snapshotID],
              snapshot.document.segments.contains(where: { $0.id == cueID }) else {
            error = AppCopy.error(LocalDataError.staleWriter); return false
        }
        var record = records[index]
        record.setPronunciationReview(value, cueID: cueID)
        return await save(record, snapshot: snapshot, generation: generation, validity: validity)
    }
    func delete(_ record: RehearsalRecord) async {
        guard activeSessions.isEmpty else { return }
        validity = UUID()
        do {
            try await repository.delete(id: record.id)
            generation = await repository.generation()
            accept(try await repository.load().archive); error = nil
        }
        catch { self.error = AppCopy.error(error) }
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
    private let generation: UUID
    private let validity: UUID
    @ObservationIgnored private var timeline: RehearsalTimeline?
    private(set) var record: RehearsalRecord?
    private(set) var saving = false
    private(set) var saveError: String?
    private(set) var savedSequence: UInt64?
    @ObservationIgnored private var persistence: Task<Bool, Never>?
    @ObservationIgnored private var pendingRecord: RehearsalRecord?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var observations: RehearsalObservations
    @ObservationIgnored private var requestOffset: TimeInterval = 0
    var running: Bool { record?.status == .running }
    var saved: Bool { if let record { return savedSequence == record.sequence && saveError == nil }; return false }

    init(document: ScriptDocument, kind: RehearsalRecord.Kind, input: RehearsalRecord.Input, store: RehearsalStore) {
        snapshot = RehearsalSnapshot(document: document); self.kind = kind; self.input = input; self.store = store
        generation = store.generation; validity = store.validity
        observations = RehearsalObservations(document: document)
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
        observations.reset()
        guard running else { return }
        timeline?.pause(interrupted: interrupted, date: .now, uptime: uptime); enqueueSave()
    }
    func observe(cueID: UUID, holding: Bool) {
        timeline?.observe(cueID: cueID, holding: holding, date: .now, uptime: uptime)
    }
    func startVoiceRequest(cueID: UUID) {
        startOrResume(cueID: cueID)
        observations.reset(); requestOffset = duration()
    }
    func observeAudio(level: Float, duration: TimeInterval) {
        guard running, let cue = timeline?.record.currentCueID else { return }
        if let finding = observations.audio(level: level, duration: duration, at: uptime,
                                              activeOffset: self.duration(), cueID: cue) {
            timeline?.appendObservation(finding, date: .now, uptime: uptime)
            enqueueSave()
        }
    }
    func observeFinalized(_ spans: [FinalSpeechSpan]) {
        guard running else { return }
        let findings = observations.finalized(spans, requestOffset: requestOffset)
        for finding in findings { timeline?.appendObservation(finding, date: .now, uptime: uptime) }
        if !findings.isEmpty { enqueueSave() }
    }
    func move(to cueID: UUID, reason: RehearsalEvent.Kind) {
        observations.reset()
        let before = record?.sequence
        timeline?.manualMove(to: cueID, reason: reason, date: .now, uptime: uptime)
        if before != timeline?.record.sequence { enqueueSave() }
    }
    func switchToManual(cueID: UUID) {
        observations.reset()
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
        observations.reset()
        timer?.cancel(); timer = nil
        timeline?.finish(completed: completed, date: .now, uptime: uptime)
        await flush()
    }
    func leave() {
        observations.reset()
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
            succeeded = await store.save(pending, snapshot: snapshot, generation: generation, validity: validity)
            if succeeded { savedSequence = pending.sequence }
            saveError = succeeded ? nil : store.error
        }
        return succeeded
    }
}
