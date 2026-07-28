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

    /// How far ahead of an even burn the window is. 1.0 is exactly on pace.
    /// Nil before the window has run long enough for the ratio to mean anything.
    static func ratio(_ window: UsageWindow, now: Date = Date()) -> Double? {
        guard let elapsed = elapsedPercent(window, now: now), elapsed >= 5 else { return nil }
        return window.percent / elapsed
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
        let color: Color
        /// True once the reading is bad enough that the whole card goes red.
        let hot: Bool
    }

    static func verdict(_ report: Report?, now: Date = Date()) -> Verdict {
        guard let worst = report?.busiestWindows(limit: 1, now: now).first else {
            return Verdict(
                headline: "No reading yet",
                line: "No reading yet",
                detail: "nothing fetched",
                percent: 0,
                color: good,
                hot: false
            )
        }

        let window = worst.window
        let tier = severityTier(window, now: now)
        let percent = Int(window.percent.rounded())
        let burn = burnPhrase(window, now: now)
        let exhausted = tier == 2 && window.percent >= 90

        let short: String
        switch tier {
        case 2: short = burn ?? "Well ahead of pace"
        case 1: short = burn ?? "Ahead of pace"
        default: short = "On pace"
        }

        return Verdict(
            headline: exhausted ? "\(window.label) window nearly out" : (tier == 0 ? "On pace everywhere" : short),
            line: exhausted
                ? [burn, "\(window.label) window nearly out"].compactMap { $0 }.joined(separator: " — ")
                : "\(short) — \(percent)% of \(phrase(window.label))",
            detail: "worst: \(worst.provider.name) \(window.label), \(percent)%",
            percent: window.percent,
            color: color(window, now: now),
            hot: tier == 2
        )
    }

    /// Window labels are a mix of periods and durations: "the week" reads, but
    /// "the 5h" does not and needs the noun spelling out.
    private static func phrase(_ label: String) -> String {
        let period = ["week", "day", "month", "hour", "session"].contains { label.contains($0) }
        return period ? "the \(label)" : "the \(label) window"
    }

    /// "Burning 2.1× pace" — only once the window has run long enough for the
    /// ratio to mean anything, otherwise the phrase would be invented.
    private static func burnPhrase(_ window: UsageWindow, now: Date) -> String? {
        guard let ratio = ratio(window, now: now), ratio > 1 else { return nil }
        return String(format: "Burning %.1f× pace", ratio)
    }

    /// The word beside a provider's name: how that provider on its own is doing.
    static func note(_ provider: Provider, now: Date = Date()) -> (text: String, color: Color) {
        guard provider.ok else { return (provider.error ?? "unavailable", bad) }
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
