import AppKit
import SwiftUI

/// The dropdown behind the menu bar item, in two tabs. Settings used to push
/// the reading off the bottom of the screen when opened; as a tab it costs one
/// click and keeps the panel a constant height instead.
struct PanelView: View {
    enum Tab: Hashable {
        case usage
        case settings
    }

    @EnvironmentObject private var store: UsageStore
    @State private var tab: Tab = .usage

    var body: some View {
        VStack(spacing: 0) {
            header

            switch tab {
            case .usage:
                VStack(alignment: .leading, spacing: 16) {
                    MenuUsageView()
                    usageFooter
                }
                .padding(EdgeInsets(top: 4, leading: 18, bottom: 18, trailing: 18))

            case .settings:
                SettingsTab()
            }
        }
        .frame(width: 430)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Glass.sheen(top: 0.17)))
        }
        .environment(\.colorScheme, .dark)
        .onAppear { store.refreshIfStale(olderThan: 300) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            GlassSegmented(
                options: [.init(.usage, "Usage"), .init(.settings, "Settings")],
                selection: $tab
            )

            if tab == .usage {
                GlassButton(label: "", systemImage: "arrow.clockwise", enabled: !store.isRefreshing) {
                    Task { await store.refresh() }
                }
                .help("Refresh now")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var usageFooter: some View {
        HStack(spacing: 12) {
            Text(footerText)
                .font(.system(size: 11))
                .foregroundStyle(Glass.ink(0.4))
            Spacer(minLength: 8)
            GlassLink(title: "Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private var footerText: String {
        let every = "every \(Int(Preferences.shared.refreshMinutes)) min"
        guard let report = store.report else { return "No reading yet · \(every)" }
        if store.isRefreshing { return "Refreshing… · \(every)" }
        let stale = report.isStale ? " (stale)" : ""
        return "Updated \(report.updatedLabel)\(stale) · \(every)"
    }
}

// --------------------------------------------------------------------- //

/// Settings as inset groups rather than one flat run of checkboxes: switches
/// for the on/off knobs, segmented controls for the either/or ones, and
/// sliders for the thresholds that used to be ±5 arithmetic on a stepper.
private struct SettingsTab: View {
    @EnvironmentObject private var store: UsageStore
    @ObservedObject private var preferences = Preferences.shared
    @State private var opensAtLogin = Preferences.shared.opensAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Capped and scrolled rather than allowed to grow: the whole point
            // of the tab is that the dropdown stays a predictable height.
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    menuBarGroup
                    displayGroup
                    alertsGroup
                    refreshGroup
                }
                .padding(EdgeInsets(top: 4, leading: 18, bottom: 14, trailing: 18))
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 380)

            // Quit stays put instead of hiding at the bottom of the scroll.
            footer
                .padding(EdgeInsets(top: 0, leading: 18, bottom: 18, trailing: 18))
        }
    }

    // ----------------------------------------------------------------- //

    private var menuBarGroup: some View {
        Group {
            groupTitle("Menu bar")

            DividedRows {
                SettingRow(title: "Provider logo") {
                    partSwitch($preferences.showLogoInMenuBar)
                }
                SettingRow(title: "Usage gauge") {
                    partSwitch($preferences.showGaugeInMenuBar)
                }
                SettingRow(title: "Percentage") {
                    partSwitch($preferences.showPercentInMenuBar)
                }
                SettingRow(
                    title: "Window initial in the gauge",
                    subtitle: "rides inside the ring, so it widens nothing",
                    enabled: preferences.showGaugeInMenuBar
                ) {
                    GlassSwitch(isOn: $preferences.showWindowInMenuBar, enabled: preferences.showGaugeInMenuBar)
                        .onChange(of: preferences.showWindowInMenuBar) { _, _ in
                            store.iconPreferenceChanged()
                        }
                }
                SettingRow(title: "Windows shown") {
                    GlassSegmented(
                        options: (1...4).map { .init($0, "\($0)") },
                        selection: $preferences.menuBarSlots,
                        fontSize: 11,
                        verticalPadding: 4
                    )
                    .frame(width: 132)
                    .onChange(of: preferences.menuBarSlots) { _, _ in
                        store.iconPreferenceChanged()
                    }
                }
                SettingRow(
                    title: "Keep every provider on screen",
                    subtitle: "even when one provider owns the busiest windows",
                    enabled: preferences.menuBarSlots > 1
                ) {
                    GlassSwitch(isOn: $preferences.menuBarFairShare, enabled: preferences.menuBarSlots > 1)
                        .onChange(of: preferences.menuBarFairShare) { _, _ in
                            store.iconPreferenceChanged()
                        }
                }
            }
        }
    }

    private var displayGroup: some View {
        Group {
            groupTitle("Display")

            DividedRows {
                SettingRow(title: "Card on desktop") {
                    GlassSwitch(isOn: $preferences.showDesktopCard)
                }
                SettingRow(title: "Card layer", enabled: preferences.showDesktopCard) {
                    GlassSegmented(
                        options: [.init(false, "Desktop"), .init(true, "Floating")],
                        selection: $preferences.desktopCardFloats,
                        fontSize: 11,
                        verticalPadding: 4,
                        enabled: preferences.showDesktopCard
                    )
                    .frame(width: 160)
                }
                SettingRow(title: "Open at login") {
                    GlassSwitch(isOn: $opensAtLogin)
                        .onChange(of: opensAtLogin) { _, wanted in
                            let actual = preferences.setOpensAtLogin(wanted)
                            if actual != wanted { opensAtLogin = actual }
                        }
                }
            }
        }
    }

    private var alertsGroup: some View {
        Group {
            groupTitle("Alerts")

            VStack(alignment: .leading, spacing: 16) {
                threshold(
                    title: "Alert past",
                    value: String(format: "%.0f%%", preferences.usageThreshold),
                    isOn: $preferences.usageAlertsEnabled,
                    slider: $preferences.usageThreshold,
                    range: 50...100,
                    step: 5,
                    colors: [Pace.warn, Color(red: 1, green: 0.549, blue: 0.235)],
                    bounds: ("50%", "100%")
                )

                threshold(
                    title: "Alert when burning faster than",
                    value: String(format: "%.1f×", preferences.paceThreshold),
                    isOn: $preferences.paceAlertsEnabled,
                    slider: $preferences.paceThreshold,
                    range: 1.1...4,
                    step: 0.1,
                    colors: [Pace.warn, Pace.bad],
                    bounds: ("1.1×", "4×")
                )
            }
            .glassGroup()
        }
    }

    private var refreshGroup: some View {
        Group {
            groupTitle("Refresh")

            VStack(alignment: .leading, spacing: 10) {
                Text("Refresh every")
                    .font(.system(size: 13))
                    .foregroundStyle(Glass.ink(0.92))

                GlassSegmented(
                    options: [.init(5.0, "5"), .init(15.0, "15"), .init(30.0, "30"), .init(60.0, "60 min")],
                    selection: $preferences.refreshMinutes
                )
            }
            .glassGroup()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("v\(Self.version) · io.github.ai-usage")
                .font(.system(size: 11))
                .foregroundStyle(Glass.ink(0.4))
            Spacer(minLength: 8)
            GlassLink(title: "Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    // ----------------------------------------------------------------- //

    private func groupTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium))
            .kerning(1.3)
            .foregroundStyle(Glass.ink(0.42))
            .padding(.leading, 4)
            .padding(.top, 2)
    }

    private func threshold(
        title: String,
        value: String,
        isOn: Binding<Bool>,
        slider: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        colors: [Color],
        bounds: (String, String)
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Glass.ink(isOn.wrappedValue ? 0.92 : 0.4))
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Glass.ink(isOn.wrappedValue ? 1 : 0.4))
                GlassSwitch(isOn: isOn)
            }

            GlassSlider(
                value: slider,
                range: range,
                step: step,
                colors: colors,
                enabled: isOn.wrappedValue
            )

            HStack {
                Text(bounds.0)
                Spacer()
                Text(bounds.1)
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundStyle(Glass.ink(0.35))
        }
    }

    /// The last part standing is locked on: a menu bar item with nothing drawn
    /// in it cannot be clicked back open to undo the mistake.
    private func partSwitch(_ isOn: Binding<Bool>) -> some View {
        let enabledParts = [
            preferences.showLogoInMenuBar,
            preferences.showGaugeInMenuBar,
            preferences.showPercentInMenuBar,
        ].filter { $0 }.count
        let locked = isOn.wrappedValue && enabledParts == 1

        return GlassSwitch(isOn: isOn, enabled: !locked)
            .onChange(of: isOn.wrappedValue) { _, _ in
                store.iconPreferenceChanged()
            }
    }
}

// --------------------------------------------------------------------- //

/// An inset group whose rows are separated by hairlines rather than spacing —
/// the shape macOS System Settings uses for a run of related switches.
private struct DividedRows<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            _VariadicView.Tree(Layout()) { content }
        }
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Glass.groupRadius, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Glass.groupRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
        )
    }

    private struct Layout: _VariadicView.UnaryViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            let last = children.last?.id

            ForEach(children) { child in
                VStack(spacing: 0) {
                    child.padding(.vertical, 11)
                    if child.id != last {
                        Rectangle()
                            .fill(Color.white.opacity(0.09))
                            .frame(height: 1)
                    }
                }
            }
        }
    }
}
