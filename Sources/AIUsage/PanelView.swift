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
        // The desktop card's pane exactly, rim included: the panel this hangs
        // in is ours now, so its edge is the only one on screen.
        // The shadow is the panel's own, as with the card: a SwiftUI one would
        // be clipped by the window it is drawn inside.
        .glassPane(radius: Glass.panelRadius, dim: 0.75, tone: 0.7, shadow: false)
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
            CappedScroll(maxHeight: Self.cap) {
                VStack(alignment: .leading, spacing: 14) {
                    menuBarGroup
                    displayGroup
                    alertsGroup
                    refreshGroup
                }
                .padding(EdgeInsets(top: 4, leading: 18, bottom: 14, trailing: 18))
            }

            // Quit stays put instead of hiding at the bottom of the scroll.
            footer
                .padding(EdgeInsets(top: 0, leading: 18, bottom: 18, trailing: 18))
        }
    }

    /// How tall the settings list is allowed to get before it starts scrolling.
    /// Measured against the screen rather than fixed, so a large display shows
    /// nearly the whole list while a laptop still leaves room for the header,
    /// the footer and the menu bar the panel hangs from.
    private static var cap: CGFloat {
        let available = (NSScreen.main?.visibleFrame.height ?? 800) - 180
        return min(640, max(320, available))
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

// --------------------------------------------------------------------- //

/// A scroll area that admits it is one.
///
/// A hard cut at the cap is indistinguishable from the end of the list, and on
/// a trackpad macOS keeps the scroller hidden until you are already scrolling —
/// so the tab looked like it simply stopped after Refresh. The clipped edge now
/// fades while there is more content past it, at whichever end is cut off, and
/// firms up once you reach it. Below the cap it does not scroll and shows no
/// fade at all.
private struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    /// Top of the content within the scroll area: 0 at rest, negative once
    /// scrolled. Paired with the two heights it says which edge is cut off.
    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private let fade: CGFloat = 26
    private let space = "capped-scroll"

    private var hiddenAbove: Bool { viewportHeight > 0 && offset < -0.5 }
    private var hiddenBelow: Bool { viewportHeight > 0 && contentHeight + offset - viewportHeight > 0.5 }

    /// A ScrollView has no height of its own to offer, so `maxHeight` alone
    /// leaves the window hosting it free to settle on something far shorter —
    /// which is how the settings tab came out a third of its cap. Measuring the
    /// content and asking for exactly what it needs, up to the cap, gives the
    /// window a number it cannot argue with. Before the first measurement the
    /// cap is the better guess: too tall corrects downwards on the same pass,
    /// too short leaves the panel visibly stunted.
    private var height: CGFloat {
        contentHeight > 0 ? min(maxHeight, contentHeight) : maxHeight
    }

    var body: some View {
        ScrollView {
            content.background(
                GeometryReader { inner in
                    Color.clear.preference(
                        key: ReachKey.self,
                        value: Reach(
                            offset: inner.frame(in: .named(space)).minY,
                            height: inner.size.height
                        )
                    )
                }
            )
        }
        .coordinateSpace(name: space)
        .frame(height: height)
        // An overlay is measured without being given a say in the layout, so
        // reading the viewport back cannot feed into the height above it.
        .overlay(
            GeometryReader { viewport in
                Color.clear
                    .onAppear { viewportHeight = viewport.size.height }
                    .onChange(of: viewport.size.height) { _, height in viewportHeight = height }
            }
        )
        .onPreferenceChange(ReachKey.self) { reach in
            offset = reach.offset
            contentHeight = reach.height
        }
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: hiddenAbove ? fade : 0)
                Rectangle()
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: hiddenBelow ? fade : 0)
            }
        )
    }
}

/// Where the scrolled content currently sits. At file scope because a generic
/// type cannot hold the static default a PreferenceKey needs.
private struct Reach: Equatable {
    var offset: CGFloat = 0
    var height: CGFloat = 0
}

private struct ReachKey: PreferenceKey {
    static let defaultValue = Reach()
    static func reduce(value: inout Reach, nextValue: () -> Reach) {
        value = nextValue()
    }
}
