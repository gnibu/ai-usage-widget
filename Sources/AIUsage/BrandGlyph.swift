import AppKit

/// The provider marks drawn in the menu bar, on the card and in the dropdown,
/// read as SVG outlines from `Resources/Icons` rather than as image assets: the
/// files stay legible and replaceable, and one outline scales to any size where
/// a bitmap would need a set.
///
/// Outlines taken from simple-icons, whose packaging is CC0; the marks
/// themselves remain trademarks of their owners. So they are only ever drawn
/// monochrome and scaled uniformly — never tinted, stretched or rotated. Pace
/// colour lives on the ring beside the mark, which is nobody's trademark.
enum BrandGlyph {
    /// Nil for a provider with no mark on file; the caller falls back to a
    /// monogram, which is also what an unreadable or unparseable outline gets.
    ///
    /// `flipped` suits AppKit, whose y runs upwards. SwiftUI's runs downwards,
    /// the same way the outlines are authored, so it asks for the mark as is.
    static func path(for provider: String, fitting box: NSSize, flipped: Bool = true) -> NSBezierPath? {
        guard let file = files[provider.lowercased()] else { return nil }
        guard let parsed = cache.path(for: file) else { return nil }
        return fit(parsed, in: box, flipped: flipped)
    }

    /// Where the outlines live. `build.sh` copies the directory into the
    /// bundle; the environment override is what an unbundled debug run or the
    /// regression tests point at the working copy with.
    static var iconDirectory: URL? {
        if let override = ProcessInfo.processInfo.environment["AI_USAGE_ICONS"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return Bundle.main.resourceURL?.appendingPathComponent("Icons")
    }

    // ----------------------------------------------------------------- //

    /// Codex is OpenAI's, and carries OpenAI's mark.
    private static let files = [
        "claude": "claude.svg",
        "codex": "openai.svg",
    ]

    /// Reading and parsing is a file plus a few hundred segments of curve
    /// maths; the menu bar redraws on every refresh, so the result is kept.
    private static let cache = OutlineCache()

    private final class OutlineCache {
        private var parsed: [String: NSBezierPath?] = [:]
        private let lock = NSLock()

        func path(for file: String) -> NSBezierPath? {
            lock.lock()
            defer { lock.unlock() }
            if let hit = parsed[file] { return hit }
            let path = load(file).flatMap(SVGPath.parse)
            parsed[file] = path
            return path
        }

        private func load(_ file: String) -> String? {
            guard let url = iconDirectory?.appendingPathComponent(file),
                  let document = try? String(contentsOf: url, encoding: .utf8)
            else { return nil }
            return SVGPath.outline(in: document)
        }
    }

    /// Both outlines are authored in a 24×24 box with y running downwards, so
    /// fitting one means centring it on the shorter side, and flipping it for
    /// a caller whose y runs the other way.
    private static func fit(_ path: NSBezierPath, in box: NSSize, flipped: Bool) -> NSBezierPath {
        let side = min(box.width, box.height)
        let scale = side / 24

        var transform = AffineTransform(
            translationByX: (box.width - side) / 2,
            byY: (box.height + (flipped ? side : -side)) / 2
        )
        transform.scale(x: scale, y: flipped ? -scale : scale)

        let copy = path.copy() as! NSBezierPath
        copy.transform(using: transform)
        return copy
    }
}

// --------------------------------------------------------------------- //

/// Just enough of the SVG path grammar for the marks above: moves, lines,
/// cubics, elliptical arcs and close, absolute and relative. Anything else
/// returns nil rather than a mangled outline, and the caller draws a monogram.
enum SVGPath {
    /// The `d` of the first `<path>` in a document. The icons are single-path
    /// by construction, so anything more than that is out of scope: a file we
    /// cannot read this way is one to fix in `Resources/Icons`, not to parse
    /// harder.
    static func outline(in document: String) -> String? {
        guard let attribute = document.range(of: " d=\"") else { return nil }
        let rest = document[attribute.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    static func parse(_ data: String) -> NSBezierPath? {
        var scanner = Scanner(data)
        let path = NSBezierPath()
        path.windingRule = .evenOdd

        var current = NSPoint.zero
        var subpathStart = NSPoint.zero
        var command: Character?

        while let next = scanner.nextCommand(repeating: command) {
            command = next.repeatable
            let relative = next.command.isLowercase
            func point(_ x: Double, _ y: Double) -> NSPoint {
                relative ? NSPoint(x: current.x + x, y: current.y + y) : NSPoint(x: x, y: y)
            }

            switch next.command.lowercased().first! {
            case "m":
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                current = point(x, y)
                subpathStart = current
                path.move(to: current)
            case "l":
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                current = point(x, y)
                path.line(to: current)
            case "h":
                guard let x = scanner.number() else { return nil }
                current = NSPoint(x: relative ? current.x + x : x, y: current.y)
                path.line(to: current)
            case "v":
                guard let y = scanner.number() else { return nil }
                current = NSPoint(x: current.x, y: relative ? current.y + y : y)
                path.line(to: current)
            case "c":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number()
                else { return nil }
                let end = point(x, y)
                path.curve(to: end, controlPoint1: point(x1, y1), controlPoint2: point(x2, y2))
                current = end
            case "a":
                guard let rx = scanner.number(), let ry = scanner.number(),
                      let rotation = scanner.number(),
                      let largeArc = scanner.flag(), let sweep = scanner.flag(),
                      let x = scanner.number(), let y = scanner.number()
                else { return nil }
                let end = point(x, y)
                appendArc(
                    to: path, from: current, to: end,
                    rx: rx, ry: ry, rotation: rotation,
                    largeArc: largeArc, sweep: sweep
                )
                current = end
            case "z":
                path.close()
                current = subpathStart
            default:
                return nil
            }
        }

        // The loop also ends when it meets something it cannot read — an
        // argument with no command to belong to, say. Trailing data means the
        // outline was only partly understood, which is worse than not
        // understanding it at all: half a mark drawn confidently.
        guard scanner.isAtEnd else { return nil }
        return path.isEmpty ? nil : path
    }

    // ----------------------------------------------------------------- //

    /// Endpoint-parameterised arc to the centre form, then out as cubics of at
    /// most a quarter turn each — the error of that approximation is well under
    /// a menu bar pixel. Follows the implementation notes in the SVG spec.
    private static func appendArc(
        to path: NSBezierPath,
        from start: NSPoint,
        to end: NSPoint,
        rx: Double,
        ry: Double,
        rotation: Double,
        largeArc: Bool,
        sweep: Bool
    ) {
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0, start != end else {
            path.line(to: end)
            return
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy

        // Radii too small to span the chord are scaled up until they just fit.
        let oversize = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if oversize > 1 {
            rx *= oversize.squareRoot()
            ry *= oversize.squareRoot()
        }

        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let factor = (largeArc == sweep ? -1.0 : 1.0) * max(0, numerator / denominator).squareRoot()
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2

        let theta = atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
        var sweepAngle = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx) - theta
        if !sweep, sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep, sweepAngle < 0 { sweepAngle += 2 * .pi }

        func on(_ angle: Double) -> NSPoint {
            NSPoint(
                x: cx + rx * cosPhi * cos(angle) - ry * sinPhi * sin(angle),
                y: cy + rx * sinPhi * cos(angle) + ry * cosPhi * sin(angle)
            )
        }
        func slope(_ angle: Double) -> NSPoint {
            NSPoint(
                x: -rx * cosPhi * sin(angle) - ry * sinPhi * cos(angle),
                y: -rx * sinPhi * sin(angle) + ry * cosPhi * cos(angle)
            )
        }

        let steps = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let step = sweepAngle / Double(steps)
        let handle = 4.0 / 3 * tan(step / 4)
        for index in 0..<steps {
            let from = theta + Double(index) * step
            let to = from + step
            let a = on(from), b = on(to)
            let da = slope(from), db = slope(to)
            path.curve(
                to: b,
                controlPoint1: NSPoint(x: a.x + handle * da.x, y: a.y + handle * da.y),
                controlPoint2: NSPoint(x: b.x - handle * db.x, y: b.y - handle * db.y)
            )
        }
    }

    // ----------------------------------------------------------------- //

    /// Path data is written without separators wherever it can be — `1-.5` is
    /// two numbers, and a repeated command letter is left out entirely — so the
    /// scanner has to work a character at a time.
    private struct Scanner {
        private let characters: [Character]
        private var index: Int

        init(_ data: String) {
            characters = Array(data)
            index = 0
        }

        var isAtEnd: Bool {
            mutating get {
                skipSeparators()
                return index >= characters.count
            }
        }

        /// The next command letter, or the previous one when the letter was
        /// elided. A repeated `m` continues as `l`, per the spec.
        ///
        /// `repeatable` is nil for close, which takes no arguments and so has
        /// nothing to repeat over: letting it repeat means a stray argument
        /// after a `z` is never consumed, and the parse loop spins forever on
        /// the same character rather than giving up.
        mutating func nextCommand(repeating previous: Character?) -> (command: Character, repeatable: Character?)? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let character = characters[index]
            if character.isLetter {
                index += 1
                switch character {
                case "m": return (character, "l")
                case "M": return (character, "L")
                case "z", "Z": return (character, nil)
                default: return (character, character)
                }
            }
            guard let previous else { return nil }
            return (previous, previous)
        }

        /// A flag is exactly one character wide, so `0 01.5` is two flags and a
        /// number — reading it as a number would swallow the second flag.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < characters.count else { return nil }
            switch characters[index] {
            case "0": index += 1; return false
            case "1": index += 1; return true
            default: return nil
            }
        }

        mutating func number() -> Double? {
            skipSeparators()
            let start = index
            if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                index += 1
            }
            consumeDigits()
            if index < characters.count, characters[index] == "." {
                index += 1
                consumeDigits()
            }
            if index < characters.count, characters[index] == "e" || characters[index] == "E" {
                index += 1
                if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                    index += 1
                }
                consumeDigits()
            }
            guard index > start else { return nil }
            return Double(String(characters[start..<index]))
        }

        private mutating func consumeDigits() {
            while index < characters.count, characters[index].isNumber {
                index += 1
            }
        }

        private mutating func skipSeparators() {
            while index < characters.count,
                  characters[index] == "," || characters[index].isWhitespace {
                index += 1
            }
        }
    }
}
