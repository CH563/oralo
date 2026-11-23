import AppKit
import SwiftUI
import OraloCore

struct MacReader: NSViewRepresentable {
    let session: MacSpeechSession
    let fontSize: Double
    let floating: Bool
    let dark: Bool
    var lineSpacing: Double? = nil
    var highlightColor: NSColor? = nil
    var alignment: ManuscriptAlignment = .left
    func makeNSView(context: Context) -> ReadingScrollView {
        let scroll = ReadingScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = !floating
        scroll.autohidesScrollers = true
        scroll.documentView = ReadingTextView()
        scroll.setAccessibilityIdentifier(floating ? "floating-reader" : "presentation-reader")
        return scroll
    }
    func updateNSView(_ scroll: ReadingScrollView, context: Context) {
        (scroll.documentView as? ReadingTextView)?.update(session: session, fontSize: fontSize, floating: floating, dark: dark, lineSpacing: lineSpacing, highlightColor: highlightColor, alignment: alignment.native)
        scroll.layoutReader()
    }
}

final class ReadingScrollView: NSScrollView {
    override func layout() { super.layout(); layoutReader() }
    func layoutReader() { (documentView as? ReadingTextView)?.fit(viewport: contentSize) }
}

final class ReadingTextView: NSTextView {
    private var session: MacSpeechSession?
    private let ruby = PronunciationLayoutManager()
    private var fontSize: CGFloat = 40
    private var floating = false
    private var dark = false
    private var lineSpacing: Double = 12
    private var paragraphAlignment: NSTextAlignment = .left
    private var highlightColor: NSColor?
    private var cueRanges: [NSRange] = []
    private var viewport = CGSize.zero
    private var painted: [NSRange] = []
    private var lastPosition: ReadingCursor.Position?
    private var lastConfirmed = -1
    private var focus = CGRect.zero
    private var marker = CGRect.zero
    private var focusRange = NSRange(location: 0, length: 0)
    private var pending = true
    private var fitting = false
    init() {
        let storage = NSTextStorage(); storage.addLayoutManager(ruby)
        let container = NSTextContainer(containerSize: CGSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false; container.lineFragmentPadding = 0
        ruby.addTextContainer(container)
        super.init(frame: CGRect(x: 0, y: 0, width: 600, height: 600), textContainer: container)
        isEditable = false; isSelectable = false; drawsBackground = false
        isVerticallyResizable = false; isHorizontallyResizable = false
        setAccessibilityLabel(MacCopy.text("演讲正文", "Presentation script"))
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    func update(session: MacSpeechSession, fontSize: Double, floating: Bool, dark: Bool,
                lineSpacing: Double? = nil, highlightColor: NSColor? = nil, alignment: NSTextAlignment = .left) {
        let spacing = (lineSpacing ?? (floating ? 5 : 12)).clamped(to: 0...24)
        let rebuild = self.session !== session || self.fontSize != fontSize || self.dark != dark || self.floating != floating || self.lineSpacing != spacing || self.paragraphAlignment != alignment
        let recolor = self.highlightColor != highlightColor
        self.session = session; self.fontSize = fontSize; self.floating = floating; self.dark = dark
        self.lineSpacing = spacing; self.highlightColor = highlightColor; self.paragraphAlignment = alignment
        if rebuild { buildText(); pending = true }
        if rebuild || recolor || lastPosition != session.readingPosition || lastConfirmed != session.follower.reading.confirmedCharacterCount {
            lastPosition = session.readingPosition; lastConfirmed = session.follower.reading.confirmedCharacterCount
            paint(); pending = true
        }
    }
    private var insetX: CGFloat { floating ? 20 : max(32, (viewport.width - 980) / 2) }
    private var bodyColor: NSColor { dark ? NSColor(red: 1, green: 0.965, blue: 0.902, alpha: 1) : NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1) }
    private var accent: NSColor { highlightColor ?? (dark ? NSColor(red: 0.74, green: 0.72, blue: 1, alpha: 1) : NSColor(red: 0.314, green: 0.337, blue: 0.961, alpha: 1)) }
    private func buildText() {
        guard let session, let textStorage else { return }
        let result = NSMutableAttributedString(string: "")
        cueRanges = []; painted = []
        var readings: [Pronunciation] = []
        for cue in session.snapshot.cues {
            if result.length > 0 { result.append(NSAttributedString(string: floating ? "\n" : "\n\n")) }
            cueRanges.append(NSRange(location: result.length, length: cue.text.utf16.count))
            for var reading in session.snapshot.pronunciations[cue.id] ?? [] where reading.isAnchored(in: cue.text) {
                reading.span?.location += result.length; readings.append(reading)
            }
            result.append(NSAttributedString(string: cue.text))
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = lineSpacing; paragraph.alignment = paragraphAlignment
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        result.addAttributes([.font: font, .foregroundColor: bodyColor.withAlphaComponent(0.60), .paragraphStyle: paragraph], range: NSRange(location: 0, length: result.length))
        ruby.configure(readings, in: result, font: font, width: max(80, viewport.width - 2 * insetX))
        textStorage.setAttributedString(result)
    }
    private func prefix(index: Int, count: Int) -> NSRange {
        guard let session, cueRanges.indices.contains(index) else { return NSRange(location: 0, length: 0) }
        return NSRange(location: cueRanges[index].location, length: session.snapshot.cues[index].text.prefix(max(0, count)).utf16.count)
    }
    private func paint() {
        guard let session, let textStorage, cueRanges.indices.contains(session.readingPosition.cueIndex) else { return }
        textStorage.beginEditing()
        for range in painted {
            textStorage.addAttribute(.foregroundColor, value: bodyColor.withAlphaComponent(0.60), range: range)
            textStorage.removeAttribute(.underlineStyle, range: range)
            textStorage.removeAttribute(.underlineColor, range: range)
        }
        painted = [cueRanges[session.currentIndex]]
        if session.currentIndex != session.readingPosition.cueIndex { painted.append(cueRanges[session.readingPosition.cueIndex]) }
        for range in painted { textStorage.addAttribute(.foregroundColor, value: bodyColor, range: range) }
        let confirmed = prefix(index: session.currentIndex, count: session.follower.reading.confirmedCharacterCount)
        let displayed = prefix(index: session.readingPosition.cueIndex, count: session.readingPosition.characterCount)
        for range in [confirmed, displayed] { textStorage.addAttribute(.foregroundColor, value: accent, range: range) }
        let leadStart = session.currentIndex == session.readingPosition.cueIndex ? NSMaxRange(confirmed) : displayed.location
        if NSMaxRange(displayed) > leadStart {
            textStorage.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: accent.withAlphaComponent(0.55)],
                                     range: NSRange(location: leadStart, length: NSMaxRange(displayed) - leadStart))
        }
        let text = session.snapshot.cues[session.readingPosition.cueIndex].text
        let count = min(text.count, max(1, session.readingPosition.characterCount))
        let start = text.index(text.startIndex, offsetBy: count - 1)
        let end = text.index(after: start)
        let local = NSRange(start..<end, in: text)
        focusRange = NSRange(location: displayed.location + local.location, length: local.length)
        textStorage.addAttribute(.foregroundColor, value: bodyColor, range: focusRange)
        textStorage.endEditing()
        setAccessibilityValue(session.snapshot.cues[session.currentIndex].text)
    }
    func fit(viewport next: CGSize) {
        guard !fitting, next.width > 0, next.height > 0, let textContainer, let textStorage, textStorage.length > 0 else { return }
        fitting = true
        defer { fitting = false }
        let resized = viewport != next
        viewport = next
        guard resized || pending else { return }
        pending = false
        if resized { buildText(); paint() }
        textContainer.containerSize = CGSize(width: max(80, next.width - 2 * insetX), height: CGFloat.greatestFiniteMagnitude)
        let focusY = next.height * 0.34
        textContainerInset = CGSize(width: insetX, height: focusY)
        ruby.ensureLayout(for: textContainer)
        let used = ruby.usedRect(for: textContainer)
        setFrameSize(CGSize(width: next.width, height: max(next.height, used.height + next.height)))
        let glyph = ruby.glyphIndexForCharacter(at: min(focusRange.location, textStorage.length - 1))
        let line = ruby.bodyLineRect(at: glyph, font: .systemFont(ofSize: fontSize, weight: .medium))
            .offsetBy(dx: insetX, dy: focusY)
        focus = CGRect(x: insetX - 8, y: line.minY - 4, width: next.width - 2 * insetX + 16, height: line.height + 8)
        let glyphs = ruby.glyphRange(forCharacterRange: focusRange, actualCharacterRange: nil)
        let rect = ruby.boundingRect(forGlyphRange: glyphs, in: textContainer)
        marker = CGRect(x: rect.minX + insetX, y: line.minY, width: rect.width, height: line.height)
        if let scroll = enclosingScrollView {
            let y = max(0, min(frame.height - next.height, line.midY - focusY))
            scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        accent.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: focus, xRadius: 10, yRadius: 10).fill()
        accent.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: marker, xRadius: 4, yRadius: 4).fill()
        super.draw(dirtyRect)
    }
    override func mouseDown(with event: NSEvent) {
        guard let session, let textContainer else { return }
        let point = convert(event.locationInWindow, from: nil)
        let local = CGPoint(x: point.x - textContainerInset.width, y: point.y - textContainerInset.height)
        let glyph = ruby.glyphIndex(for: local, in: textContainer)
        guard glyph < ruby.numberOfGlyphs, ruby.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).contains(local) else { return }
        let character = ruby.characterIndexForGlyph(at: glyph)
        if let index = cueRanges.firstIndex(where: { NSLocationInRange(character, $0) }) { session.select(index: index) }
    }
}
