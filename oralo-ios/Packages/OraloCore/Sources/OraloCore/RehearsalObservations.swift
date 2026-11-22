import Foundation

/// Final, time-indexed recognition evidence. Kept in memory only, never in an archive.
public struct FinalSpeechSpan: Sendable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text; self.start = start; self.end = end
    }
}

/// Passive review observations. Cannot move a cue or alter the reading cursor.
/// Uncertain audio, partial hypotheses and duplicated time ranges produce no conclusions.
public struct RehearsalObservations: Sendable {
    public struct Finding: Equatable, Sendable {
        public let kind: RehearsalEvent.Kind
        public let cueID: UUID
        public let offset: TimeInterval
        public let duration: TimeInterval
    }
    private struct Pattern: Sendable {
        let cueID: UUID
        let tokens: [String]
    }
    private struct Heard: Sendable {
        let token: String
        let start: TimeInterval
        let end: TimeInterval
    }
    private let patterns: [String: [Pattern]]
    private var heard: [Heard] = []
    private var lastEnd: TimeInterval = -1
    private var occurrences: [UUID: TimeInterval] = [:]
    private var lastAudioAt: TimeInterval?
    private var voicedDuration: TimeInterval = 0
    private var quietDuration: TimeInterval = 0
    private var quietCue: UUID?
    private var quietOffset: TimeInterval = 0

    public init(document: ScriptDocument) {
        let candidates = document.segments.map { Pattern(cueID: $0.id, tokens: CueMatcher.tokens($0.text)) }
        let groups = Dictionary(grouping: candidates, by: { $0.tokens })
        // Repeated script sentences have no safe occurrence identity. Short phrases are
        // too easily repeated incidentally; require six Han tokens or three English words.
        let unique = candidates.filter { pattern in
            let han = pattern.tokens.contains { token in token.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } }
            return pattern.tokens.count >= (han ? 6 : 3) && groups[pattern.tokens]?.count == 1
        }
        patterns = Dictionary(grouping: unique, by: { $0.tokens.last! })
    }

    /// Call at every microphone chunk, before UI-meter throttling. Only actual sampled
    /// quiet contributes duration. Missing callbacks, paused capture and startup do not.
    public mutating func audio(level: Float, duration: TimeInterval, at uptime: TimeInterval,
                               activeOffset: TimeInterval, cueID: UUID) -> Finding? {
        guard level.isFinite, duration.isFinite, uptime.isFinite,
              duration > 0, duration <= 0.25 else { resetAudio(); return nil }
        if let lastAudioAt, uptime < lastAudioAt || uptime - lastAudioAt > 0.5 { resetAudio() }
        lastAudioAt = uptime
        if level >= 0.30 {
            let finding: Finding? = quietDuration >= 4 && quietCue != nil
                ? Finding(kind: .silence, cueID: quietCue!, offset: quietOffset, duration: quietDuration) : nil
            quietDuration = 0; quietCue = nil
            voicedDuration = min(1, voicedDuration + duration)
            return finding
        }
        guard level <= 0.20, voicedDuration >= 0.25 else {
            quietDuration = 0; quietCue = nil
            if level > 0.20 { voicedDuration = 0 }
            return nil
        }
        if quietCue == nil {
            quietCue = cueID; quietOffset = max(0, activeOffset - duration)
        }
        quietDuration += duration
        return nil
    }

    /// Accept only finalized, non-overlapping source-audio ranges in a single request.
    /// Exact full-sentence repeats can be reported; partial restarts remain unclassified.
    public mutating func finalized(_ spans: [FinalSpeechSpan], requestOffset: TimeInterval) -> [Finding] {
        var findings: [Finding] = []
        for span in spans.sorted(by: { $0.start < $1.start }) {
            guard span.start.isFinite, span.end.isFinite, span.start >= 0, span.end > span.start,
                  span.start >= lastEnd - 0.001 else { continue }
            guard span.text.count <= 768 else { continue }
            let tokens = CueMatcher.heardTokens(span.text)
            guard !tokens.isEmpty else { continue }
            if span.start - lastEnd > 3 { heard.removeAll(keepingCapacity: true) }
            for token in tokens {
                // Keep actual source ranges. Never manufacture per-character timestamps
                // by evenly dividing a phrase; duplicate words in one range are ambiguous.
                let start = span.start, end = span.end
                heard.append(Heard(token: token, start: start, end: end))
                if heard.count > 400 { heard.removeFirst(heard.count - 400) }
                for pattern in patterns[token] ?? [] where heard.count >= pattern.tokens.count {
                    let suffix = heard.suffix(pattern.tokens.count)
                    guard suffix.map(\.token) == pattern.tokens, let first = suffix.first else { continue }
                    if let previousEnd = occurrences[pattern.cueID], first.start >= previousEnd - 0.001 {
                        findings.append(Finding(kind: .reread, cueID: pattern.cueID,
                                                offset: max(0, requestOffset + first.start), duration: end - first.start))
                    }
                    occurrences[pattern.cueID] = end
                }
            }
            lastEnd = span.end
        }
        return findings
    }

    /// Every pause, manual reposition, interruption and recognition renewal breaks evidence.
    public mutating func reset() {
        resetAudio(); heard.removeAll(keepingCapacity: true)
        occurrences.removeAll(keepingCapacity: true); lastEnd = -1
    }
    private mutating func resetAudio() {
        lastAudioAt = nil; voicedDuration = 0; quietDuration = 0; quietCue = nil
    }
}
