import Foundation

public struct FollowEngine: Sendable {
    public let cues: [ScriptCue]
    public private(set) var session: FollowSession
    public private(set) var lastMatch: CueMatcher.Match?
    public private(set) var reading: ReadingProgress
    private let matcher: CueMatcher
    private var candidateIndex: Int?
    private var distinctEvidence = 0
    private var lastTokens: [String] = []
    private var anchorTokens: [String] = []
    private var candidateEnd = 0
    private var lastSequence: UInt64?

    public init(cues: [ScriptCue]) throws {
        self.cues = cues
        session = try FollowSession(cueIDs: cues.map(\.id), maximumForwardStep: 3)
        matcher = CueMatcher(cues: cues)
        reading = ReadingProgress(text: cues[0].text)
    }

    public mutating func resume() { session.resume(); clearEvidence(); reading.suspendPrediction() }
    public mutating func pause() { session.pause(); clearEvidence(); reading.suspendPrediction() }

    public mutating func selectCue(_ id: UUID) {
        if session.selectCue(id) {
            clearEvidence()
            reading = ReadingProgress(text: cues[session.currentIndex].text)
        }
    }

    /// Prepare the next sentence while the speaker is nearing the end of the recognized one.
    /// This is a visual cue only; the recognized anchor stays put until new speech matches it.
    public var preparedCueIndex: Int? {
        guard session.mode == .following, reading.fraction >= 0.72,
              session.currentIndex + 1 < cues.count else { return nil }
        return session.currentIndex + 1
    }

    /// Transcript revisions must come from the exact context captured when the source began.
    public mutating func ingest(_ text: String, isFinal: Bool, token: UUID, sequence: UInt64,
                                observedAt: TimeInterval = 0) {
        guard token == session.contextToken,
              session.mode == .following || session.mode == .holding,
              lastSequence.map({ sequence > $0 }) ?? true else { return }
        lastSequence = sequence
        let tokens = CueMatcher.heardTokens(text)
        guard tokens != lastTokens || isFinal else { return }
        let match = matcher.match(text, currentIndex: session.currentIndex,
                                  currentTokenEnd: reading.confirmedTokenCount,
                                  recoveryTokens: freshTokens(tokens))
        lastMatch = match
        guard let match else {
            reading.suspendPrediction()
            candidateIndex = nil
            distinctEvidence = 0
            lastTokens = tokens
            session.apply(.uncertain, contextToken: token, sequence: sequence)
            return
        }
        if candidateIndex != match.index {
            candidateIndex = match.index
            distinctEvidence = 1
        } else if tokens != lastTokens, match.tokenEnd > candidateEnd {
            distinctEvidence += 1
        }
        candidateEnd = match.tokenEnd
        lastTokens = tokens
        // Near speech remains responsive after a brief hold. Clear unique long-distance
        // evidence may relocate immediately; fuzzy recovery needs growing evidence or a final.
        let confirmed = !match.isRecovery || match.score == 1 || isFinal || distinctEvidence >= 2
        let previousIndex = session.currentIndex
        let evidence: FollowSession.Evidence = confirmed
            ? (match.isRecovery ? .relocatedCue(cues[match.index].id) : .matchedCue(cues[match.index].id)) : .uncertain
        let applied = session.apply(evidence, contextToken: token, sequence: sequence)
        if confirmed && applied {
            if previousIndex != session.currentIndex {
                reading = ReadingProgress(text: cues[session.currentIndex].text, initialRate: reading.tokensPerSecond)
                anchorTokens = tokens
            }
            reading.observe(tokenEnd: match.tokenEnd, at: observedAt)
        }
    }

    /// Only speech newer than the last move may trigger another global relocation. Accounts
    /// for bounded transcript windows; stable tails do not become fresh through old revisions.
    private func freshTokens(_ tokens: [String]) -> [String] {
        guard !anchorTokens.isEmpty else { return tokens }
        let stableCount = min(8, tokens.count, anchorTokens.count)
        if stableCount > 0, tokens.suffix(stableCount).elementsEqual(anchorTokens.suffix(stableCount)) { return [] }
        let prefix = zip(tokens, anchorTokens).prefix(while: { $0 == $1 }).count
        if prefix == anchorTokens.count { return Array(tokens.dropFirst(prefix)) }
        for count in stride(from: min(tokens.count, anchorTokens.count), through: 1, by: -1) {
            if anchorTokens.suffix(count).elementsEqual(tokens.prefix(count)) { return Array(tokens.dropFirst(count)) }
        }
        // A recognizer can start a new utterance or revise its earlier text. Use the changed
        // suffix, never the unchanged prefix before that revision.
        return Array(tokens.dropFirst(prefix))
    }

    private mutating func clearEvidence() {
        candidateIndex = nil
        distinctEvidence = 0
        lastTokens = []
        anchorTokens = []
        candidateEnd = 0
        lastSequence = nil
        lastMatch = nil
    }
}
