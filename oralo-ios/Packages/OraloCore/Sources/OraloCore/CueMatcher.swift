import Foundation

public struct ScriptCue: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }

    /// New revision, new cue identities. Explicit lines remain separate reading blocks.
    public static func parse(_ script: String) -> [ScriptCue] {
        script.components(separatedBy: .newlines).flatMap { line -> [ScriptCue] in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            var sentences: [ScriptCue] = []
            trimmed.enumerateSubstrings(in: trimmed.startIndex..., options: .bySentences) { text, _, _, _ in
                if let text {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { sentences.append(ScriptCue(text: value)) }
                }
            }
            return sentences.isEmpty ? [ScriptCue(text: trimmed)] : sentences
        }
    }
}

/// Tail-anchored text alignment: the newest non-filler token must actually match.
/// Retrieval searches the whole script, while only a small indexed shortlist needs edit distance.
public struct CueMatcher: Sendable {
    public struct TextToken: Equatable, Sendable {
        public let value: String
        public let characters: Range<Int>
    }

    public struct Match: Equatable, Sendable {
        public let index: Int
        public let score: Double
        public let evidenceCount: Int
        public let hasHan: Bool
        public let tokenEnd: Int
        public let isExactPrefix: Bool
        public let isRecovery: Bool
        public var strength: Double { Double(evidenceCount) * (2 * score - 1) }
    }

    private let references: [[String]]
    private let postings: [String: Set<Int>]
    private static let fillers: Set<String> = ["嗯", "呃", "啊", "呢", "呀", "um", "uh"]

    public init(cues: [ScriptCue]) {
        references = cues.map { Self.tokens($0.text) }
        var index: [String: Set<Int>] = [:]
        for (cue, tokens) in references.enumerated() {
            for key in Self.keys(tokens) { index[key, default: []].insert(cue) }
        }
        postings = index
    }

    public func match(_ transcript: String, currentIndex: Int, currentTokenEnd: Int = 0,
                      recoveryTokens: [String]? = nil) -> Match? {
        guard references.indices.contains(currentIndex) else { return nil }
        let heard = Array(Self.heardTokens(transcript).suffix(24))
        let recovery = Array((recoveryTokens ?? heard).suffix(24))
        guard !heard.isEmpty else { return nil }
        var retrieval: [Int: Double] = [:]
        for key in Self.keys(recovery) {
            guard let candidates = postings[key] else { continue }
            let weight = (key.hasPrefix("b:") ? 2.0 : 0.3) + 2 / Double(candidates.count)
            for index in candidates { retrieval[index, default: 0] += weight }
        }
        let ranked = retrieval.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        var indices = Set(ranked.prefix(12).map(\.key))
        indices.insert(currentIndex)
        for index in currentIndex...min(references.count - 1, currentIndex + 3) { indices.insert(index) }
        var matches: [Match] = []
        for index in indices {
            let isRecovery = index < currentIndex || index > currentIndex + 3
            let input = isRecovery ? recovery : heard
            let minimumEnd = index == currentIndex ? currentTokenEnd : 0
            if let candidate = align(input, reference: references[index], index: index,
                                     minimumEnd: minimumEnd, recovery: isRecovery) {
                matches.append(candidate)
            }
        }
        matches.sort { $0.strength == $1.strength ? $0.index < $1.index : $0.strength > $1.strength }
        guard let winner = matches.first else { return nil }
        if matches.count > 1 {
            let runner = matches[1]
            // The full index is also used for short-phrase ambiguity, even when a distant
            // occurrence is too short to qualify as a relocation on its own.
            guard winner.strength - runner.strength >= max(0.9, winner.strength * 0.08) else { return nil }
        }
        if winner.score == 1, winner.evidenceCount < (winner.hasHan ? 6 : 3) {
            let tail = Array(heard.suffix(winner.evidenceCount))
            for other in exactOccurrences(tail) where other != winner.index {
                // Words behind the confirmed cursor cannot pin the next sentence forever.
                if other == currentIndex,
                   !Self.contains(tail, in: references[other], minimumEnd: currentTokenEnd) { continue }
                return nil
            }
        }
        return winner
    }

    public static func tokens(_ text: String) -> [String] { tokenize(text).map(\.value) }
    public static func tokenize(_ text: String) -> [TextToken] { SpeechText.tokenize(text) }
    public static func heardTokens(_ text: String) -> [String] { tokens(text).filter { !fillers.contains($0) } }

