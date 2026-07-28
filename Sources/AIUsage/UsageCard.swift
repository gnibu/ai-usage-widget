import SwiftUI

/// The reading itself. Two densities of the same content: the roomy one the
/// desktop card uses, and the tighter one that fits the dropdown's Usage tab.
/// Both are driven by the same rows so the two can never drift apart.

/// Column widths and type sizes — the only difference between the two.
struct RowMetrics {
    let label: CGFloat
    let percent: CGFloat
    let reset: CGFloat
    let trackHeight: CGFloat
    let gap: CGFloat
    let labelSize: CGFloat
    let percentSize: CGFloat
    let resetSize: CGFloat
    let glows: Bool

    static let card = RowMetrics(
        label: 84, percent: 46, reset: 88, trackHeight: 10, gap: 12,
        labelSize: 14, percentSize: 14, resetSize: 12, glows: true
    )

    static let menu = RowMetrics(
        label: 66, percent: 38, reset: 70, trackHeight: 8, gap: 10,
        labelSize: 12, percentSize: 12, resetSize: 11, glows: false
    )
}

// --------------------------------------------------------------------- //

/// 1a — the free-standing glass card: summary line, hairline, then a block per
/// provider with the word for how that provider on its own is doing.
struct DesktopUsageCard: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        let verdict = Pace.verdict(store.report)

        VStack(alignment: .leading, spacing: 18) {
            header(verdict)

            Glass.hairline

            if let report = store.report {
                ForEach(report.providers) { provider in
                    ProviderBlock(provider: provider, metrics: .card, worstRow: verdict.rowKey)
                }
            } else {
                Text(store.isRefreshing ? "fetching…" : "no data yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Glass.ink(0.5))
            }
        }
    }

    private func header(_ verdict: Pace.Verdict) -> some View {
        HStack(spacing: 14) {
            PaceRing(
                percent: verdict.percent,
                color: verdict.color,
                elapsed: verdict.elapsed,
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.source.map { "WORST — \($0.uppercased())" } ?? "AI USAGE")
                    .font(.system(size: 11, weight: .regular))
                    .kerning(1.4)
                    .foregroundStyle(Glass.ink(0.5))
                Text(verdict.line)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(verdict.hot ? Color(red: 1, green: 0.788, blue: 0.788) : .white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(store.report?.updatedLabel ?? "--:--")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Glass.ink(0.7))
                Text(store.isRefreshing ? "refreshing…" : (store.report?.ageLabel() ?? "never"))
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.ink(0.4))
            }
            .fixedSize()
        }
    }
}

// --------------------------------------------------------------------- //

/// 1b — the Usage tab: one summary pill, then the same rows a size down.
struct MenuUsageView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        let verdict = Pace.verdict(store.report)

        VStack(alignment: .leading, spacing: 16) {
            summary(verdict)

            if let report = store.report {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(report.providers) { provider in
                        ProviderBlock(
                            provider: provider,
                            metrics: .menu,
                            showsNote: false,
                            worstRow: verdict.rowKey
                        )
                    }
                }
            } else {
                Text(store.isRefreshing ? "fetching…" : "no data yet")
                    .font(.system(size: 12))
                    .foregroundStyle(Glass.ink(0.5))
            }
        }
    }

    private func summary(_ verdict: Pace.Verdict) -> some View {
        HStack(spacing: 12) {
            PaceRing(
                percent: verdict.percent,
                color: verdict.color,
                elapsed: verdict.elapsed,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(verdict.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Glass.ink(0.5))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Glass.groupRadius, style: .continuous)
                .fill(Color.white.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Glass.groupRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// --------------------------------------------------------------------- //

struct ProviderBlock: View {
    let provider: Provider
    let metrics: RowMetrics
    var showsNote: Bool = true
    /// The row the summary above is speaking for, marked here so the reader can
    /// trace the ring back to the window it came from.
    var worstRow: String? = nil

    var body: some View {
        let note = Pace.note(provider)

        VStack(alignment: .leading, spacing: metrics.trackHeight == 10 ? 10 : 9) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(provider.name)
                    .font(.system(size: metrics.labelSize + 3, weight: .semibold))
                    .foregroundStyle(.white)

                if let plan = provider.plan, !plan.isEmpty {
                    planBadge(plan)
                }

                Spacer(minLength: 6)

                if showsNote {
                    Text(note.text)
                        .font(.system(size: 12))
                        .foregroundStyle(note.color)
                }
            }

            if provider.ok {
                ForEach(provider.windows) { window in
                    UsageRow(
                        window: window,
                        metrics: metrics,
                        isWorst: worstRow == Report.rowKey(provider: provider, window: window)
                    )
                }
            } else {
                Text(provider.error ?? "unavailable")
                    .font(.system(size: metrics.resetSize))
                    .foregroundStyle(Pace.bad)
            }
        }
    }

    @ViewBuilder
    private func planBadge(_ plan: String) -> some View {
        let text = Text(plan.uppercased())
            .font(.system(size: metrics.labelSize == 14 ? 11 : 10, weight: .semibold))
            .kerning(1)

        if showsNote {
            text
                .foregroundStyle(Glass.ink(0.72))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                )
        } else {
            text.foregroundStyle(Glass.ink(0.5))
        }
    }
}

struct UsageRow: View {
    let window: UsageWindow
    let metrics: RowMetrics
    var isWorst: Bool = false

    var body: some View {
        HStack(spacing: metrics.gap) {
            // The dot sits in a gutter every row pays for, so marking a row
            // moves nothing.
            HStack(spacing: 5) {
                Circle()
                    .fill(isWorst ? Pace.color(window) : .clear)
                    .frame(width: 4, height: 4)

                Text(window.label)
                    .font(.system(size: metrics.labelSize, weight: isWorst ? .semibold : .regular))
                    .foregroundStyle(Glass.ink(isWorst ? 0.95 : 0.6))
            }
            .frame(width: metrics.label, alignment: .leading)

            UsageTrack(
                percent: window.percent,
                elapsed: Pace.elapsedPercent(window),
                palette: Pace.palette(window),
                height: metrics.trackHeight,
                glows: metrics.glows
            )

            Text("\(Int(window.percent.rounded()))%")
                .font(.system(size: metrics.percentSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Glass.ink(window.percent < 0.5 ? 0.55 : 1))
                .frame(width: metrics.percent, alignment: .trailing)

            Text(Pace.resetLabel(window.resetsAt))
                .font(.system(size: metrics.resetSize))
                .monospacedDigit()
                .foregroundStyle(Glass.ink(0.45))
                .frame(width: metrics.reset, alignment: .trailing)
        }
    }
}
