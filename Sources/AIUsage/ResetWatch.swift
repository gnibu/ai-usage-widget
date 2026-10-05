import Foundation

/// Decides when a quota has cleared or a reset credit has arrived. Kept apart
/// from `Notifier` so the rules can be tested without a notification center.
enum ResetWatch {
    /// The 5h session clears several times a day; announcing it would be noise.
    static let shortestAnnouncedWindow = 5 * 3600

    /// A reading taken after the app was off for days should not announce a
    /// reset that happened long ago.
    static let staleAfter = 12 * 3600

    /// Whether `window` is a quota worth announcing when it clears: longer than
    /// the session window, and an allowance rather than a spend budget.
    static func isAnnounced(_ window: UsageWindow) -> Bool {
        guard window.budgetUSD == nil, window.spentUSD == nil else { return false }
        return (window.windowSeconds ?? Int.max) > shortestAnnouncedWindow
    }

    /// True when the window last seen resetting at `previousResetsAt`, with
    /// `previousPercent` used, has since cleared. Either its reset time has
    /// passed, or the provider now reports a later reset with less used — the
    /// shape of both an ordinary rollover and an early reset from a credit.
    /// A reset that moves by less than an hour is jitter, not a new window.
    static func quotaCleared(
        previousResetsAt: Int?,
        previousPercent: Double?,
        window: UsageWindow,
        now: Int
    ) -> Bool {
        guard isAnnounced(window),
              let old = previousResetsAt, old > 0,
              let used = previousPercent, used >= 1,
              old > now - staleAfter
        else { return false }
        if old <= now { return true }
        guard let new = window.resetsAt else { return false }
        return new >= old + 3600 && window.percent < used
    }

    /// How many credits arrived since the last reading. The first reading for
    /// an account only establishes the baseline.
    static func newCredits(previous: Int?, current: ResetCredits?) -> Int {
        guard let previous, let current else { return 0 }
        return max(0, current.available - previous)
    }
}
