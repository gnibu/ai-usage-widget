import AppKit
import SwiftUI

/// The dropdown behind the menu bar item: the reading, plus the controls a
/// desktop card had nowhere to put.
struct PanelView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageCard()

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

            Toggle("Show card on desktop", isOn: $preferences.showDesktopCard)
            Toggle("Keep card above other windows", isOn: $preferences.desktopCardFloats)
                .disabled(!preferences.showDesktopCard)
                .padding(.leading, 18)

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
