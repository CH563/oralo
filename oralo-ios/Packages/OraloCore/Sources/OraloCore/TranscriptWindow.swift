import Foundation

/// Bounded in-memory transcript. Revised time ranges replace earlier text instead of appending it.
public struct TranscriptWindow: Sendable {
    private struct Segment: Sendable {
        let start: Double
        let end: Double
        let text: String
    }
    private var segments: [Segment] = []
    public private(set) var latestEnd: Double = 0

    public init() {}

    public mutating func replace(start: Double, end: Double, text: String) -> String? {
        guard start.isFinite, end.isFinite, start >= 0, end > start,
              end >= latestEnd - 12 else { return nil }
        latestEnd = max(latestEnd, end)
        segments.removeAll { $0.end <= latestEnd - 12 || ($0.start < end && start < $0.end) }
        segments.append(Segment(start: start, end: end, text: String(text.suffix(512))))
        segments.sort { $0.start < $1.start }
        if segments.count > 32 { segments.removeFirst(segments.count - 32) }
        return String(segments.map(\.text).joined(separator: " ").suffix(768))
    }
}
