import Foundation

/// Time is mapped to original UTF-16 manuscript positions, independently of
/// font size, annotations, voice following and the system PiP window size.
public struct FloatingReadingTimeline: Sendable {
    public struct Unit: Sendable {
        public let range: NSRange
        public let start: Double
        public let duration: Double
    }
    public let units: [Unit]
    public let duration: Double
    public let textLength: Int
    public let pauses: [Double]

    public init(document: ScriptDocument, chineseRate: Double = 240, englishRate: Double = 140) {
        let chinese = chineseRate.isFinite ? min(320, max(160, chineseRate)) : 240
        let english = englishRate.isFinite ? min(220, max(100, englishRate)) : 140
        let text = document.text
        var result: [Unit] = [], time = 0.0, index = text.startIndex
        while index < text.endIndex {
            let start = index, character = text[index]
            index = text.index(after: index)
            let han = character.unicodeScalars.contains(where: SpeechText.isHan)
            if character.isLetter && !han {
                while index < text.endIndex {
                    let next = text[index]
                    if next.isLetter && !next.unicodeScalars.contains(where: SpeechText.isHan) { index = text.index(after: index) }
                    else if ["'", "’", "-"].contains(next), text.index(after: index) < text.endIndex,
                            text[text.index(after: index)].isLetter,
                            !text[text.index(after: index)].unicodeScalars.contains(where: SpeechText.isHan) { index = text.index(after: index) }
                    else { break }
                }
            }
            guard han || character.isLetter || character.isNumber else { continue }
            let seconds = 60 / (han || character.isNumber ? chinese : english)
            result.append(Unit(range: NSRange(start..<index, in: text), start: time, duration: seconds))
            time += seconds
        }
        units = result; duration = time; textLength = text.utf16.count
        let marked = Set(document.segments.filter(\.pauseAfter).map(\.id))
        pauses = document.segmentSpans().filter { marked.contains($0.0) }.compactMap { _, span in
            result.last(where: { $0.range.location < NSMaxRange(span) }).map { $0.start + $0.duration }
        }
    }

    public func offset(at time: Double) -> Int {
        guard !units.isEmpty else { return 0 }
        if time >= duration { return textLength }
        var low = 0, high = units.count
        while low < high {
            let mid = (low + high) / 2
            if units[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        return units[max(0, low - 1)].range.location
    }

    public func time(atOffset offset: Int) -> Double {
        guard offset < textLength else { return duration }
        var low = 0, high = units.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(units[mid].range) <= max(0, offset) { low = mid + 1 } else { high = mid }
        }
        return low < units.count ? units[low].start : duration
    }
}

public struct FloatingReadingProgress: Sendable {
    public private(set) var elapsed = 0.0
    public private(set) var isPlaying = false
    public init() {}
    public mutating func play(timeline: FloatingReadingTimeline) { isPlaying = elapsed < timeline.duration && !timeline.units.isEmpty }
    public mutating func pause() { isPlaying = false }
    public mutating func seek(offset: Int, timeline: FloatingReadingTimeline) {
        elapsed = timeline.time(atOffset: offset); isPlaying = false
    }
    /// A suspension or long scheduling gap must never skip unread text on resume.
    public mutating func advance(delta: Double, speed: Double, timeline: FloatingReadingTimeline) {
        guard isPlaying, delta.isFinite, delta > 0, delta <= 0.5, speed.isFinite else { return }
        let next = min(timeline.duration, elapsed + delta * min(2, max(0.5, speed)))
        if let pause = timeline.pauses.first(where: { $0 > elapsed + 0.000_001 && $0 <= next }) {
            elapsed = pause; isPlaying = false
        } else {
            elapsed = next
            if elapsed >= timeline.duration { isPlaying = false }
        }
    }
}
