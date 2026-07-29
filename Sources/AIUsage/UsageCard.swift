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
    /// The provider mark beside the name, sized to the cap height of the name
    /// rather than to its point size, so it reads as a sibling of the word.
    let markSize: CGFloat
    let glows: Bool

    static let card = RowMetrics(
        label: 84, percent: 46, reset: 88, trackHeight: 10, gap: 12,
        labelSize: 14, percentSize: 14, resetSize: 12, markSize: 16, glows: true
    )

    // The label column is wide enough for "spark week", which is the longest
    // one any provider reports — at 66pt it came out as "spark w…".
    static let menu = RowMetrics(
        label: 78, percent: 38, reset: 70, trackHeight: 8, gap: 10,
        labelSize: 12, percentSize: 12, resetSize: 11, markSize: 14, glows: false
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

            OutageNotice(report: store.report, size: 12)

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

            OutageNotice(report: store.report, size: 11)

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

/// Why a provider has no reading, said once for the whole card and in amber
/// rather than red: a missed poll is a gap in what we know, not a warning about
/// spending, and the rows below still say everything we do know.
struct OutageNotice: View {
    let report: Report?
    let size: CGFloat

    var body: some View {
        let down = (report?.providers ?? []).filter { !$0.ok || $0.stale }

        if !down.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(down) { provider in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: size))
                        Text(Self.line(provider))
                            .font(.system(size: size))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .foregroundStyle(Pace.warn.opacity(0.92))
        }
    }

    /// A stale provider still has rows below, so the notice has to say which
    /// reading those rows are — otherwise the numbers look current.
    static func line(_ provider: Provider) -> String {
        let reason = provider.error ?? "no reading"
        guard provider.stale, let measured = provider.measuredAt else {
            return "\(provider.name): \(reason)"
        }
        return "\(provider.name): \(reason) · rows from \(Pace.clockLabel(measured))"
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
                BrandMark(provider: provider.name, size: metrics.markSize)
                    // Marks are centred on their own box, names sit on a
                    // baseline; aligning the two by eye keeps the row level.
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - metrics.markSize * 0.14 }

                Text(provider.name)
                    .font(.system(size: metrics.labelSize + 3, weight: .semibold))
                    .foregroundStyle(.white)

                if let plan = provider.plan, !plan.isEmpty {
                    planBadge(plan)
                }

                Spacer(minLength: 6)

                if showsNote, let note {
                    Text(note.text)
                        .font(.system(size: 12))
                        .foregroundStyle(note.color)
                }
            }

            // A provider with no reading contributes its name and nothing else:
            // the reason is carried once by `OutageNotice`, above the list.
            // Carried-over rows are dimmed there, so they cannot be mistaken
            // for numbers that were just measured.
            VStack(alignment: .leading, spacing: metrics.trackHeight == 10 ? 10 : 9) {
                ForEach(provider.windows) { window in
                    UsageRow(
                        window: window,
                        metrics: metrics,
                        isWorst: worstRow == Report.rowKey(provider: provider, window: window)
                    )
                }
            }
            .opacity(provider.stale ? 0.55 : 1)
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

/// The provider mark beside its name, drawn from the same outline the menu bar
/// uses. Monochrome and uniformly scaled, per the trademark note on
/// `BrandGlyph` — pace colour stays on the track and the ring.
struct BrandMark: View {
    let provider: String
    let size: CGFloat
    var opacity: Double = 0.9

    var body: some View {
        Group {
            if let outline = BrandGlyph.path(
                for: provider,
                fitting: NSSize(width: size, height: size),
                flipped: false
            ) {
                // Even-odd, as the outline was parsed: the marks carry counters
                // a nonzero fill would flood.
                Path(outline.cgPath).fill(style: FillStyle(eoFill: true))
            } else {
                // The monogram the menu bar falls back to, at this size.
                Text(String(provider.prefix(1)).uppercased())
                    .font(.system(size: size * 0.78, weight: .semibold))
            }
        }
        .foregroundStyle(Glass.ink(opacity))
        .frame(width: size, height: size)
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
