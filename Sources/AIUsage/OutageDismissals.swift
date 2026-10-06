import Combine
import Foundation

/// Acknowledges one ongoing failure per account. The signature excludes the
/// account's display name and the carried reading's clock, which can change
/// while the same problem remains unresolved.
final class OutageDismissals: ObservableObject {
    static let shared = OutageDismissals()

    private static let key = "dismissedOutages"
    private let defaults: UserDefaults

    @Published private var reasons: [String: String] {
        didSet { defaults.set(reasons, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reasons = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    func isDismissed(_ provider: Provider) -> Bool {
        guard let reason = Self.reason(for: provider) else { return false }
        return reasons[provider.id] == reason
    }

    func dismiss(_ provider: Provider) {
        guard let reason = Self.reason(for: provider) else { return }
        reasons[provider.id] = reason
    }

    /// Use the complete report, including hidden accounts and providers that
    /// weren't polled this round. Recovery, removal, or a different failure
    /// ends the acknowledgement so a later recurrence appears again.
    func reconcile(providers: [Provider]) {
        let current = Dictionary(uniqueKeysWithValues: providers.compactMap { provider in
            Self.reason(for: provider).map { (provider.id, $0) }
        })
        let next = reasons.filter { current[$0.key] == $0.value }
        if next != reasons { reasons = next }
    }

    /// The actionable reason displayed by both surfaces, without the reading's
    /// age. Credential-source changes may supply a new route to reconnect.
    static func reason(for provider: Provider) -> String? {
        guard !provider.ok || provider.stale else { return nil }
        if let reconnect = OpenCodeGoCredential.reconnectMessage(for: provider) { return reconnect }
        if let reconnect = OpenRouterCredential.reconnectMessage(for: provider) { return reconnect }
        if let reconnect = CursorCredential.reconnectMessage(for: provider) { return reconnect }
        return provider.error ?? "no reading"
    }
}
