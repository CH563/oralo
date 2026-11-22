import OraloCore
import SwiftUI
import UIKit

/// TextKit supplies the *laid-out line* of the cursor, including wrapping and Dynamic Type.
/// Updating paint attributes does not rebuild hundreds of SwiftUI sentence views per tick.
struct ScriptReader: UIViewRepresentable {
    let cues: [ScriptCue]
    let recognizedIndex: Int
    let confirmedCharacters: Int
    let position: ReadingCursor.Position
    let fontSize: CGFloat
    let presenting: Bool
    let controlsVisible: Bool
    let reduceMotion: Bool
    var pauseAfter: Set<UUID> = []
    var pronunciations: [UUID: [Pronunciation]] = [:]
    let select: (ScriptCue) -> Void
    let revealControls: () -> Void

    func makeUIView(context: Context) -> ReaderTextView { ReaderTextView() }

    func updateUIView(_ view: ReaderTextView, context: Context) {
        view.update(self)
    }
}

final class ReaderTextView: UITextView, UITextViewDelegate {
    private var configuration: ScriptReader?
    private var cueRanges: [NSRange] = []
    private var cueElements: [ReaderCueElement] = []
    private let focusBand = UIView()
    private let characterMarker = UIView()
    private var focusRange = NSRange(location: 0, length: 0)
    private var lineRect = CGRect.zero
    private var lastSize = CGSize.zero
    private var lastAlignedLine: CGFloat?
    private var browsing = false
    private var paintedRanges: [NSRange] = []
    private var pendingAlignment = false
    private var immediateAlignment = false

    init() {
        let storage = NSTextStorage()
        let layout = PronunciationLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        backgroundColor = .clear
        isEditable = false
        isSelectable = false
        contentInsetAdjustmentBehavior = .never
        textContainerInset = UIEdgeInsets(top: 0, left: 30, bottom: 0, right: 30)
        delegate = self
        accessibilityIdentifier = "script-scroll"
        isAccessibilityElement = false
        focusBand.backgroundColor = UIColor(named: "AccentColor")?.withAlphaComponent(0.12)
        focusBand.layer.cornerRadius = 12
        focusBand.isUserInteractionEnabled = false
        focusBand.isAccessibilityElement = true
        focusBand.accessibilityTraits = .staticText
        focusBand.accessibilityIdentifier = "reading-line"
        insertSubview(focusBand, at: 0)
        characterMarker.isUserInteractionEnabled = false
        characterMarker.isAccessibilityElement = false
        characterMarker.layer.cornerRadius = 4
        insertSubview(characterMarker, aboveSubview: focusBand)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ReaderTextView, _: UITraitCollection) in
            if let configuration = view.configuration { view.paint(configuration); view.setNeedsDisplay() }
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func update(_ next: ScriptReader) {
        let previous = configuration
        configuration = next
        let rebuild = previous?.cues != next.cues || previous?.fontSize != next.fontSize || previous?.pauseAfter != next.pauseAfter || previous?.pronunciations != next.pronunciations
        let presentationChanged = previous?.presenting != next.presenting
        if rebuild { buildText(next) }
        showsVerticalScrollIndicator = !next.presenting
        if rebuild || presentationChanged || previous?.position != next.position ||
            previous?.recognizedIndex != next.recognizedIndex || previous?.confirmedCharacters != next.confirmedCharacters {
            paint(next)
            browsing = false
            // UITextView preserves offsets while processing text-storage edits. Position
            // the line after that layout pass, otherwise its restoration can undo our move.
            pendingAlignment = true
            immediateAlignment = rebuild || presentationChanged
            setNeedsLayout()
        }
        if rebuild || previous?.recognizedIndex != next.recognizedIndex {
            if let oldIndex = previous?.recognizedIndex, cueElements.indices.contains(oldIndex) {
                cueElements[oldIndex].accessibilityTraits = .button
            }
            if cueElements.indices.contains(next.recognizedIndex) {
                cueElements[next.recognizedIndex].accessibilityTraits = [.button, .selected]
            }
        }
    }

