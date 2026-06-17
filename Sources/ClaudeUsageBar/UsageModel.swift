import Foundation
import Combine

/// One rate-limit window (e.g. the 5-hour rolling window or the 7-day week).
struct WindowUsage: Equatable {
    /// Percentage of the window's quota consumed (0...100). `nil` when Claude
    /// Code has not yet reported any usage for the window in this session.
    var usedPercentage: Double?
    /// Wall-clock instant at which the window resets.
    var resetsAt: Date

    /// Percentage of quota still available (0...100). Treats "no data yet" as
    /// fully available, and a window whose reset time has already passed as
    /// replenished.
    func remainingPercentage(now: Date) -> Double {
        if now >= resetsAt { return 100 }
        guard let used = usedPercentage else { return 100 }
        return max(0, min(100, 100 - used))
    }

    /// True once the reset instant has elapsed with no fresher reading — the
    /// window has rolled over, so we infer it is replenished.
    func hasResetSince(now: Date) -> Bool { now >= resetsAt }

    /// Seconds until reset, floored at zero.
    func timeRemaining(now: Date) -> TimeInterval { max(0, resetsAt.timeIntervalSince(now)) }
}

/// A full reading persisted by the statusline bridge.
struct UsageSnapshot: Equatable {
    var capturedAt: Date
    var fiveHour: WindowUsage?
    var sevenDay: WindowUsage?
}

/// How fresh the on-disk reading is, which doubles as the "is Claude Code
/// actively running" signal — only a live session rewrites the file.
enum Freshness {
    case live(age: TimeInterval)     // updated within the liveness window
    case stale(age: TimeInterval)    // file exists but Claude Code is idle/closed
    case missing                     // no reading has ever been captured

    /// A reading is considered "live" if written within this many seconds.
    static let livenessWindow: TimeInterval = 90
}

/// Loads, caches, and ticks the usage data for the UI.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    /// Drives the live countdown; updated every tick.
    @Published private(set) var now: Date = .now

    /// `~/.claude/menubar-usage.json`
    private let cacheURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/menubar-usage.json")
    }()

    private let defaultsKey = "lastSnapshot"
    private var timer: Timer?
    private var reloadCounter = 0

    init() {
        loadFromDefaults()
        reload()
        // Tick continuously so the menu bar icon stays live even while the panel
        // is closed.
        start()
    }

    /// Begin ticking.
    func start() {
        stop()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        now = .now
        // The file only changes while Claude Code renders, so polling it once a
        // second is cheap; reload every 5s to pick up new readings.
        reloadCounter += 1
        if reloadCounter % 5 == 0 { reload() }
    }

    func freshness() -> Freshness {
        guard let snap = snapshot else { return .missing }
        let age = now.timeIntervalSince(snap.capturedAt)
        return age <= Freshness.livenessWindow ? .live(age: age) : .stale(age: age)
    }

    /// Read the bridge file. Falls back to the last known snapshot on any
    /// failure so the panel never blanks out.
    func reload() {
        guard let data = try? Data(contentsOf: cacheURL),
              let parsed = Self.parse(data) else { return }
        if parsed != snapshot {
            snapshot = parsed
            saveToDefaults(parsed)
        }
    }

    // MARK: - Parsing

    static func parse(_ data: Data) -> UsageSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let capturedAt = (obj["captured_at"] as? NSNumber)?.doubleValue else { return nil }
        return UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: capturedAt),
            fiveHour: window(from: obj["five_hour"]),
            sevenDay: window(from: obj["seven_day"])
        )
    }

    private static func window(from any: Any?) -> WindowUsage? {
        guard let dict = any as? [String: Any],
              let resets = (dict["resets_at"] as? NSNumber)?.doubleValue else { return nil }
        // Guard the known Claude Code bug where used_percentage can come back as
        // an epoch timestamp instead of 0/null when a window has no data yet.
        var used: Double? = (dict["used_percentage"] as? NSNumber)?.doubleValue
        if let u = used, !(0...100).contains(u) { used = nil }
        return WindowUsage(usedPercentage: used, resetsAt: Date(timeIntervalSince1970: resets))
    }

    // MARK: - Local cache (UserDefaults) for resilience

    private func saveToDefaults(_ snap: UsageSnapshot) {
        var dict: [String: Any] = ["captured_at": snap.capturedAt.timeIntervalSince1970]
        if let w = snap.fiveHour { dict["five_hour"] = encode(w) }
        if let w = snap.sevenDay { dict["seven_day"] = encode(w) }
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func encode(_ w: WindowUsage) -> [String: Any] {
        var d: [String: Any] = ["resets_at": w.resetsAt.timeIntervalSince1970]
        if let u = w.usedPercentage { d["used_percentage"] = u }
        return d
    }

    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let parsed = Self.parse(data) else { return }
        snapshot = parsed
    }
}
