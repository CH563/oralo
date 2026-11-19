import Foundation

/// Position safety rules only. Speech recognition and text matching are not implemented here.
/// Each session is bound to an immutable, ordered list of cue IDs from one draft revision.
public struct FollowSession: Sendable {
    public enum Mode: Equatable, Sendable {
        case ready, following, holding, paused, ended
    }

    public enum ConfigurationError: Error, Equatable {
        case emptyScript, duplicateCueIDs, invalidForwardWindow
    }

    /// The matcher may propose a position only after evaluating the actual speech evidence.
    public enum Evidence: Equatable, Sendable {
        case matchedCue(UUID)
        /// A unique match to fresh speech, checked separately by the whole-script matcher.
        case relocatedCue(UUID)
        case uncertain
    }

    public let cueIDs: [UUID]
    public let maximumForwardStep: Int
    public private(set) var currentIndex = 0
    public private(set) var mode: Mode = .ready

    /// Capture this token when recognition/matching work starts, never when its callback arrives.
    /// A new token invalidates every pending result from the previous audio/matching context.
    public private(set) var contextToken = UUID()
    private var lastSequence: UInt64?

    public var currentCueID: UUID { cueIDs[currentIndex] }

    public init(cueIDs: [UUID], maximumForwardStep: Int = 1) throws {
        guard !cueIDs.isEmpty else { throw ConfigurationError.emptyScript }
        guard Set(cueIDs).count == cueIDs.count else {
            throw ConfigurationError.duplicateCueIDs
        }
        guard (1...3).contains(maximumForwardStep) else {
            throw ConfigurationError.invalidForwardWindow
        }
        self.cueIDs = cueIDs
        self.maximumForwardStep = maximumForwardStep
    }

    /// The coordinator must first obtain permissions and prepare a working recognition source.
    public mutating func resume() {
        guard mode == .ready || mode == .paused else { return }
        invalidateContext()
        mode = .following
    }

    public mutating func pause() {
        guard mode != .ended, mode != .paused else { return }
        invalidateContext()
        mode = .paused
    }

    public mutating func end() {
        guard mode != .ended else { return }
        invalidateContext()
        mode = .ended
    }

    /// Manual navigation never starts a paused or not-yet-started microphone session.
    /// Selecting even the current cue invalidates stale results.
    @discardableResult
    public mutating func selectCue(_ id: UUID) -> Bool {
        guard mode != .ended, let index = cueIDs.firstIndex(of: id) else { return false }
        currentIndex = index
        invalidateContext()
        if mode == .holding { mode = .following }
        return true
    }

    /// Sequence numbers are monotonic per context, assigned to ordered recognition revisions
    /// before asynchronous matching. Reject stale and out-of-order callbacks.
    /// Ordinary matched cues stay within the forward window. Explicit relocation evidence
    /// can move elsewhere; the matcher must first validate fresh, distinctive speech.
    @discardableResult
    public mutating func apply(
        _ evidence: Evidence,
        contextToken token: UUID,
        sequence: UInt64
    ) -> Bool {
        guard mode == .following || mode == .holding,
              token == contextToken,
              lastSequence.map({ sequence > $0 }) ?? true else { return false }
        lastSequence = sequence

        switch evidence {
        case .uncertain:
            mode = .holding
        case .matchedCue(let id):
            guard let index = cueIDs.firstIndex(of: id),
                  index >= currentIndex, index <= currentIndex + maximumForwardStep else { return false }
            currentIndex = index
            mode = .following
        case .relocatedCue(let id):
            guard let index = cueIDs.firstIndex(of: id) else { return false }
            currentIndex = index
            mode = .following
        }
        return true
    }

    private mutating func invalidateContext() {
        contextToken = UUID()
        lastSequence = nil
    }
}
