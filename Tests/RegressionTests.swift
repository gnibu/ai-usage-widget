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
        testBusiestWindowsIgnoreWhoOwnsThem()
        testFairShareGivesEveryProviderASlot()
        testFairShareSpendsSpareSlotsOnTheNextWorstWindow()
        testShippedIconsParse()
        testArcFlagsAreReadOneCharacterWide()
        testWindowInitialSkipsDigits()
        testMenuBarItemIsNeverZeroWidth()
        testStrayArgumentAfterCloseIsRejected()
        testFailedPollKeepsTheLastReading()
        testCarriedReadingIsDroppedOnceItIsOld()
        testCarriedWindowIsDroppedOnceItHasReset()
        testBudgetModeQuotesTheBudget()
        testPaceModeQuotesThePaceIndex()
        testPaceModeSaysNothingWhileTheWindowIsYoung()
        testPaceIsPrintedSoonerThanItIsColoured()
        testPaceReadingIsCapped()
        testTooltipStatesBothReadings()
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

    private static func testBusiestWindowsIgnoreWhoOwnsThem() {
        // Two busy Claude windows and one idle Codex one: asking for the two
        // busiest has to mean exactly that, twice the same provider included.
        let picked = twoProviderReport().busiestWindows(limit: 2, now: now)
        check(
            picked.map(\.provider.name) == ["Claude", "Claude"],
            "the busiest windows must be the busiest, whoever owns them"
        )
        check(
            picked.map(\.window.percent) == [95, 90],
            "the busiest windows must come back in order"
        )
    }

    private static func testFairShareGivesEveryProviderASlot() {
        let picked = twoProviderReport().busiestWindows(limit: 2, fairShare: true, now: now)
        check(
            picked.map(\.provider.name) == ["Claude", "Codex"],
            "fair share must seat a second provider before the first repeats"
        )
    }

    private static func testFairShareSpendsSpareSlotsOnTheNextWorstWindow() {
        let picked = twoProviderReport().busiestWindows(limit: 3, fairShare: true, now: now)
        check(
            picked.map(\.provider.name) == ["Claude", "Codex", "Claude"],
            "a spare slot must go to the next worst window, whoever owns it"
        )
        check(
            picked.map(\.window.percent) == [95, 1, 90],
            "the repeat slot must be the provider's second worst window"
        )
    }

    private static func twoProviderReport() -> Report {
        Report(providers: [
            provider(name: "Claude", windows: [
                window(percent: 95, elapsedPercent: 95),
                window(percent: 90, elapsedPercent: 95),
            ]),
            provider(name: "Codex", windows: [window(percent: 1, elapsedPercent: 50)]),
        ])
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

    private static func testMenuBarItemIsNeverZeroWidth() {
        // The empty reading has no provider to draw a mark for, so a logo-only
        // item would have nothing in it at all. With no Dock tile, that leaves
        // no way back to the settings or to Quit.
        for parts in [StatusIcon.Parts.mark, .gauge, .percent, .window, []] {
            let image = StatusIcon.image(segments: [], parts: parts)
            check(
                image.size.width > 0,
                "an empty reading must stay clickable, got \(image.size) for \(parts)"
            )
        }
    }

    private static func testStrayArgumentAfterCloseIsRejected() {
        // Close takes no arguments, so it has nothing to repeat over. Treating
        // it as repeatable leaves the `1` here forever unconsumed, and the
        // parse loop spins on it instead of giving up.
        check(SVGPath.parse("M0 0Z1") == nil, "a stray argument after close must fail the parse")
        check(SVGPath.parse("M0 0L1 1Z") != nil, "a well-formed close must still parse")
    }

    private static func testWindowInitialSkipsDigits() {
        // `5h` has to read as `h`; taking the very first character gives `5`,
        // which says nothing about the window at all.
        check(StatusIcon.windowInitial("5h") == "h", "5h must be marked h")
        check(StatusIcon.windowInitial("week") == "w", "week must be marked w")
        check(StatusIcon.windowInitial("spark week") == "s", "spark week must be marked s")
        check(StatusIcon.windowInitial("30") == nil, "a label with no letters gets no mark")
    }

    private static func testFailedPollKeepsTheLastReading() {
        let good = Report(
            providers: [provider(name: "Claude", windows: [window(percent: 40, elapsedPercent: 50)])],
            date: now
        )
        var failed = Provider(name: "Claude")
        failed.error = "stored token went stale — run claude once to refresh it"
        // Inside the carried window's own life: a window that has reset is a
        // separate case, and `testCarriedWindowIsDroppedOnceItHasReset` has it.
        let later = now.addingTimeInterval(300)
        let merged = Report(providers: [failed], date: later).carryingOver(from: good, now: later)

        let carried = merged.providers[0]
        check(carried.ok, "a one-off failed poll must not blank the provider out")
        check(carried.stale, "the carried reading must be marked stale")
        check(carried.windows.count == 1, "the last reading's rows must survive")
        check(carried.error != nil, "the reason for the failed poll must still be said")
        check(carried.measuredAt == good.updatedAt, "the carried rows must say when they were measured")
    }

    private static func testCarriedReadingIsDroppedOnceItIsOld() {
        let good = Report(
            providers: [provider(name: "Claude", windows: [window(percent: 40, elapsedPercent: 50)])],
            date: now
        )
        let later = now.addingTimeInterval(Report.carryLimit + 60)
        var failed = Provider(name: "Claude")
        failed.error = "the service is not answering (http 503)"
        let merged = Report(providers: [failed], date: later).carryingOver(from: good, now: later)

        check(!merged.providers[0].ok, "a reading older than the carry limit must not be shown as usable")
        check(merged.providers[0].windows.isEmpty, "stale-beyond-limit rows must be dropped")
    }

    private static func testCarriedWindowIsDroppedOnceItHasReset() {
        // 94% of a five-hour window that resets a minute from now. Once it has,
        // the quota is empty and carrying the old number would keep the menu bar
        // red — and the verdict at "nearly out" — through the fresh window.
        let spent = UsageWindow(
            label: "5h",
            percent: 94,
            resetsAt: Int(now.timeIntervalSince1970) + 60,
            windowSeconds: 18_000
        )
        let week = UsageWindow(
            label: "week",
            percent: 30,
            resetsAt: Int(now.timeIntervalSince1970) + 86_400,
            windowSeconds: 604_800
        )
        let good = Report(providers: [provider(name: "Claude", windows: [spent, week])], date: now)

        let later = now.addingTimeInterval(120)
        var failed = Provider(name: "Claude")
        failed.error = "stored token went stale — run claude once"
        let merged = Report(providers: [failed], date: later).carryingOver(from: good, now: later)

        let carried = merged.providers[0]
        check(carried.ok && carried.stale, "the windows that have not reset must still be carried")
        check(
            carried.windows.map(\.label) == ["week"],
            "a window carried past its own reset must be dropped"
        )

        // And with nothing left to carry, the provider goes back to having no
        // reading rather than to an empty one that still counts as usable.
        let onlySpent = Report(providers: [provider(name: "Claude", windows: [spent])], date: now)
        let emptied = Report(providers: [failed], date: later).carryingOver(from: onlySpent, now: later)
        check(!emptied.providers[0].ok, "a provider whose every carried window has reset is not ok")
    }

    private static func testBudgetModeQuotesTheBudget() {
        // Half the budget a quarter of the way in — 50 against the budget, 200
        // against the clock. Budget mode must not be tempted by the latter.
        let reading = Pace.reading(window(percent: 50, elapsedPercent: 25), mode: .budget, now: now)
        check(reading.text == "50%", "budget mode must quote the budget, got \(reading.text)")
        check(reading.hasValue, "a budget reading always has a value")
    }

    private static func testPaceModeQuotesThePaceIndex() {
        let reading = Pace.reading(window(percent: 50, elapsedPercent: 25), mode: .pace, now: now)
        check(reading.text == "200%", "pace mode must quote the pace index, got \(reading.text)")
        check(reading.hasValue, "a pace index that exists is a value")
    }

    private static func testPaceModeSaysNothingWhileTheWindowIsYoung() {
        // The budget number must NOT stand in here. Both readings share one
        // column, so a budget percentage printed under a pace heading is
        // indistinguishable from a pace one and quietly means something else —
        // which is exactly how "2% of pace" and "2% of budget" came to look
        // like the same reading for a window that had just reset.
        let reading = Pace.reading(window(percent: 3, elapsedPercent: 0.5), mode: .pace, now: now)
        check(
            reading.text == Pace.noReading,
            "a window too young for a pace must print a dash, got \(reading.text)"
        )
        check(!reading.hasValue, "an absent pace must not claim to have a value")
        check(reading.text != "3%", "the budget number must never stand in for a pace")
    }

    private static func testPaceIsPrintedSoonerThanItIsColoured() {
        // Between the two floors: settled enough to print next to the reset
        // time that explains it, not settled enough to recolour the row or to
        // decide which window the menu bar speaks for.
        let young = window(percent: 2, elapsedPercent: 2)
        check(
            Pace.reading(young, mode: .pace, now: now).text == "100%",
            "a window past the display floor must print its pace"
        )
        check(
            Pace.ratio(young, now: now) == nil,
            "the same window must still be too young to be given a severity tier"
        )
    }

    private static func testPaceReadingIsCapped() {
        // 100% of the budget spent in 5% of the window is 2000% of pace, which
        // would widen the menu bar item without telling the reader anything.
        let reading = Pace.reading(window(percent: 100, elapsedPercent: 5), mode: .pace, now: now)
        check(reading.text == "999%", "a runaway pace must be capped, got \(reading.text)")
    }

    private static func testTooltipStatesBothReadings() {
        let tooltip = Pace.tooltip(
            source: "Claude 5h",
            window: window(percent: 50, elapsedPercent: 25),
            now: now
        )
        for expected in ["Claude 5h", "200% of pace", "50% of the budget", "25% of the window"] {
            check(tooltip.contains(expected), "tooltip must state \(expected), got: \(tooltip)")
        }

        // With no pace to state it has to say why rather than quote a number.
        let young = Pace.tooltip(source: nil, window: window(percent: 3, elapsedPercent: 2), now: now)
        check(!young.contains("of pace"), "a window with no pace must not be given one")
        check(young.contains("3% of the budget"), "the budget is stated either way")
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
