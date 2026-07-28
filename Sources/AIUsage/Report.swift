import Foundation

/// What gets written to the cache. The snake_case keys are deliberate: the
/// file is meant to stay readable by anything that wants to `cat | jq` it.

struct UsageWindow: Codable, Identifiable, Equatable {
    var label: String
    var percent: Double
    var resetsAt: Int?
    var windowSeconds: Int?

    var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label
        case percent
        case resetsAt = "resets_at"
        case windowSeconds = "window_seconds"
    }

    init(label: String, percent: Double, resetsAt: Int? = nil, windowSeconds: Int? = nil) {
        self.label = label
        self.percent = percent
        self.resetsAt = resetsAt
        self.windowSeconds = windowSeconds
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? box.decode(String.self, forKey: .label)) ?? "limit"
        percent = (try? box.decode(Double.self, forKey: .percent)) ?? 0
        resetsAt = try? box.decodeIfPresent(Int.self, forKey: .resetsAt)
        windowSeconds = try? box.decodeIfPresent(Int.self, forKey: .windowSeconds)
    }
}

struct Provider: Codable, Identifiable, Equatable {
    var name: String
    var ok: Bool = false
    var plan: String?
    var error: String?
    var windows: [UsageWindow] = []

    var id: String { name }

    init(name: String) {
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? box.decode(String.self, forKey: .name)) ?? "?"
        ok = (try? box.decode(Bool.self, forKey: .ok)) ?? false
        plan = try? box.decodeIfPresent(String.self, forKey: .plan)
        error = try? box.decodeIfPresent(String.self, forKey: .error)
        windows = (try? box.decode([UsageWindow].self, forKey: .windows)) ?? []
    }
}

struct Report: Codable, Equatable {
    var updatedAt: Int
    var updatedLabel: String
    var providers: [Provider]

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case updatedLabel = "updated_label"
        case providers
    }

    init(providers: [Provider], date: Date = Date()) {
        updatedAt = Int(date.timeIntervalSince1970)
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        updatedLabel = clock.string(from: date)
        self.providers = providers
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = (try? box.decode(Int.self, forKey: .updatedAt)) ?? 0
        updatedLabel = (try? box.decode(String.self, forKey: .updatedLabel)) ?? "--:--"
        providers = (try? box.decode([Provider].self, forKey: .providers)) ?? []
    }

    /// A reading older than this is shown as stale rather than silently trusted.
    var isStale: Bool {
        Date().timeIntervalSince1970 - Double(updatedAt) > 2700
    }

    /// The windows worth watching, worst first, but with every provider given a
    /// slot before any provider gets a second one. Otherwise a busy Claude week
    /// takes every slot and Codex is never seen at all.
    func busiestWindows(limit: Int, now: Date = Date()) -> [(provider: Provider, window: UsageWindow)] {
        guard limit > 0 else { return [] }
        let ranked = providers
            .filter(\.ok)
            .flatMap { provider in provider.windows.map { (provider: provider, window: $0) } }
            .sorted { Pace.severity($0.window, now: now) > Pace.severity($1.window, now: now) }

        var claimed = Set<String>()
        let leading = ranked.filter { claimed.insert($0.provider.name).inserted }
        let taken = Set(leading.map(Self.key))
        return Array((leading + ranked.filter { !taken.contains(Self.key($0)) }).prefix(limit))
    }

    /// Provider and window labels are each unique within a reading, but only
    /// together do they identify one row.
    private static func key(_ pair: (provider: Provider, window: UsageWindow)) -> String {
        pair.provider.name + "\u{1}" + pair.window.label
    }
}
