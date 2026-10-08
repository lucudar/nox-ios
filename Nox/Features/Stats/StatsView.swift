import SwiftUI

struct StatsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(StatsStore.self) private var stats

    @State private var period: StatsStore.Period = .week
    @State private var grown = false

    var body: some View {
        let snap = stats.snapshot(period, settings.lang)
        Screen(title: settings.t("Статистика", "Statistics")) {
            VStack(alignment: .leading, spacing: 0) {
                SlidingSegmented(options: StatsStore.Period.allCases, selection: $period) { $0.title(settings.lang) }

                Text(snap.caption)
                    .font(.system(size: 15))
                    .foregroundStyle(Ink.secondary)
                    .padding(.top, 30)

                let total = Fmt.amount(snap.totalMB, settings.lang)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(total.value)
                        .font(.system(size: 64, weight: .light))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(total.unit)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(Ink.secondary)
                }
                .foregroundStyle(Ink.primary)
                .padding(.top, 2)

                HStack(spacing: 22) {
                    Amount(symbol: "arrow.down", text: Fmt.size(snap.downMB, settings.lang))
                    Amount(symbol: "arrow.up", text: Fmt.size(snap.upMB, settings.lang))
                }
                .padding(.top, 2)

                BarChart(bars: snap.bars, labels: snap.labels, current: snap.current, grown: grown)
                    .frame(height: 230)
                    .padding(.top, 34)

                if snap.isEmpty {
                    Caption(text: settings.t("Здесь появится трафик через Nox: он считается по данным ядра, пока туннель включён.",
                                             "Traffic through Nox shows up here: it's counted from the core while the tunnel is on."))
                        .padding(.top, 18)
                        .padding(.horizontal, 4)
                }

                RowDivider()
                    .padding(.top, 26)

                HStack(alignment: .top, spacing: 0) {
                    Metric(title: settings.t("Время в сети", "Time online")) {
                        let h = snap.onlineMinutes / 60, m = snap.onlineMinutes % 60
                        if h > 0 {
                            MetricValue(number: "\(h)", unit: Fmt.hoursUnit(settings.lang))
                        }
                        MetricValue(number: "\(m)", unit: Fmt.minutesUnit(settings.lang))
                    }
                    Rectangle()
                        .fill(Ink.separator)
                        .frame(width: 1, height: 58)
                        .padding(.horizontal, 18)
                    Metric(title: settings.t("Средний пинг", "Average ping")) {
                        if snap.avgPing > 0 {
                            MetricValue(number: "\(snap.avgPing)", unit: Fmt.msUnit(settings.lang))
                        } else {
                            MetricValue(number: "—", unit: "")
                        }
                    }
                }
                .padding(.vertical, 22)

                RowDivider()

                if !snap.top.isEmpty {
                    Text(settings.t("Чаще всего", "Most used"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Ink.secondary)
                        .padding(.top, 34)
                        .padding(.bottom, 12)

                    let maxMB = snap.top.map(\.mb).max() ?? 1
                    GroupCard {
                        ForEach(Array(snap.top.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { RowDivider(leading: 62) }
                            TopRow(item: item, fraction: maxMB > 0 ? item.mb / maxMB : 0, grown: grown)
                        }
                    }
                }
            }
            .animation(Motion.spring, value: period)
        }
        .onAppear {
            guard !grown else { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) { grown = true }
        }
    }
}

private struct Amount: View {
    let symbol: String
    let text: String

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(settings.accentColor)
            Text(text)
                .font(.system(size: 17))
                .foregroundStyle(Ink.secondary)
                .monospacedDigit()
        }
    }
}

private struct Metric<Value: View>: View {
    let title: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Ink.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                value()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricValue: View {
    let number: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(number)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Ink.primary)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 17))
                .foregroundStyle(Ink.secondary)
        }
    }
}

/// Thin capsule bars, dim accent; the current one (today / now) is bright.
private struct BarChart: View {
    let bars: [Double]
    let labels: [String]
    let current: Int
    let grown: Bool

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let peak = max(bars.max() ?? 1, 0.001)
        let width: CGFloat = bars.count > 20 ? 4 : (bars.count > 9 ? 7 : 9)
        VStack(spacing: 12) {
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(bars.indices, id: \.self) { i in
                        let isLast = i == current
                        let h = max(width, geo.size.height * CGFloat(bars[i] / peak))
                        Capsule()
                            .fill(isLast ? settings.accentColor : settings.accent.color(0.26))
                            .frame(width: width, height: grown ? h : width)
                            .shadow(color: isLast ? settings.accent.color(0.45 * settings.look.glow) : .clear, radius: 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(labels.indices, id: \.self) { i in
                    let isLast = i == current
                    Text(labels[i])
                        .font(.system(size: 13, weight: isLast ? .bold : .regular))
                        .foregroundStyle(isLast ? Ink.primary : Ink.tertiary)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct TopRow: View {
    let item: StatsStore.TopItem
    let fraction: Double
    let grown: Bool

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 16) {
            avatar
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Fmt.size(item.mb, settings.lang))
                        .font(.system(size: 15))
                        .foregroundStyle(Ink.secondary)
                        .monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(settings.accentColor)
                            .frame(width: geo.size.width * CGFloat(grown ? fraction : 0))
                    }
                }
                .frame(height: 4)
                .padding(.trailing, 64)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var avatar: some View {
        if item.badge == .home {
            BadgeDisc(kind: .home, size: 30)
        } else if item.code.isEmpty {
            BadgeDisc(kind: .globe, size: 30)
        } else {
            FlagView(code: item.code, size: 30)
        }
    }
}
