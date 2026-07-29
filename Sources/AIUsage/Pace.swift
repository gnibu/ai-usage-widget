import SwiftUI

/// Pace maths and formatting, shared by the panel, the menu bar icon and the
/// notification rules. One implementation so that every surface judges a
/// window identically.
enum Pace {
    static let good = Color(red: 0.369, green: 0.788, blue: 0.541)   // #5ec98a
    static let warn = Color(red: 1.000, green: 0.706, blue: 0.329)   // #ffb454
    static let bad = Color(red: 1.000, green: 0.420, blue: 0.420)    // #ff6b6b

    /// The three shades a filled track is drawn in. The flat colour is what the
    /// menu bar and the ring use; the gradient is what gives the fill in a
    /// recessed groove its curvature.
    struct Palette {
        let base: Color
        let top: Color
        let bottom: Color

        var fill: LinearGradient {
            LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
        }
    }

    static let idleFill = LinearGradient(
        colors: [.white.opacity(0.5), .white.opacity(0.3)],
        startPoint: .top,
        endPoint: .bottom
    )

    struct Severity: Comparable {
        let tier: Int
        let percent: Double
        let pace: Double

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.percent != rhs.percent { return lhs.percent < rhs.percent }
            return lhs.pace < rhs.pace
        }
    }

    /// Share of the window already elapsed, 0-100. Nil when the window length
    /// or reset time is unknown, in which case absolute thresholds are used.
    static func elapsedPercent(_ window: UsageWindow, now: Date = Date()) -> Double? {
        guard let resetsAt = window.resetsAt, let length = window.windowSeconds, length > 0 else {
            return nil
        }
        let remaining = Double(resetsAt) - now.timeIntervalSince1970
        let elapsed = Double(length) - remaining
        return min(100, max(0, elapsed / Double(length) * 100))
    }

    /// Share of the window that has to be gone before a pace ratio is quoted at
    /// all. Spending divided by a very small elapsed share swings wildly from
    /// one poll to the next, so early on the answer is "not yet" rather than a
    /// number that will look different in a minute.
    ///
    /// Two floors because the two uses can bear different amounts of noise. The
    /// severity tier picks the colour of a row and the window the menu bar
    /// speaks for, so it waits for the ratio to settle. A printed percentage is
    /// read once, next to the reset time that explains why it is early, and
    /// holding it back to match the colour left freshly reset windows with
    /// nothing to say for hours.
    static let severityFloor: Double = 5
    static let displayFloor: Double = 1

    /// How far ahead of an even burn the window is. 1.0 is exactly on pace.
    /// Nil before the window has run long enough for the ratio to mean anything.
    static func ratio(_ window: UsageWindow, floor: Double = severityFloor, now: Date = Date()) -> Double? {
        guard let elapsed = elapsedPercent(window, now: now), elapsed >= floor else { return nil }
        return window.percent / elapsed
    }

    /// The same reading as a percentage, which is how the summary states it:
    /// spending measured against the even-burn mark on the track rather than
    /// against the whole budget. 100 sits exactly on the mark, 150 is half
    /// again past it. Nil while the mark is still too early to mean anything.
    static func paceIndex(
        _ window: UsageWindow,
        floor: Double = severityFloor,
        now: Date = Date()
    ) -> Double? {
        ratio(window, floor: floor, now: now).map { $0 * 100 }
    }

    /// Which number the percentages quote. The gauges are unaffected either
    /// way: a ring or a track always fills to the share of the budget spent,
    /// because that is the only one of the two readings with an end to it.
    enum PercentMode: String, CaseIterable {
        /// How much of the budget is gone. 100% is the budget spent.
        case budget
        /// How that spending compares with an even burn. 100% sits exactly on
        /// the even-burn mark, which is the white notch on the tracks.
        case pace
    }

    /// A pace reading early in a window is a small number over a smaller one
    /// and runs to four figures. Past this the exact value says nothing the cap
    /// does not, and in the menu bar it would widen the item a digit at a time.
    static let paceCeiling: Double = 999

    /// What a column shows for a window that has no pace yet. Not the budget
    /// number: the two readings share one column, so a budget percentage
    /// printed under a "pace" heading is indistinguishable from a pace one and
    /// silently means something else. The track beside it still fills to the
    /// budget, and the reset time beside that says why the window is early.
    static let noReading = "—"

    /// The percentage a surface prints, and whether there was one to print.
    struct Reading {
        let text: String
        /// False when the window is too young for a pace and pace was asked
        /// for. The surfaces dim it, so an absent reading is not mistaken for
        /// a very small one.
        let hasValue: Bool
    }

    static func reading(_ window: UsageWindow, mode: PercentMode, now: Date = Date()) -> Reading {
        guard mode == .pace else {
            return Reading(text: "\(Int(window.percent.rounded()))%", hasValue: true)
        }
        guard let index = paceIndex(window, floor: displayFloor, now: now) else {
            return Reading(text: noReading, hasValue: false)
        }
        return Reading(text: "\(Int(min(paceCeiling, index).rounded()))%", hasValue: true)
    }

    /// What a pace percentage is measured against. Said once per tooltip, not
    /// once per window in it.
    static let paceExplainer = "100% of pace is spending exactly in step with the clock."

    /// The line behind the menu bar item. A bare "142%" cannot say which of the
    /// two readings it is, so the tooltip states both and how far into the
    /// window they were taken.
    ///
    /// `explains` appends `paceExplainer`; leave it off when several of these
    /// are being stacked and the caller adds the sentence itself.
    static func tooltip(
        source: String?,
        window: UsageWindow,
        explains: Bool = true,
        now: Date = Date()
    ) -> String {
        let spent = "\(Int(window.percent.rounded()))% of the budget spent"
        let lead = source.map { "\($0) — " } ?? ""

        guard let index = paceIndex(window, now: now), let elapsed = elapsedPercent(window, now: now)
        else {
            return "\(lead)\(spent). Too early in the window to judge the pace."
        }
        let reading = """
            \(lead)\(Int(index.rounded()))% of pace · \(spent), \
            \(Int(elapsed.rounded()))% of the window gone.
            """
        return explains ? "\(reading) \(paceExplainer)" : reading
    }

    /// Green while spending is at or under the even-burn pace, orange when
    /// running ahead of it, red when far ahead or nearly exhausted.
    static func color(_ window: UsageWindow, now: Date = Date()) -> Color {
        switch severityTier(window, now: now) {
        case 2: return bad
        case 1: return warn
        default: return good
        }
    }

    static func palette(_ window: UsageWindow, now: Date = Date()) -> Palette {
        switch severityTier(window, now: now) {
        case 2:
            return Palette(
                base: bad,
                top: Color(red: 1.000, green: 0.604, blue: 0.604),   // #ff9a9a
                bottom: Color(red: 0.902, green: 0.310, blue: 0.310)  // #e64f4f
            )
        case 1:
            return Palette(
                base: warn,
                top: Color(red: 1.000, green: 0.816, blue: 0.541),   // #ffd08a
                bottom: Color(red: 0.941, green: 0.604, blue: 0.188)  // #f09a30
            )
        default:
            return Palette(
                base: good,
                top: Color(red: 0.549, green: 0.910, blue: 0.678),   // #8ce8ad
                bottom: Color(red: 0.294, green: 0.722, blue: 0.478)  // #4bb87a
            )
        }
    }

    private static func severityTier(_ window: UsageWindow, now: Date) -> Int {
        if window.percent >= 90 { return 2 }
        guard let ratio = ratio(window, now: now) else {
            // Too early in the window for a pace ratio to mean anything.
            if window.percent >= 60 { return 2 }
            if window.percent >= 30 { return 1 }
            return 0
        }
        if ratio > 1.5 { return 2 }
        if ratio > 1.0 { return 1 }
        return 0
    }

    /// Ranking used to pick which window the menu bar should speak for: the one
    /// in the most trouble. Colour tier wins first, then usage and pace break
    /// ties without collapsing high percentages into the same capped score.
    static func severity(_ window: UsageWindow, now: Date = Date()) -> Severity {
        Severity(
            tier: severityTier(window, now: now),
            percent: window.percent,
            pace: ratio(window, now: now) ?? 0
        )
    }

    /// One sentence answering "am I fine?", so neither surface makes the reader
    /// parse four rows to find out.
    struct Verdict {
        /// Title of the dropdown's summary pill, over `detail`.
        let headline: String
        /// The card's one line, which has to carry the number as well.
        let line: String
        let detail: String
        let percent: Double
        /// Share of the window elapsed, for the ring's even-burn mark.
        let elapsed: Double?
        /// "Anthropic 5h" — the row the whole summary is speaking about, named
        /// so that the ring is not an anonymous number.
        let source: String?
        /// Identifies that row in the list below, so it can be marked there too.
        let rowKey: String?
        let color: Color
        /// True once the reading is bad enough that the whole card goes red.
        let hot: Bool
    }

    /// `mode` decides which reading the summary sentence quotes, so that it
    /// agrees with the column of numbers underneath it. That agreement is what
    /// labels the column: a heading over it was tried and read as clutter, and
    /// this sentence was already on screen saying "70% of pace" in words.
    static func verdict(
        _ report: Report?,
        mode: PercentMode = .budget,
        now: Date = Date()
    ) -> Verdict {
        guard let worst = report?.busiestWindows(limit: 1, now: now).first else {
            return Verdict(
                headline: "No reading yet",
                line: "No reading yet",
                detail: "nothing fetched",
                percent: 0,
                elapsed: nil,
                source: nil,
                rowKey: nil,
                color: good,
                hot: false
            )
        }

        let window = worst.window
        let tier = severityTier(window, now: now)
        let exhausted = tier == 2 && window.percent >= 90
        let reading = readingPhrase(window, mode: mode, now: now)

        let short: String
        switch tier {
        case 2: short = "Well ahead of pace"
        case 1: short = "Ahead of pace"
        default: short = "On pace"
        }

        return Verdict(
            headline: exhausted ? "\(window.label) window nearly out" : (tier == 0 ? "On pace everywhere" : short),
            line: exhausted
                ? "\(window.label) window nearly out — \(reading)"
                : "\(short) — \(reading)",
            detail: "worst: \(worst.provider.name) \(window.label), \(reading)",
            percent: window.percent,
            elapsed: elapsedPercent(window, now: now),
            source: "\(worst.provider.name) \(window.label)",
            rowKey: Report.rowKey(provider: worst.provider, window: window),
            color: color(window, now: now),
            hot: tier == 2
        )
    }

    /// The number the summary quotes, named. Whichever reading the rows below
    /// are showing, said in words — "70% of pace" or "36% of the week" — so the
    /// bare percentages in the column inherit the noun from the sentence above
    /// them.
    ///
    /// Pace mode still falls back to the budget here rather than to a dash. A
    /// column of numbers has to be read against one heading and cannot carry
    /// a substitution, but a sentence names whatever it is quoting.
    private static func readingPhrase(_ window: UsageWindow, mode: PercentMode, now: Date) -> String {
        if mode == .pace, let index = paceIndex(window, floor: displayFloor, now: now) {
            return "\(Int(min(paceCeiling, index).rounded()))% of pace"
        }
        return "\(Int(window.percent.rounded()))% of \(phrase(window.label))"
    }

    /// Window labels are a mix of periods and durations: "the week" reads, but
    /// "the 5h" does not and needs the noun spelling out.
    private static func phrase(_ label: String) -> String {
        let period = ["week", "day", "month", "hour", "session"].contains { label.contains($0) }
        return period ? "the \(label)" : "the \(label) window"
    }

    /// The word beside a provider's name: how that provider on its own is doing.
    /// Nil when the reading is missing or carried over from an earlier poll:
    /// what happened is said once, in the notice above the list, and a verdict
    /// read off stale numbers would be stated with more confidence than it has.
    static func note(_ provider: Provider, now: Date = Date()) -> (text: String, color: Color)? {
        guard provider.ok, !provider.stale else { return nil }
        guard let worst = provider.windows.max(by: { severity($0, now: now) < severity($1, now: now) })
        else { return ("no windows", .white.opacity(0.45)) }

        if worst.percent < 5 { return ("barely touched", .white.opacity(0.45)) }
        switch severityTier(worst, now: now) {
        case 2 where worst.percent >= 90: return ("nearly out", bad)
        case 2: return ("over budget", bad)
        case 1: return ("ahead of pace", warn)
        default: return ("under budget", good)
        }
    }

    /// Bare wall clock, for saying when a carried-over reading was taken.
    static func clockLabel(_ epoch: Int) -> String {
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        return clock.string(from: Date(timeIntervalSince1970: Double(epoch)))
    }

    /// Absolute reset time. Bare clock today, weekday within the week, and a
    /// date beyond that — a weekday alone is ambiguous once it wraps around.
    static func resetLabel(_ epoch: Int?, now: Date = Date()) -> String {
        // An untouched window has no reset instant yet; the clock starts on use.
        guard let epoch, epoch > 0 else { return "idle" }
        let at = Date(timeIntervalSince1970: Double(epoch))
        if at <= now { return "now" }

        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        let calendar = Calendar.current
        if calendar.isDate(at, inSameDayAs: now) { return clock.string(from: at) }

        if at.timeIntervalSince(now) >= 6 * 86400 {
            let long = DateFormatter()
            long.dateFormat = "MMM d HH:mm"
            return long.string(from: at)
        }
        let weekday = DateFormatter()
        weekday.dateFormat = "EEE HH:mm"
        return weekday.string(from: at)
    }
}