    private func buildText(_ configuration: ScriptReader) {
        let result = NSMutableAttributedString()
        cueRanges = []
        var pauseRanges: [NSRange] = []
        var readings: [Pronunciation] = []
        for cue in configuration.cues {
            if result.length > 0 { result.append(NSAttributedString(string: "\n\n")) }
            cueRanges.append(NSRange(location: result.length, length: cue.text.utf16.count))
            for var reading in configuration.pronunciations[cue.id] ?? [] where reading.isAnchored(in: cue.text) {
                reading.span?.location += result.length
                readings.append(reading)
            }
            result.append(NSAttributedString(string: cue.text))
            if configuration.pauseAfter.contains(cue.id) {
                pauseRanges.append(NSRange(location: result.length, length: 2))
                result.append(NSAttributedString(string: " ⏸"))
            }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 8
        result.addAttributes([.font: UIFont.systemFont(ofSize: configuration.fontSize, weight: .medium),
                              .paragraphStyle: paragraph, .foregroundColor: UIColor.secondaryLabel],
                             range: NSRange(location: 0, length: result.length))
        for range in pauseRanges {
            result.addAttributes([.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.secondaryLabel], range: range)
        }
        (layoutManager as? PronunciationLayoutManager)?.configure(readings, in: result,
            font: .systemFont(ofSize: configuration.fontSize, weight: .medium), width: max(80, bounds.width - 60))
        textStorage.setAttributedString(result)
        paintedRanges = []
        cueElements = configuration.cues.enumerated().map { index, cue in
            let element = ReaderCueElement(reader: self, index: index)
            element.accessibilityLabel = String(format: AppCopy.text("Sentence %lld. %@"), index + 1, cue.text)
            element.accessibilityHint = AppCopy.text("Continue from this sentence")
            if let readings = configuration.pronunciations[cue.id], !readings.isEmpty {
                element.accessibilityHint = AppCopy.text("Continue from this sentence.") + " " + readings.map { "\($0.term): \($0.reading)" }.joined(separator: "; ")
                element.accessibilityValue = readings.map { "\($0.term): \($0.reading)" }.joined(separator: "; ")
            }
            element.accessibilityIdentifier = "cue-\(index)"
            element.accessibilityTraits = index == configuration.recognizedIndex ? [.button, .selected] : .button
            return element
        }
        lastAlignedLine = nil
    }

    // UITextView supplies its own accessibility container; override the getter so the
    // semantic cue actions survive its internal text-storage/accessibility refreshes.
    override var accessibilityElements: [Any]? {
        get { [focusBand] + cueElements }
        set { }
    }

    override func accessibilityElementCount() -> Int { cueElements.count + 1 }
    override func accessibilityElement(at index: Int) -> Any? {
        index == 0 ? focusBand : cueElements.indices.contains(index - 1) ? cueElements[index - 1] : nil
    }
    override func index(ofAccessibilityElement element: Any) -> Int {
        if let view = element as? UIView, view === focusBand { return 0 }
        guard let cue = element as? ReaderCueElement,
              let index = cueElements.firstIndex(where: { $0 === cue }) else { return NSNotFound }
        return index + 1
    }

    private func prefixRange(cue index: Int, count: Int) -> NSRange {
        guard let configuration, cueRanges.indices.contains(index) else { return NSRange(location: 0, length: 0) }
        let text = configuration.cues[index].text
        return NSRange(location: cueRanges[index].location, length: text.prefix(max(0, count)).utf16.count)
    }

    private func paint(_ configuration: ScriptReader) {
        guard cueRanges.indices.contains(configuration.position.cueIndex) else { return }
        let accent = configuration.presenting && traitCollection.userInterfaceStyle == .dark ? UIColor(red: 0.74, green: 0.72, blue: 1, alpha: 1)
            : UIColor(named: "AccentColor") ?? .systemIndigo
        textStorage.beginEditing()
        for range in paintedRanges {
            textStorage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range)
            textStorage.removeAttribute(.backgroundColor, range: range)
            textStorage.removeAttribute(.underlineStyle, range: range)
            textStorage.removeAttribute(.underlineColor, range: range)
        }
        paintedRanges = [cueRanges[configuration.recognizedIndex]]
        if configuration.position.cueIndex != configuration.recognizedIndex {
            paintedRanges.append(cueRanges[configuration.position.cueIndex])
        }
        for range in paintedRanges { textStorage.addAttribute(.foregroundColor, value: UIColor.label, range: range) }
        let confirmed = prefixRange(cue: configuration.recognizedIndex, count: configuration.confirmedCharacters)
        textStorage.addAttribute(.foregroundColor, value: accent, range: confirmed)
        let displayed = prefixRange(cue: configuration.position.cueIndex, count: configuration.position.characterCount)
        textStorage.addAttribute(.foregroundColor, value: accent, range: displayed)
        // The estimated tail shares the immediate reading highlight, with an underline to
        // distinguish it from recognition. It never changes the actual session anchor.
        let leadStart = configuration.position.cueIndex == configuration.recognizedIndex ? NSMaxRange(confirmed) : displayed.location
        if NSMaxRange(displayed) > leadStart {
            let lead = NSRange(location: leadStart, length: NSMaxRange(displayed) - leadStart)
            textStorage.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .underlineColor: accent.withAlphaComponent(0.55)], range: lead)
        }
        let text = configuration.cues[configuration.position.cueIndex].text
        let count = min(text.count, max(1, configuration.position.characterCount))
        let start = text.index(text.startIndex, offsetBy: count - 1)
        let end = text.index(after: start)
        let local = NSRange(start..<end, in: text)
        focusRange = NSRange(location: displayed.location + local.location, length: local.length)
        textStorage.addAttribute(.foregroundColor, value: UIColor.label, range: focusRange)
        if configuration.pronunciations.isEmpty {
            textStorage.addAttribute(.backgroundColor, value: accent.withAlphaComponent(0.32), range: focusRange)
        }
        characterMarker.isHidden = configuration.pronunciations.isEmpty
        characterMarker.backgroundColor = accent.withAlphaComponent(0.32)
        textStorage.endEditing()
    }

    override func layoutSubviews() {
        if bounds.width != lastSize.width, let configuration, !configuration.pronunciations.isEmpty {
            buildText(configuration); paint(configuration)
        }
        super.layoutSubviews()
        let sizeChanged = bounds.size != lastSize
        guard sizeChanged || pendingAlignment else { return }
        lastSize = bounds.size
        if sizeChanged { browsing = false } // Rotation returns to the same cursor, without touching speech state.
        pendingAlignment = false
        let immediate = sizeChanged || immediateAlignment
        immediateAlignment = false
        alignLine(force: immediate)
    }

    private func alignLine(force: Bool) {
        guard let configuration, bounds.height > 0, bounds.width > 0, textStorage.length > 0 else { return }
        layoutManager.ensureLayout(for: textContainer)
        let glyph = layoutManager.glyphIndexForCharacter(at: min(focusRange.location, textStorage.length - 1))
        var glyphRange = NSRange()
        lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &glyphRange)
            .offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
        if !configuration.pronunciations.isEmpty, let layout = layoutManager as? PronunciationLayoutManager {
            lineRect = layout.bodyLineRect(at: glyph, font: .systemFont(ofSize: configuration.fontSize, weight: .medium))
                .offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
        }
        focusBand.frame = CGRect(x: 12, y: lineRect.minY - 4, width: max(0, bounds.width - 24), height: lineRect.height + 8)
        if !characterMarker.isHidden {
            let focusGlyphs = layoutManager.glyphRange(forCharacterRange: focusRange, actualCharacterRange: nil)
            let character = layoutManager.boundingRect(forGlyphRange: focusGlyphs, in: textContainer)
            characterMarker.frame = CGRect(x: character.minX + textContainerInset.left, y: lineRect.minY,
                                           width: character.width, height: lineRect.height)
        }
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        focusBand.accessibilityLabel = AppCopy.text("Reading line.") + " " + (textStorage.string as NSString).substring(with: characterRange)
        focusBand.accessibilityValue = String(format: AppCopy.text("Sentence %lld, %lld characters read"), configuration.position.cueIndex + 1, configuration.position.characterCount)
        let desiredY = bounds.height * (configuration.presenting ? 0.34 : 0.25)
        // Keep the actual body line below floating chrome, even on a short landscape
        // viewport with large text. Controls appearing never changes this anchor.
        let rubyClearance: CGFloat = configuration.pronunciations.isEmpty ? 0 : configuration.fontSize * 0.38
        let readingY = configuration.presenting
            ? max(desiredY, min(bounds.height * 0.55, 76 + rubyClearance + lineRect.height / 2)) : desiredY
        // Insets permit the very first and very last lines to reach the same focal position.
        let insets = UIEdgeInsets(top: max(0, readingY - lineRect.height / 2), left: 0,
                                 bottom: max(0, bounds.height - readingY - lineRect.height / 2), right: 0)
        if contentInset != insets { contentInset = insets }
        guard !isDragging, !isDecelerating, !browsing, force || lastAlignedLine != lineRect.midY else { return }
        lastAlignedLine = lineRect.midY
        let offset = CGPoint(x: 0, y: max(-insets.top, min(contentSize.height + insets.bottom - bounds.height,
                                                        lineRect.midY - readingY)))
        let animate = !force && !configuration.reduceMotion && abs(offset.y - contentOffset.y) < bounds.height
        if animate {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.contentOffset = offset
            }
        } else { setContentOffset(offset, animated: false) }
    }

    func cueFrame(_ index: Int) -> CGRect {
        guard cueRanges.indices.contains(index) else { return .zero }
        let glyphs = layoutManager.glyphRange(forCharacterRange: cueRanges[index], actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            .offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
        return UIAccessibility.convertToScreenCoordinates(rect, in: self)
    }

    func activateCue(_ index: Int) {
        guard let configuration else { return }
        if configuration.presenting && !configuration.controlsVisible { configuration.revealControls(); return }
        guard configuration.cues.indices.contains(index) else { return }
        configuration.select(configuration.cues[index])
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let configuration else { return }
        if configuration.presenting && !configuration.controlsVisible { configuration.revealControls(); return }
        let point = gesture.location(in: self)
        let textPoint = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        let glyph = layoutManager.glyphIndex(for: textPoint, in: textContainer)
        guard layoutManager.numberOfGlyphs > glyph,
              layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).insetBy(dx: -12, dy: -4).contains(textPoint)
        else { return }
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        if let index = cueRanges.firstIndex(where: { NSLocationInRange(character, $0) }) { activateCue(index) }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { browsing = true }
}

private final class ReaderCueElement: UIAccessibilityElement {
    private weak var reader: ReaderTextView?
    private let index: Int

    init(reader: ReaderTextView, index: Int) {
        self.reader = reader
        self.index = index
        super.init(accessibilityContainer: reader)
    }

    override var accessibilityFrame: CGRect {
        get { reader?.cueFrame(index) ?? .zero }
        set { }
    }

    override func accessibilityActivate() -> Bool {
        reader?.activateCue(index)
        return reader != nil
    }
}
