import SwiftUI

/// Pace maths and formatting, shared by the panel, the menu bar icon and the
/// notification rules. One implementation so that every surface judges a
/// window identically.
enum Pace {
    static let good = Color(red: 0.369, green: 0.788, blue: 0.541)   // #5ec98a
    static let warn = Color(red: 1.000, green: 0.706, blue: 0.329)   // #ffb454
    static let bad = Color(red: 1.000, green: 0.420, blue: 0.420)    // #ff6b6b

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
