import AppKit
import SwiftUI

/// The menu bar glyph: one segment per window worth watching, worst first.
/// A segment is up to three parts — the provider mark, a ring filled to that
/// window's consumption, and the percentage — and the user picks which of the
/// three to show.
///
/// Drawn rather than composed from SF Symbols because the tint is the whole
/// point, and a template image would throw the colour away.
enum StatusIcon {
    struct Segment {
        /// Names the provider, so the mark can be looked up.
        var provider: String
        var percent: Double?
        var color: Color
    }

    /// Which parts of a segment to draw. Never empty — the settings pane keeps
    /// the last enabled part switched on.
    struct Parts: OptionSet {
        let rawValue: Int

        static let mark = Parts(rawValue: 1 << 0)
        static let gauge = Parts(rawValue: 1 << 1)
        static let percent = Parts(rawValue: 1 << 2)

        static let all: Parts = [.mark, .gauge, .percent]
    }

    private static let height: CGFloat = 18
    private static let mark: CGFloat = 13
    private static let ring: CGFloat = 14
    private static let partGap: CGFloat = 3
    private static let segmentGap: CGFloat = 7
    private static let lineWidth: CGFloat = 2

    private static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.labelColor,
    ]

    private static let monogramAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: NSColor.labelColor,
    ]

    static func image(segments: [Segment], parts: Parts = .all) -> NSImage {
        // An empty reading still needs something clickable in the menu bar, and
        // an empty part set would leave nothing at all to click.
        let drawn = segments.isEmpty ? [placeholder] : segments
        let parts = parts.isEmpty ? .gauge : parts

        let widths = drawn.map { width(of: $0, parts: parts) }
        let total = widths.reduce(0, +) + segmentGap * CGFloat(drawn.count - 1)

        let image = NSImage(size: NSSize(width: total, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (segment, width) in zip(drawn, widths) {
                draw(segment, parts: parts, atX: x)
                x += width + segmentGap
            }
            return true
        }
        // The ring is meaningful in colour, so it must not be tinted by the bar.
        image.isTemplate = false
        return image
    }

    private static var placeholder: Segment {
        Segment(provider: "", percent: nil, color: .secondary)
    }

    // ----------------------------------------------------------------- //

    private static func width(of segment: Segment, parts: Parts) -> CGFloat {
        var widths: [CGFloat] = []
        if parts.contains(.mark), !segment.provider.isEmpty {
            widths.append(mark)
        }
        if parts.contains(.gauge) {
            widths.append(ring)
        }
        if parts.contains(.percent) {
            widths.append(ceil(label(for: segment.percent).size(withAttributes: textAttributes).width))
        }
        return widths.reduce(0, +) + partGap * CGFloat(max(0, widths.count - 1))
    }

    private static func draw(_ segment: Segment, parts: Parts, atX origin: CGFloat) {
        var x = origin
        var drawn = false
        func space() {
            if drawn { x += partGap }
            drawn = true
        }

        if parts.contains(.mark), !segment.provider.isEmpty {
            space()
            drawMark(segment.provider, atX: x)
            x += mark
        }

        if parts.contains(.gauge) {
            space()
            drawRing(percent: segment.percent, color: segment.color, atX: x)
            x += ring
        }

        if parts.contains(.percent) {
            space()
            let text = label(for: segment.percent)
            let size = text.size(withAttributes: textAttributes)
            text.draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: textAttributes)
        }
    }

    /// Monochrome and to scale — see the trademark note on `BrandGlyph`. A
    /// provider with no mark on file falls back to its initial.
    private static func drawMark(_ provider: String, atX x: CGFloat) {
        let box = NSSize(width: mark, height: mark)
        NSColor.labelColor.setFill()

        if let path = BrandGlyph.path(for: provider, fitting: box) {
            path.transform(using: AffineTransform(translationByX: x, byY: (height - mark) / 2))
            path.fill()
            return
        }

        let initial = String(provider.prefix(1)).uppercased() as NSString
        let size = initial.size(withAttributes: monogramAttributes)
        initial.draw(
            at: NSPoint(x: x + (mark - size.width) / 2, y: (height - size.height) / 2),
            withAttributes: monogramAttributes
        )
    }

    private static func drawRing(percent: Double?, color: Color, atX x: CGFloat) {
        let center = NSPoint(x: x + ring / 2, y: height / 2)
        let radius = (ring - lineWidth) / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.labelColor.withAlphaComponent(0.22).setStroke()
        track.stroke()

        guard let percent else { return }
        let fraction = min(1, max(0, percent / 100))
        guard fraction > 0 else { return }

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - 360 * fraction,
            clockwise: true
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        NSColor(color).setStroke()
        arc.stroke()
    }

    private static func label(for percent: Double?) -> NSString {
        guard let percent else { return "--" }
        return "\(Int(percent.rounded()))%" as NSString
    }
}
