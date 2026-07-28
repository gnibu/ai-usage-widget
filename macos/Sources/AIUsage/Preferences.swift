import Foundation
import ServiceManagement

/// User-visible knobs, all backed by UserDefaults so they survive a restart.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    @Published var showPercentInMenuBar: Bool {
        didSet { defaults.set(showPercentInMenuBar, forKey: Keys.showPercent) }
    }

    /// Notify once per window when consumption crosses this mark.
    @Published var usageThreshold: Double {
        didSet { defaults.set(usageThreshold, forKey: Keys.usageThreshold) }
    }

    @Published var usageAlertsEnabled: Bool {
        didSet { defaults.set(usageAlertsEnabled, forKey: Keys.usageAlerts) }
    }

    /// Notify once per window when burn rate exceeds this multiple of even pace.
    @Published var paceThreshold: Double {
        didSet { defaults.set(paceThreshold, forKey: Keys.paceThreshold) }
    }

    @Published var paceAlertsEnabled: Bool {
        didSet { defaults.set(paceAlertsEnabled, forKey: Keys.paceAlerts) }
    }

    @Published var refreshMinutes: Double {
        didSet { defaults.set(refreshMinutes, forKey: Keys.refreshMinutes) }
    }

    private enum Keys {
        static let showPercent = "showPercentInMenuBar"
        static let usageThreshold = "usageThreshold"
        static let usageAlerts = "usageAlertsEnabled"
        static let paceThreshold = "paceThreshold"
        static let paceAlerts = "paceAlertsEnabled"
        static let refreshMinutes = "refreshMinutes"
    }

    private init() {
        defaults.register(defaults: [
            Keys.showPercent: true,
            Keys.usageThreshold: 90.0,
            Keys.usageAlerts: true,
            Keys.paceThreshold: 1.5,
            Keys.paceAlerts: true,
            Keys.refreshMinutes: 15.0,
        ])
        showPercentInMenuBar = defaults.bool(forKey: Keys.showPercent)
        usageThreshold = defaults.double(forKey: Keys.usageThreshold)
        usageAlertsEnabled = defaults.bool(forKey: Keys.usageAlerts)
        paceThreshold = defaults.double(forKey: Keys.paceThreshold)
        paceAlertsEnabled = defaults.bool(forKey: Keys.paceAlerts)
        refreshMinutes = defaults.double(forKey: Keys.refreshMinutes)
    }

    // ----------------------------------------------------------------- //
    // Login item — not a default, it is read back from the system.
    // ----------------------------------------------------------------- //

    var opensAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting state; registration can be refused (for instance
    /// when the app is run from a build directory rather than /Applications).
    @discardableResult
    func setOpensAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("ai-usage: login item \(enabled ? "register" : "unregister") failed: \(error)")
        }
        return opensAtLogin
    }
}
