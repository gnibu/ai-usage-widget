import AppKit
import SwiftUI

/// The dropdown behind the menu bar item: the same card the Übersicht widget
/// draws, plus the controls a desktop widget had nowhere to put.
struct PanelView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var showingSettings = false

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

            Divider()

            if showingSettings {
                SettingsView()
                Divider()
            }

            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { store.refreshIfStale(olderThan: 300) }
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

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Refresh") {
                Task { await store.refresh() }
            }
            .disabled(store.isRefreshing)

            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .font(.system(size: 11))
        .buttonStyle(.borderless)
    }
}

// --------------------------------------------------------------------- //

private struct ProviderView: View {
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

private struct WindowRow: View {
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

// --------------------------------------------------------------------- //

private struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    @ObservedObject private var preferences = Preferences.shared
    @State private var opensAtLogin = Preferences.shared.opensAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show percentage in menu bar", isOn: $preferences.showPercentInMenuBar)
                .onChange(of: preferences.showPercentInMenuBar) { _, _ in
                    store.iconPreferenceChanged()
                }

            Toggle("Open at login", isOn: $opensAtLogin)
                .onChange(of: opensAtLogin) { _, wanted in
                    let actual = preferences.setOpensAtLogin(wanted)
                    if actual != wanted { opensAtLogin = actual }
                }

            Divider()

            Toggle("Alert past", isOn: $preferences.usageAlertsEnabled)
            stepperRow(
                value: $preferences.usageThreshold,
                range: 50...100,
                step: 5,
                enabled: preferences.usageAlertsEnabled,
                text: "\(Int(preferences.usageThreshold))% of a window"
            )

            Toggle("Alert when burning faster than", isOn: $preferences.paceAlertsEnabled)
            stepperRow(
                value: $preferences.paceThreshold,
                range: 1.1...4,
                step: 0.1,
                enabled: preferences.paceAlertsEnabled,
                text: String(format: "%.1f× the even pace", preferences.paceThreshold)
            )

            Divider()

            stepperRow(
                value: $preferences.refreshMinutes,
                range: 1...120,
                step: 5,
                enabled: true,
                text: "Refresh every \(Int(preferences.refreshMinutes)) min"
            )
        }
        .font(.system(size: 11))
        .toggleStyle(.checkbox)
    }

    private func stepperRow(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        enabled: Bool,
        text: String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            Text(text)
                .foregroundStyle(enabled ? .primary : .tertiary)
        }
        .disabled(!enabled)
    }
}
