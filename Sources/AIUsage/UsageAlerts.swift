import Foundation

/// Usage-alert decisions and acknowledgements, independent of macOS delivery.
enum UsageAlerts {
    /// Pace comparisons are too noisy at the start of a quota window.
    static let quietTargetPercent: Double = 10

    enum Kind {
        case usage
        case offTrack
        case wayOffTrack
    }

    struct Mark: Codable {
        var resetsAt: Int?
        var usageSent = false
        var paceSent = false
        // Optional so existing saved marks still decode after an upgrade.
        var severePaceSent: Bool?
        var lastPercent: Double?
        var resetAnnounced: Bool?

        mutating func advance(to resetsAt: Int?) {
            if self.resetsAt != resetsAt { self = Mark(resetsAt: resetsAt) }
        }

        /// Called only after macOS accepts the notification request.
        mutating func acknowledge(_ kind: Kind) {
            switch kind {
            case .usage: usageSent = true
            case .offTrack: paceSent = true
            case .wayOffTrack:
                paceSent = true
                severePaceSent = true
            }
        }

        func paceAlert(
            for window: UsageWindow,
            threshold: Double,
            timing: Pace.Timing
        ) -> Kind? {
            // Both stages stay quiet through the first 10% of the active time
            // basis, even when a small target makes the burn ratio enormous.
            // Quota consumed is a separate floor, not a measure of elapsed time.
            guard window.percent >= 10,
                  let target = Pace.targetPercent(window, timing: timing),
                  target > quietTargetPercent
            else { return nil }
            let ratio = window.percent / target

            if ratio > max(3, threshold * 2) {
                return severePaceSent == true ? nil : .wayOffTrack
            }
            if ratio > threshold, !paceSent { return .offTrack }
            return nil
        }
    }
}
