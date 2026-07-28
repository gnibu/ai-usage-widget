import SwiftUI

/// The reading itself — header, then a block per provider. Shared verbatim by
/// the menu bar dropdown and the desktop card so the two can never drift.
struct UsageCard: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let report = store.report {
                ForEach(report.providers) { provider in
                    ProviderView(provider: provider)
                }
            } else {
                Text(store.isRefreshing ? "fetching…" : "no data yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("AI USAGE")
                .font(.system(size: 10, weight: .medium))
                .kerning(0.8)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(stamp)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    private var stamp: String {
        guard let report = store.report else { return "" }
        if store.isRefreshing { return "refreshing…" }
        return report.isStale ? "\(report.updatedLabel) (stale)" : report.updatedLabel
    }
}

struct ProviderView: View {
    let provider: Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(provider.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text((provider.plan ?? "").uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .kerning(0.6)
                    .foregroundStyle(.tertiary)
            }

            if provider.ok {
                ForEach(provider.windows) { window in
                    WindowRow(window: window)
                }
            } else {
                Text(provider.error ?? "unavailable")
                    .font(.system(size: 10))
                    .foregroundStyle(Pace.bad)
            }
        }
    }
}

struct WindowRow: View {
    let window: UsageWindow

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            track

            Text("\(Int(window.percent.rounded()))%")
                .font(.system(size: 10))
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)

            Text(Pace.resetLabel(window.resetsAt))
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 68, alignment: .trailing)
        }
    }

    private var track: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.09))

                Capsule()
                    .fill(Pace.color(window))
                    .frame(width: width * min(100, max(2, window.percent)) / 100)

                // Where usage *should* be if spent evenly across the window.
                if let elapsed = Pace.elapsedPercent(window) {
                    Rectangle()
                        .fill(.primary.opacity(0.55))
                        .frame(width: 1)
                        .offset(x: width * elapsed / 100)
                }
            }
        }
        .frame(height: 6)
    }
}
