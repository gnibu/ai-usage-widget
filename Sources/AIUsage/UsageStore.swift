import AppKit
import Combine
import SwiftUI

/// Owns the current reading: loads the cache at launch, refreshes on a timer,
/// on wake, and on demand, and writes `usage.json` so a reading survives a
/// restart and the app has something to draw before the first fetch lands.
@MainActor
final class UsageStore: ObservableObject {
    /// One reading for the whole app: the menu bar scene and the AppKit-owned
    /// desktop card both need it, and only one of them can own it.
    static let shared = UsageStore()

    @Published private(set) var report: Report?
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusImage: NSImage = StatusIcon.image(segments: [])

    static var stateDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["AI_USAGE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: ("~/.local/share/ai-usage" as NSString).expandingTildeInPath)
    }

    static var cacheURL: URL { stateDirectory.appendingPathComponent("usage.json") }

    private var timer: Timer?
    private var preferenceWatch: AnyCancellable?

    private init() {
        loadCache()
        redrawIcon()

        preferenceWatch = Preferences.shared.$refreshMinutes
            .removeDuplicates()
            .sink { [weak self] minutes in self?.scheduleTimer(minutes: minutes) }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshIfStale(olderThan: 300) }
        }

        Task { await refresh() }
    }

    // ----------------------------------------------------------------- //

    /// The window in the most trouble, which is what the menu bar leads with.
    var worstWindow: (provider: Provider, window: UsageWindow)? {
        menuBarWindows(limit: 1).first
    }

    /// What the menu bar speaks for.
    func menuBarWindows(limit: Int) -> [(provider: Provider, window: UsageWindow)] {
        report?.busiestWindows(
            limit: limit,
            fairShare: Preferences.shared.menuBarFairShare
        ) ?? []
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let merged = (await Fetcher.fetchAll()).carryingOver(from: report)
        report = merged
        write(merged)
        redrawIcon()
        Notifier.evaluate(merged)
    }

    func refreshIfStale(olderThan seconds: TimeInterval) {
        let age = Date().timeIntervalSince1970 - Double(report?.updatedAt ?? 0)
        guard age > seconds else { return }
        Task { await refresh() }
    }

    // ----------------------------------------------------------------- //

    private func scheduleTimer(minutes: Double) {
        timer?.invalidate()
        let interval = max(60, minutes * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        // Let the system coalesce the wake-up; a minute either way is fine.
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func redrawIcon() {
        let preferences = Preferences.shared
        let segments = menuBarWindows(limit: preferences.menuBarSlots).map {
            StatusIcon.Segment(
                provider: $0.provider.name,
                window: $0.window.label,
                percent: $0.window.percent,
                color: Pace.color($0.window)
            )
        }

        var parts: StatusIcon.Parts = []
        if preferences.showLogoInMenuBar { parts.insert(.mark) }
        if preferences.showGaugeInMenuBar { parts.insert(.gauge) }
        if preferences.showPercentInMenuBar { parts.insert(.percent) }
        if preferences.showWindowInMenuBar { parts.insert(.window) }

        statusImage = StatusIcon.image(segments: segments, parts: parts)
    }

    /// Re-render after a preference change that only affects the icon.
    func iconPreferenceChanged() {
        redrawIcon()
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let cached = try? JSONDecoder().decode(Report.self, from: data)
        else { return }
        report = cached
    }

    private func write(_ report: Report) {
        do {
            try FileManager.default.createDirectory(
                at: Self.stateDirectory, withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(report)
            let temporary = Self.cacheURL.appendingPathExtension("tmp")
            try data.write(to: temporary, options: .atomic)
            _ = try FileManager.default.replaceItemAt(Self.cacheURL, withItemAt: temporary)
        } catch {
            // The cache is a convenience for the other surfaces, never fatal.
            NSLog("ai-usage: could not write cache: \(error)")
        }
    }
}
