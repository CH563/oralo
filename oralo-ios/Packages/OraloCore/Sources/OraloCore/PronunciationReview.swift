import Foundation

/// A user's review decision, not an ASR judgment. No audio or transcript is stored.
public struct PronunciationReview: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case added, kept, ignored }
    public let cueID: UUID
    public let span: TextSpan?
    public let pronunciationID: UUID?
    public let status: Status
    public init(cueID: UUID, span: TextSpan? = nil, pronunciationID: UUID? = nil, status: Status) {
        self.cueID = cueID; self.span = span; self.pronunciationID = pronunciationID; self.status = status
    }
}

extension RehearsalRecord {
    public mutating func setPronunciationReview(_ value: PronunciationReview?, cueID: UUID, date: Date = .now) {
        guard isFinished, kind == .rehearsal else { return }
        var updated = pronunciationReviews ?? []
        updated.removeAll { $0.cueID == cueID }
        if let value, value.cueID == cueID { updated.append(value) }
        pronunciationReviews = updated.isEmpty ? nil : updated
        sequence += 1; updatedAt = date
    }
}
