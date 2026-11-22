import AVFoundation
import OraloCore
import UIKit

/// Real text frames for AVKit. No camera, audio track or video file is generated.
@MainActor final class FloatingFrameRenderer {
    static let size = CGSize(width: 960, height: 540)
    private let storage = NSTextStorage()
    private let layout = PronunciationLayoutManager()
    private let container = NSTextContainer(size: CGSize(width: 864, height: CGFloat.greatestFiniteMagnitude))
    private var pool: CVPixelBufferPool?
    private var lines: [(range: NSRange, rect: CGRect)] = []
    private var fontSize: CGFloat = 84

    init() {
        container.lineFragmentPadding = 0
        layout.addTextContainer(container); storage.addLayoutManager(layout)
        let attributes: [CFString: Any] = [kCVPixelBufferWidthKey: 960, kCVPixelBufferHeightKey: 540,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
    }

    func configure(document: ScriptDocument, scale: Double) {
        fontSize = 84 * scale
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * 0.22; paragraph.paragraphSpacing = fontSize * 0.28
        let text = NSMutableAttributedString(string: document.text, attributes: [
            .font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        layout.configure(document.pronunciations.filter(\.showInPresentation), in: text, font: font, width: container.size.width)
        storage.setAttributedString(text); layout.ensureLayout(for: container)
        lines = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { [self] rect, _, _, glyphs, _ in
            lines.append((layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil), rect))
        }
    }

    func frame(elapsed: Double, timeline: FloatingReadingTimeline, timestamp: Double,
               voiceOffset: Int? = nil, caption: String? = nil) -> CMSampleBuffer? {
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 960, height: 540,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            CVPixelBufferUnlockBaseAddress(buffer, []); return nil
        }
        context.translateBy(x: 0, y: 540); context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            UIColor(red: 0.06, green: 0.07, blue: 0.12, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: Self.size))
            if !lines.isEmpty {
                let offset = voiceOffset ?? timeline.offset(at: elapsed)
                let current = lines.lastIndex(where: { $0.range.location <= offset }) ?? 0
                let line = lines[current]
                let next = min(lines.count - 1, current + 1)
                let begin = timeline.time(atOffset: line.range.location)
                let end = next > current ? timeline.time(atOffset: lines[next].range.location) : timeline.duration
                let fraction = voiceOffset == nil && end > begin && next > current ? min(1, max(0, (elapsed - begin) / (end - begin))) : 0
                let scroll = line.rect.minY + (lines[next].rect.minY - line.rect.minY) * fraction - 110
                // A quiet reading lane, never an ASR-confirmed karaoke highlight.
                UIColor(red: 0.45, green: 0.41, blue: 1, alpha: 0.1).setFill()
                UIBezierPath(roundedRect: CGRect(x: 24, y: 94, width: 912, height: min(210, line.rect.height + 16)), cornerRadius: 24).fill()
                let visible = CGRect(x: 0, y: max(0, scroll - fontSize), width: container.size.width, height: 540 + fontSize * 2)
                let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
                context.saveGState(); context.clip(to: CGRect(x: 32, y: caption == nil ? 18 : 62, width: 896, height: caption == nil ? 504 : 460))
                layout.drawGlyphs(forGlyphRange: glyphs, at: CGPoint(x: 48, y: -scroll))
                context.restoreGState()
            }
            if let caption {
                let rect = CGRect(x: 32, y: 14, width: 896, height: 38)
                UIColor(red: 0.06, green: 0.07, blue: 0.12, alpha: 1).setFill(); context.fill(rect)
                (caption as NSString).draw(in: rect.insetBy(dx: 8, dy: 2), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24, weight: .medium), .foregroundColor: UIColor.lightGray])
            }
        }
        UIGraphicsPopContext(); CVPixelBufferUnlockBaseAddress(buffer, [])
        var description: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &description)
        guard let description else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 15),
            presentationTimeStamp: CMTime(seconds: timestamp, preferredTimescale: 60_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: description,
            sampleTiming: &timing, sampleBufferOut: &sample)
        if let sample,
           let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            // Text is a live surface, including while scrolling is paused. Do not
            // wait for a copied PiP timebase before displaying its latest frame.
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sample
    }

    func clear() { storage.setAttributedString(NSAttributedString(string: "")); lines = []; pool = nil }
}
