import AppKit
import SwiftUI

/// The menu bar glyph: a ring filled to the worst window's consumption, tinted
/// by that window's pace, optionally followed by the percentage.
///
/// Drawn rather than composed from SF Symbols because the tint is the whole
/// point, and a template image would throw the colour away.
enum StatusIcon {
    private static let height: CGFloat = 18
    private static let ring: CGFloat = 14
    private static let gap: CGFloat = 3
    private static let lineWidth: CGFloat = 2

    static func image(percent: Double?, color: Color, showText: Bool = true) -> NSImage {
        let tint = NSColor(color)
        let text = showText ? label(for: percent) : nil
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let textSize = text.map { ($0 as NSString).size(withAttributes: attributes) } ?? .zero
        let width = ring + (text == nil ? 0 : gap + ceil(textSize.width))

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let center = NSPoint(x: ring / 2, y: height / 2)
            let radius = (ring - lineWidth) / 2

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.22).setStroke()
            track.stroke()

            if let percent {
                let fraction = min(1, max(0, percent / 100))
                if fraction > 0 {
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
                    tint.setStroke()
                    arc.stroke()
                }
            }

            if let text {
                let origin = NSPoint(
                    x: ring + gap,
                    y: (height - textSize.height) / 2
                )
                (text as NSString).draw(at: origin, withAttributes: attributes)
            }
            return true
        }
        // The ring is meaningful in colour, so it must not be tinted by the bar.
        image.isTemplate = false
        return image
    }

    private static func label(for percent: Double?) -> String {
        guard let percent else { return "--" }
        return "\(Int(percent.rounded()))%"
    }
}
