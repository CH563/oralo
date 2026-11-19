import Foundation

/// Content is kept once per saved script revision, separately from content-free events.
public struct RehearsalSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let document: ScriptDocument
    public var id: String { "\(document.id.uuidString)-\(document.revision)" }
    public init(document: ScriptDocument) { self.document = document }

    /// Never fuzzy-match a historical passage into an edited script.
    public func editRange(cueID: UUID, in current: ScriptDocument) -> TextSpan? {
        guard current.id == document.id,
              let old = document.segments.first(where: { $0.id == cueID }),
              let now = current.segments.first(where: { $0.id == cueID }), old.text == now.text,
              let range = current.segmentSpans().first(where: { $0.0 == cueID })?.1 else { return nil }
        // Sequence reconciliation cannot establish occurrence identity among repeated sentences
        // after textual edits. Require user choice instead of guessing at the retained UUID.
        if current.text != document.text,
           (document.segments.filter { $0.text == old.text }.count > 1 || current.segments.filter { $0.text == old.text }.count > 1) { return nil }
        return TextSpan(range)
    }
}

public struct RehearsalEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case previous, next, selection, hold, interruption, manualMode }
    public let id: UUID
    public let kind: Kind
    public let cueID: UUID
    public let activeOffset: TimeInterval
    public var duration: TimeInterval
    public init(kind: Kind, cueID: UUID, activeOffset: TimeInterval, duration: TimeInterval = 0) {
        id = UUID(); self.kind = kind; self.cueID = cueID
        self.activeOffset = activeOffset; self.duration = duration
    }
    public var isManualCue: Bool { [.previous, .next, .selection].contains(kind) }
}

public struct RehearsalRecord: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case rehearsal, presentation }
    public enum Input: String, Codable, Sendable { case voice, manual }
    public enum Status: String, Codable, Sendable { case running, paused, completed, unfinished }
    public let id: UUID
    public let scriptID: UUID
    public let snapshotID: String
    public let kind: Kind
    public let initialInput: Input
    public internal(set) var usedVoice = false
    public internal(set) var startedAt: Date
    public internal(set) var updatedAt: Date
    public internal(set) var endedAt: Date?
    public internal(set) var status: Status = .running
    public internal(set) var activeDuration: TimeInterval = 0
    public internal(set) var pausedDuration: TimeInterval = 0
    public internal(set) var currentCueID: UUID
    public internal(set) var events: [RehearsalEvent] = []
    public internal(set) var sequence: UInt64 = 0
    public var manualCount: Int { events.filter(\.isManualCue).count }
    public var holdCount: Int { events.filter { $0.kind == .hold }.count }
    public var isFinished: Bool { status == .completed || status == .unfinished }

    public init(snapshot: RehearsalSnapshot, kind: Kind, input: Input, cueID: UUID, date: Date) {
        id = UUID(); scriptID = snapshot.document.id; snapshotID = snapshot.id
        self.kind = kind; initialInput = input; currentCueID = cueID
        startedAt = date; updatedAt = date
    }
    public func recoveringInterrupted() -> Self {
        guard !isFinished else { return self }
        var result = self
        result.status = .unfinished; result.endedAt = updatedAt; result.sequence += 1
        return result
    }
}

/// Monotonic time is injected: wall-clock changes and background time cannot inflate a session.
public struct RehearsalTimeline: Sendable {
    public private(set) var record: RehearsalRecord
    private var anchor: TimeInterval
    private var holdIndex: Int?
    private var holdingCue: UUID?
    private var holdStarted: TimeInterval?

    public init(snapshot: RehearsalSnapshot, kind: RehearsalRecord.Kind, input: RehearsalRecord.Input,
                cueID: UUID, date: Date, uptime: TimeInterval) {
        record = RehearsalRecord(snapshot: snapshot, kind: kind, input: input, cueID: cueID, date: date)
        anchor = uptime
    }
    public func activeDuration(at uptime: TimeInterval) -> TimeInterval {
        record.activeDuration + (record.status == .running ? max(0, uptime - anchor) : 0)
    }
    public mutating func checkpoint(date: Date, uptime: TimeInterval) {
        guard !record.isFinished else { return }
        let elapsed = max(0, uptime - anchor)
        if record.status == .running { record.activeDuration += elapsed }
        else { record.pausedDuration += elapsed }
        anchor = max(anchor, uptime)
        updateHold(at: record.activeDuration)
        record.updatedAt = date; record.sequence += 1
    }
    public mutating func pause(interrupted: Bool, date: Date, uptime: TimeInterval) {
        guard record.status == .running else { return }
        checkpoint(date: date, uptime: uptime); closeHold()
        record.status = .paused
        if interrupted { append(.interruption, cueID: record.currentCueID) }
    }
    public mutating func resume(date: Date, uptime: TimeInterval) {
        guard record.status == .paused else { return }
        checkpoint(date: date, uptime: uptime); record.status = .running
    }
    public mutating func observe(cueID: UUID, holding: Bool, date: Date, uptime: TimeInterval) {
        guard record.status == .running else { return }
        record.usedVoice = true
        if !holding {
            if holdingCue != nil { checkpoint(date: date, uptime: uptime); closeHold() }
            record.currentCueID = cueID
            return
        }
        if holdingCue == cueID { return }
        checkpoint(date: date, uptime: uptime); closeHold()
        record.currentCueID = cueID; holdingCue = cueID; holdStarted = record.activeDuration
    }
    public mutating func manualMove(to cueID: UUID, reason: RehearsalEvent.Kind, date: Date, uptime: TimeInterval) {
        guard !record.isFinished, cueID != record.currentCueID,
              [.previous, .next, .selection].contains(reason) else { return }
        checkpoint(date: date, uptime: uptime); closeHold()
        record.currentCueID = cueID; append(reason, cueID: cueID)
    }
    public mutating func switchToManual(date: Date, uptime: TimeInterval) {
        guard !record.isFinished else { return }
        checkpoint(date: date, uptime: uptime); closeHold(); append(.manualMode, cueID: record.currentCueID)
    }
    public mutating func finish(completed: Bool, date: Date, uptime: TimeInterval) {
        guard !record.isFinished else { return }
        checkpoint(date: date, uptime: uptime); closeHold()
        record.status = completed ? .completed : .unfinished; record.endedAt = date
    }
    private mutating func append(_ kind: RehearsalEvent.Kind, cueID: UUID) {
        record.events.append(RehearsalEvent(kind: kind, cueID: cueID, activeOffset: record.activeDuration))
    }
    private mutating func updateHold(at time: TimeInterval) {
        guard let holdingCue, let holdStarted else { return }
        let duration = max(0, time - holdStarted)
        // Short recognition revisions are not useful review events. One interval, not one callback.
        guard duration >= 2 else { return }
        if let holdIndex { record.events[holdIndex].duration = duration }
        else {
            record.events.append(RehearsalEvent(kind: .hold, cueID: holdingCue, activeOffset: holdStarted, duration: duration))
            holdIndex = record.events.count - 1
        }
    }
    private mutating func closeHold() { holdIndex = nil; holdingCue = nil; holdStarted = nil }
}