    private static func keys(_ tokens: [String]) -> Set<String> {
        var result = Set(tokens.map { "w:" + $0 })
        if tokens.count > 1 {
            for i in 1..<tokens.count { result.insert("b:" + tokens[i - 1] + "\u{1F}" + tokens[i]) }
        }
        return result
    }

    private func exactOccurrences(_ tail: [String]) -> Set<Int> {
        guard let first = tail.first else { return [] }
        let candidates = postings["w:" + first] ?? []
        return Set(candidates.filter { Self.contains(tail, in: references[$0], minimumEnd: 0) })
    }

    private static func contains(_ needle: [String], in reference: [String], minimumEnd: Int) -> Bool {
        guard !needle.isEmpty, needle.count <= reference.count else { return false }
        return (0...(reference.count - needle.count)).contains { start in
            start + needle.count >= minimumEnd && reference[start..<(start + needle.count)].elementsEqual(needle)
        }
    }

    /// One reversed DP pass yields every suffix length. Unlike the old free-tail alignment,
    /// it cannot discard the newest words as insertions and keep matching yesterday's position.
    private func align(_ input: [String], reference: [String], index: Int,
                       minimumEnd: Int, recovery: Bool) -> Match? {
        guard !input.isEmpty, !reference.isEmpty else { return nil }
        let heard = Array(input.reversed())
        let target = Array(reference.reversed())
        let hasHan = input.contains { $0.unicodeScalars.contains(where: SpeechText.isHan) }
        let exactMinimum = recovery ? (hasHan ? 6 : 3) : (hasHan ? 3 : 2)
        let fuzzyMinimum = recovery ? (hasHan ? 8 : 5) : (hasHan ? 5 : 3)
        let threshold = recovery ? 0.78 : 0.72
        let unreachable = 10_000
        var costs = Array(repeating: unreachable, count: target.count + 1)
        var starts = Array(repeating: 0, count: target.count + 1)
        var best: Match?
        for length in 1...min(heard.count, hasHan ? 24 : 12) {
            var row = Array(repeating: unreachable, count: target.count + 1)
            var origins = Array(repeating: 0, count: target.count + 1)
            for j in target.indices {
                if length == 1 {
                    if heard[0] == target[j] { row[j + 1] = 0; origins[j + 1] = j }
                    else { row[j + 1] = row[j] + 1; origins[j + 1] = origins[j] }
                } else {
                    let diagonal = costs[j] + (heard[length - 1] == target[j] ? 0 : 1)
                    let deletion = costs[j + 1] + 1
                    let insertion = row[j] + 1
                    let cost = min(diagonal, deletion, insertion)
                    row[j + 1] = cost
                    origins[j + 1] = cost == diagonal ? starts[j] : (cost == deletion ? starts[j + 1] : origins[j])
                }
                let distance = row[j + 1]
                let end = reference.count - origins[j + 1]
                guard end >= minimumEnd, distance < unreachable else { continue }
                let score = 1 - Double(distance) / Double(length)
                let startsAtBeginning = reference.count - (j + 1) == 0
                let exactPrefix = distance == 0 && startsAtBeginning
                let minimum = distance == 0
                    ? (exactPrefix || minimumEnd > 0 ? exactMinimum : max(exactMinimum, hasHan ? 4 : 3)) : fuzzyMinimum
                // A short, distinctive opening with two matching tokens at both ends can
                // tolerate a small ASR corruption inside (客户返回说明 / 客户反馈说明).
                let bookended = !recovery && hasHan && length >= 6 && startsAtBeginning && end >= 2
                    && input.suffix(length).prefix(2).elementsEqual(reference.prefix(2))
                    && input.suffix(2).elementsEqual(reference[(end - 2)..<end])
                guard length >= minimum, score >= (bookended ? 2.0 / 3.0 : threshold) else { continue }
                let candidate = Match(index: index, score: score, evidenceCount: length, hasHan: hasHan,
                    tokenEnd: end, isExactPrefix: distance == 0 && end == length, isRecovery: recovery)
                if best == nil || candidate.strength > best!.strength
                    || (candidate.strength == best!.strength && (score > best!.score || (score == best!.score && end < best!.tokenEnd))) {
                    best = candidate
                }
            }
            costs = row; starts = origins
        }
        return best
    }
}
