import OraloCore
import UIKit

/// Ruby is drawn over the original glyphs. The text storage and cursor offsets remain
/// manuscript-only, so neither recognition nor character highlighting sees IPA/pinyin.
nonisolated final class PronunciationLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    private(set) var readings: [Pronunciation] = []
    private var readingFont = UIFont.systemFont(ofSize: 12, weight: .medium)
    private var availableWidth: CGFloat = 300
    private let readingColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.74, green: 0.72, blue: 1, alpha: 1)
            : UIColor(red: 0.32, green: 0.30, blue: 0.83, alpha: 1)
    }

    override init() { super.init(); delegate = self }
    required init?(coder: NSCoder) { fatalError("Use init()") }

    func configure(_ readings: [Pronunciation], in string: NSMutableAttributedString, font: UIFont, width: CGFloat) {
        self.readings = readings.filter { $0.isAnchored(in: string.string) }.sorted { ($0.span?.location ?? 0) < ($1.span?.location ?? 0) }
        readingFont = .systemFont(ofSize: max(11, font.pointSize * 0.46), weight: .medium)
        availableWidth = max(80, width)
        for reading in self.readings {
            guard let span = reading.span else { continue }
            let base = (reading.term as NSString).size(withAttributes: [.font: font]).width
            let ruby = (reading.reading as NSString).size(withAttributes: [.font: readingFont]).width
            let extra = min(availableWidth, ruby + 4) - base
            if extra > 0 {
                string.addAttribute(.kern, value: extra / CGFloat(max(1, reading.term.count)), range: span.nsRange)
            }
        }
    }

    private func pieces(in characters: NSRange) -> [(NSRange, String)] {
        overlapping(characters).compactMap { reading in
            guard let span = reading.span else { return nil }
            let part = NSIntersectionRange(characters, span.nsRange)
            guard part.length > 0 else { return nil }
            if part == span.nsRange { return (part, reading.reading) }
            // Very long terms can wrap on narrow/large-type screens. Divide the ruby
            // across those fragments instead of shrinking it or painting over neighbours.
            let units = reading.kind == .pinyin ? reading.reading.split(separator: " ").map(String.init)
                : reading.reading.map(String.init)
            guard !units.isEmpty else { return nil }
            let start = (part.location - span.location) * units.count / span.length
            let end = min(units.count, (NSMaxRange(part) - span.location) * units.count / span.length)
            return (part, units[start..<max(start, end)].joined(separator: reading.kind == .pinyin ? " " : ""))
        }
    }

    private func overlapping(_ range: NSRange) -> ArraySlice<Pronunciation> {
        var low = 0, high = readings.count
        while low < high {
            let mid = (low + high) / 2
            if let span = readings[mid].span, NSMaxRange(span.nsRange) <= range.location { low = mid + 1 }
            else { high = mid }
        }
        let start = low
        while low < readings.count, let span = readings[low].span, span.location < NSMaxRange(range) { low += 1 }
        return readings[start..<low]
    }

    private func rubySize(_ text: String, width: CGFloat) -> CGSize {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byCharWrapping; style.alignment = .center
        return (text as NSString).boundingRect(with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                                              options: [.usesLineFragmentOrigin, .usesFontLeading],
                                              attributes: [.font: readingFont, .paragraphStyle: style], context: nil).size
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<CGRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let items = pieces(in: characters)
        guard !items.isEmpty else { return false }
        let reserve = ceil(items.map { rubySize($0.1, width: availableWidth).height }.max() ?? readingFont.lineHeight) + 4
        lineFragmentRect.pointee.size.height += reserve
        lineFragmentUsedRect.pointee.size.height += reserve
        baselineOffset.pointee += reserve
        return true
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
        for reading in overlapping(NSRange(location: charIndex, length: 1)) {
            guard let span = reading.span, charIndex > span.location, charIndex < NSMaxRange(span.nsRange),
                  let textStorage else { continue }
            let width = textStorage.attributedSubstring(from: span.nsRange).size().width
            if width <= availableWidth { return false }
        }
        return true
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard !readings.isEmpty else { return }
        enumerateLineFragments(forGlyphRange: glyphsToShow) { [self] line, _, container, glyphRange, _ in
            let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            for (range, reading) in pieces(in: characters) {
                let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let base = boundingRect(forGlyphRange: glyphs, in: container)
                let natural = (reading as NSString).size(withAttributes: [.font: readingFont]).width
                let width = min(availableWidth, max(base.width, natural + 4))
                let x = max(line.minX, min(base.midX - width / 2, line.maxX - width))
                let rect = CGRect(x: x + origin.x, y: line.minY + origin.y + 1,
                                  width: width, height: ceil(rubySize(reading, width: width).height) + 2)
                let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byCharWrapping
                (reading as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                          attributes: [.font: readingFont, .foregroundColor: readingColor, .paragraphStyle: style], context: nil)
            }
        }
    }

    /// Focal position follows the body, not the extra ruby space above it.
    func bodyLineRect(at glyph: Int, font: UIFont) -> CGRect {
        let line = lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        let position = location(forGlyphAt: glyph)
        return CGRect(x: line.minX, y: line.minY + position.y - font.ascender,
                      width: line.width, height: font.lineHeight)
    }
}
