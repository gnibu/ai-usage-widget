import AppKit
import Darwin
import Foundation

@main
enum RegressionTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    static func main() {
        testRedHighUsageWindowOutranksGreenWindow()
        testColorTierOutranksPercentage()
        testProcessOutputIsReturned()
        testProcessIsTerminatedAtTimeout()
        testEveryProviderIsSeenBeforeAnyProviderRepeats()
        testExtraSlotsFallBackToTheNextWorstWindow()
        testShippedIconsParse()
        testArcFlagsAreReadOneCharacterWide()
        testWindowInitialSkipsDigits()
        print("All regression tests passed")
    }

    private static func testRedHighUsageWindowOutranksGreenWindow() {
        let green = window(percent: 80, elapsedPercent: 80)
        let red = window(percent: 95, elapsedPercent: 95)
        check(
            Pace.severity(green, now: now) < Pace.severity(red, now: now),
            "95% red window must outrank 80% green window"
        )
    }

    private static func testColorTierOutranksPercentage() {
        let green = window(percent: 80, elapsedPercent: 80)
        let red = window(percent: 50, elapsedPercent: 25)
        check(
            Pace.severity(green, now: now) < Pace.severity(red, now: now),
            "red pace window must outrank higher-percentage green window"
        )
    }

    private static func testProcessOutputIsReturned() {
        let output = Fetcher.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["hello"],
            timeout: 1
        )
        check(
            output.flatMap { String(data: $0, encoding: .utf8) } == "hello",
            "successful helper process must return stdout"
        )
    }

    private static func testProcessIsTerminatedAtTimeout() {
        let startedAt = Date()
        let output = Fetcher.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            timeout: 0.1
        )
        check(output == nil, "timed-out helper process must return nil")
        check(
            Date().timeIntervalSince(startedAt) < 2,
            "timed-out helper process must be terminated promptly"
        )
    }

    // ----------------------------------------------------------------- //
    // What the menu bar speaks for.
    // ----------------------------------------------------------------- //

    private static func testEveryProviderIsSeenBeforeAnyProviderRepeats() {
        // Both of the loud provider's windows outrank the quiet one's.
        let loud = provider(name: "Claude", windows: [
            window(percent: 95, elapsedPercent: 95),
            window(percent: 90, elapsedPercent: 95),
        ])
        let quiet = provider(name: "Codex", windows: [window(percent: 1, elapsedPercent: 50)])
        let report = Report(providers: [loud, quiet])

        let picked = report.busiestWindows(limit: 2, now: now)
        check(
            picked.map(\.provider.name) == ["Claude", "Codex"],
            "a second provider must get a slot before the first provider gets two"
        )
    }

    private static func testExtraSlotsFallBackToTheNextWorstWindow() {
        let loud = provider(name: "Claude", windows: [
            window(percent: 95, elapsedPercent: 95),
            window(percent: 90, elapsedPercent: 95),
        ])
        let quiet = provider(name: "Codex", windows: [window(percent: 1, elapsedPercent: 50)])
        let report = Report(providers: [loud, quiet])

        let picked = report.busiestWindows(limit: 3, now: now)
        check(
            picked.map(\.provider.name) == ["Claude", "Codex", "Claude"],
            "a spare slot must go to the next worst window, whoever owns it"
        )
        check(
            picked.map(\.window.percent) == [95, 1, 90],
            "the repeat slot must be the provider's second worst window"
        )
    }

    // ----------------------------------------------------------------- //
    // Provider marks.
    // ----------------------------------------------------------------- //

    private static func testShippedIconsParse() {
        for file in ["claude.svg", "openai.svg"] {
            guard let directory = BrandGlyph.iconDirectory else {
                check(false, "icon directory must resolve")
                return
            }
            let url = directory.appendingPathComponent(file)
            guard let document = try? String(contentsOf: url, encoding: .utf8) else {
                check(false, "\(file) must be readable — is it still in Resources/Icons?")
                return
            }
            guard let outline = SVGPath.outline(in: document), let path = SVGPath.parse(outline) else {
                check(false, "\(file) must parse into a path")
                return
            }
            // Both marks are authored to fill a 24×24 box; a mangled parse
            // lands well inside it or spills far outside.
            let bounds = path.bounds
            check(
                bounds.minX >= -0.5 && bounds.minY >= -0.5
                    && bounds.maxX <= 24.5 && bounds.maxY <= 24.5,
                "\(file) must stay inside its 24×24 box, got \(bounds)"
            )
            check(
                bounds.width > 20 && bounds.height > 20,
                "\(file) must fill its 24×24 box, got \(bounds)"
            )
        }
    }

    private static func testArcFlagsAreReadOneCharacterWide() {
        // `0 01 10` is two flags and two numbers. Reading the flags as numbers
        // swallows the sweep flag and the arc comes out mirrored.
        guard let glued = SVGPath.parse("M0 0a5 5 0 0110 0"),
              let spaced = SVGPath.parse("M0 0a5 5 0 0 1 10 0")
        else {
            check(false, "an arc with glued flags must parse")
            return
        }
        check(
            abs(glued.bounds.height - spaced.bounds.height) < 0.01,
            "glued arc flags must describe the same arc as spaced ones"
        )
        check(
            abs(spaced.bounds.height - 5) < 0.01,
            "a semicircle of radius 5 must be 5 tall, got \(spaced.bounds.height)"
        )
    }

    private static func testWindowInitialSkipsDigits() {
        // `5h` has to read as `h`; taking the very first character gives `5`,
        // which says nothing about the window at all.
        check(StatusIcon.windowInitial("5h") == "h", "5h must be marked h")
        check(StatusIcon.windowInitial("week") == "w", "week must be marked w")
        check(StatusIcon.windowInitial("spark week") == "s", "spark week must be marked s")
        check(StatusIcon.windowInitial("30") == nil, "a label with no letters gets no mark")
    }

    // ----------------------------------------------------------------- //

    private static func provider(name: String, windows: [UsageWindow]) -> Provider {
        var provider = Provider(name: name)
        provider.ok = true
        provider.windows = windows
        return provider
    }

    private static func window(percent: Double, elapsedPercent: Double) -> UsageWindow {
        let length = 1_000
        let remaining = Double(length) * (1 - elapsedPercent / 100)
        return UsageWindow(
            label: "\(percent)",
            percent: percent,
            resetsAt: Int(now.timeIntervalSince1970 + remaining),
            windowSeconds: length
        )
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
