import AppKit

/// The provider marks drawn in the menu bar, read as SVG outlines from
/// `Resources/Icons` rather than as image assets: the files stay legible and
/// replaceable, and one outline scales to any menu bar height where a bitmap
/// would need a set.
///
/// Outlines taken from simple-icons, whose packaging is CC0; the marks
/// themselves remain trademarks of their owners. So they are only ever drawn
/// monochrome and scaled uniformly — never tinted, stretched or rotated. Pace
/// colour lives on the ring beside the mark, which is nobody's trademark.
enum BrandGlyph {
    /// Nil for a provider with no mark on file; the caller falls back to a
    /// monogram, which is also what an unreadable or unparseable outline gets.
    static func path(for provider: String, fitting box: NSSize) -> NSBezierPath? {
        guard let file = files[provider.lowercased()] else { return nil }
        guard let parsed = cache.path(for: file) else { return nil }
        return fit(parsed, in: box)
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
    /// fitting one means flipping it and centring it on the shorter side.
    private static func fit(_ path: NSBezierPath, in box: NSSize) -> NSBezierPath {
        let side = min(box.width, box.height)
        let scale = side / 24

        let transform = AffineTransform(translationByX: (box.width - side) / 2, byY: (box.height + side) / 2)
        var flip = transform
        flip.scale(x: scale, y: -scale)

        let copy = path.copy() as! NSBezierPath
        copy.transform(using: flip)
        return copy
    }

    // Verbatim from simple-icons: icons/claude.svg and icons/openai.svg.
    private static let claudeOutline = "m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"

    private static let openAIOutline = "M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z"
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

        /// The next command letter, or the previous one when the letter was
        /// elided. A repeated `m` continues as `l`, per the spec.
        mutating func nextCommand(repeating previous: Character?) -> (command: Character, repeatable: Character)? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let character = characters[index]
            if character.isLetter {
                index += 1
                switch character {
                case "m": return (character, "l")
                case "M": return (character, "L")
                case "z", "Z": return (character, character)
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
