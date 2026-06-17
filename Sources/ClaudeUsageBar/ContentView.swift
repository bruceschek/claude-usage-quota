import SwiftUI
import ServiceManagement

private func barColor(forRemaining pct: Double) -> Color {
    switch pct {
    case 50...: return .green
    case 20..<50: return .orange
    default: return .red
    }
}

private func formatCountdown(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m \(s)s" }
    return "\(s)s"
}

private func formatAge(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    if total < 60 { return "\(total)s ago" }
    if total < 3600 { return "\(total / 60)m ago" }
    if total < 86_400 { return "\(total / 3600)h ago" }
    return "\(total / 86_400)d ago"
}

/// Progress bar with an optional tick mark showing expected proportional usage.
/// Tick position = fraction of the window's time still remaining, so if 40% of
/// the window has elapsed the tick sits at the 60% mark. Fill to the right of
/// the tick means you're under-pacing (good); fill to the left means over-pacing.
private struct TrackedBar: View {
    let actual: Double       // 0–100 remaining %, drives the fill
    var expected: Double? = nil  // 0–100 expected remaining at this point in time
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(actual / 100))
                if let exp = expected {
                    // Tick: clamped so it never clips outside the track bounds.
                    let x = max(0, min(geo.size.width - 2, geo.size.width * CGFloat(exp / 100) - 1))
                    Rectangle()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 2)
                        .offset(x: x)
                }
            }
        }
        .frame(height: 6)
    }
}

struct ContentView: View {
    @ObservedObject var store: UsageStore
    @AppStorage("showPercentInBar") private var showPercentInBar = false
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Claude Usage Quota")
                .font(.headline)

            if let snap = store.snapshot {
                metrics(for: snap)
            } else {
                noData
            }

            Divider()
            footer
            Toggle("Show 5 hr % in menu bar", isOn: $showPercentInBar)
                .font(.caption)
                .toggleStyle(.checkbox)
                .padding(.top, 2)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .font(.caption)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        // Revert to the real state if registration failed.
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        .padding(16)
        .frame(width: 280)
    }

    @ViewBuilder
    private func metrics(for snap: UsageSnapshot) -> some View {
        let now = store.now
        let fiveHourTotal: Double = 5 * 3600
        let weekTotal: Double = 7 * 24 * 3600

        if let five = snap.fiveHour {
            let fiveLeft = five.remainingPercentage(now: now)
            // Expected: if usage tracked time linearly, remaining % = time remaining %.
            let fiveExpected: Double? = five.hasResetSince(now: now) ? nil
                : max(0, min(100, five.timeRemaining(now: now) / fiveHourTotal * 100))

            MetricRow(
                title: five.hasResetSince(now: now) ? "5-hour window" : "5-hour window resets in",
                value: five.hasResetSince(now: now) ? "ready" : formatCountdown(five.timeRemaining(now: now)),
                percent: nil,
                tag: five.hasResetSince(now: now) ? "already reset" : nil
            )

            MetricRow(
                title: "5-hour usage left",
                value: "\(Int(fiveLeft.rounded()))%",
                percent: fiveLeft,
                expectedPercent: fiveExpected,
                tag: five.hasResetSince(now: now) ? "after reset" : nil
            )
        }

        if let week = snap.sevenDay {
            let weekLeft = week.remainingPercentage(now: now)
            let weekExpected: Double? = week.hasResetSince(now: now) ? nil
                : max(0, min(100, week.timeRemaining(now: now) / weekTotal * 100))

            MetricRow(
                title: "Weekly usage left",
                value: "\(Int(weekLeft.rounded()))%",
                percent: weekLeft,
                expectedPercent: weekExpected,
                tag: week.hasResetSince(now: now) ? "after reset" : nil
            )
        }
    }

    private var noData: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No reading yet")
                .font(.subheadline.weight(.medium))
            Text("Run a Claude Code session to capture the first usage reading.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch store.freshness() {
        case .live(let age):
            Label("Live — updated \(formatAge(age))", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .labelStyle(DotLabelStyle())
        case .stale(let age):
            Label("Claude Code idle/closed — \(formatAge(age))", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .labelStyle(DotLabelStyle())
        case .missing:
            Label("Waiting for first reading", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .labelStyle(DotLabelStyle())
        }
    }
}

private struct MetricRow: View {
    let title: String
    let value: String
    let percent: Double?
    var expectedPercent: Double? = nil
    var tag: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let tag {
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(alignment: .center, spacing: 8) {
                Text(value)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(percent.map(barColor(forRemaining:)) ?? .primary)
                if let percent {
                    TrackedBar(
                        actual: percent,
                        expected: expectedPercent,
                        color: barColor(forRemaining: percent)
                    )
                }
            }
        }
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 7))
            configuration.title
        }
    }
}
