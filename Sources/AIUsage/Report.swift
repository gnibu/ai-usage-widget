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
    /// True when `windows` is the last reading that did land rather than one
    /// taken now: the poll failed and these numbers were carried over.
    var stale: Bool = false
    /// When those carried numbers were actually measured.
    var measuredAt: Int?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case ok
        case plan
        case error
        case windows
        case stale
        case measuredAt = "measured_at"
    }

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
        stale = (try? box.decode(Bool.self, forKey: .stale)) ?? false
        measuredAt = try? box.decodeIfPresent(Int.self, forKey: .measuredAt)
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

    /// A provider that failed this round keeps the numbers it last reported,
    /// marked stale, instead of the card blanking out. Most failures are one
    /// bad poll — an access token the CLI has not refreshed yet, or the API not
    /// answering — and the previous reading stays the best answer to "am I
    /// fine?" for the few minutes until the next try.
    ///
    /// Only for a while: past `carryLimit` the quota windows have moved on and
    /// the old numbers would be a lie rather than an approximation.
    static let carryLimit: TimeInterval = 3 * 3600

    func carryingOver(from previous: Report?, now: Date = Date()) -> Report {
        guard let previous else { return self }
        var merged = self
        merged.providers = providers.map { provider in
            guard !provider.ok,
                  let old = previous.providers.first(where: { $0.name == provider.name }),
                  old.ok
            else { return provider }

            let measured = (old.stale ? old.measuredAt : previous.updatedAt) ?? previous.updatedAt
            guard now.timeIntervalSince1970 - Double(measured) < Self.carryLimit else { return provider }

            var carried = provider
            carried.ok = true
            carried.stale = true
            carried.plan = provider.plan ?? old.plan
            carried.windows = old.windows
            carried.measuredAt = measured
            return carried
        }
        return merged
    }

    /// A reading older than this is shown as stale rather than silently trusted.
    var isStale: Bool {
        Date().timeIntervalSince1970 - Double(updatedAt) > 2700
    }

    /// How long ago the reading landed, in the card's second line. The absolute
    /// clock beside it says *when*; this says whether it is worth trusting.
    func ageLabel(now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince1970 - Double(updatedAt)
        if updatedAt == 0 { return "never" }
        if seconds < 90 { return "just now" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = Int((seconds / 3600).rounded())
        if hours < 24 { return "\(hours) hr ago" }
        return "\(Int((seconds / 86400).rounded())) d ago"
    }

    /// The windows worth watching, worst first.
    ///
    /// `fairShare` gives every provider a slot before any provider gets a
    /// second one. That keeps a quiet Codex on screen next to a loud Claude,
    /// at the cost of bumping a window that really is busier — so it is a
    /// choice, not the rule.
    func busiestWindows(
        limit: Int,
        fairShare: Bool = false,
        now: Date = Date()
    ) -> [(provider: Provider, window: UsageWindow)] {
        guard limit > 0 else { return [] }
        let ranked = providers
            .filter(\.ok)
            .flatMap { provider in provider.windows.map { (provider: provider, window: $0) } }
            .sorted { Pace.severity($0.window, now: now) > Pace.severity($1.window, now: now) }

        guard fairShare else { return Array(ranked.prefix(limit)) }

        var claimed = Set<String>()
        let leading = ranked.filter { claimed.insert($0.provider.name).inserted }
        let taken = Set(leading.map(Self.key))
        return Array((leading + ranked.filter { !taken.contains(Self.key($0)) }).prefix(limit))
    }

    /// Provider and window labels are each unique within a reading, but only
    /// together do they identify one row.
    static func rowKey(provider: Provider, window: UsageWindow) -> String {
        provider.name + "\u{1}" + window.label
    }

    private static func key(_ pair: (provider: Provider, window: UsageWindow)) -> String {
        rowKey(provider: pair.provider, window: pair.window)
    }
}
