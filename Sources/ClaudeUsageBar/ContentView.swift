import SwiftUI

/// Color ramp shared by the bars: lots left = green, getting low = amber, near
/// empty = red.
private func barColor(forRemaining pct: Double) -> Color {
    switch pct {
    case 50...: return .green
    case 20..<50: return .yellow
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

struct ContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Claude Code Usage")
                .font(.headline)

            if let snap = store.snapshot {
                metrics(for: snap)
            } else {
                noData
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 280)
        .onAppear { store.start() }
        .onDisappear { store.stop() }
    }

    @ViewBuilder
    private func metrics(for snap: UsageSnapshot) -> some View {
        let now = store.now

        // 1. Time remaining in current 5-hour window
        if let five = snap.fiveHour {
            MetricRow(
                title: "5-hour window resets in",
                value: five.hasResetSince(now: now) ? "reset" : formatCountdown(five.timeRemaining(now: now)),
                percent: nil,
                tag: five.hasResetSince(now: now) ? "window rolled over" : nil
            )

            // 2. 5-hour usage remaining
            let fiveLeft = five.remainingPercentage(now: now)
            MetricRow(
                title: "5-hour usage left",
                value: "\(Int(fiveLeft.rounded()))%",
                percent: fiveLeft,
                tag: five.hasResetSince(now: now) ? "after reset" : nil
            )
        }

        // 3. Weekly usage remaining
        if let week = snap.sevenDay {
            let weekLeft = week.remainingPercentage(now: now)
            MetricRow(
                title: "Weekly usage left",
                value: "\(Int(weekLeft.rounded()))%",
                percent: weekLeft,
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

/// A title, a big value, an optional progress bar, and an optional inferred tag.
private struct MetricRow: View {
    let title: String
    let value: String
    let percent: Double?   // remaining %, drives the bar + color
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(percent.map(barColor(forRemaining:)) ?? .primary)
                if let percent {
                    ProgressView(value: percent, total: 100)
                        .tint(barColor(forRemaining: percent))
                }
            }
        }
    }
}

/// Tighter spacing between the status dot and its text than the default Label.
private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 7))
            configuration.title
        }
    }
}
