import SwiftUI
import AppKit
import Combine

@main
struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No real window scene — the app lives entirely in the menu bar. The
        // status item is created by AppDelegate. Settings is an inert placeholder
        // so SwiftUI has a Scene to satisfy the App protocol.
        Settings { EmptyView() }
    }
}

/// Creates the menu bar status item with AppKit (reliable, unlike MenuBarExtra in
/// a SwiftPM executable) and shows the SwiftUI panel in a popover on click.
///
/// The status item is a live hourglass: the sand level reflects how much of the
/// 5-hour window remains, and the color (green→amber→red) reflects the scarcer of
/// the two quotas, so it warns when either limit runs low.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    /// Full length of the rolling 5-hour window, used to pick the hourglass fill.
    private static let fiveHourWindow: TimeInterval = 5 * 3600

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: ContentView(store: store))

        // Redraw the icon every tick so it stays live with the panel closed.
        store.$now
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
        updateIcon()
    }

    // MARK: - Live icon

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let snap = store.snapshot
        let now = store.now

        let image = NSImage(systemSymbolName: hourglassSymbol(snap?.fiveHour, now: now),
                            accessibilityDescription: "Claude usage quota")
        if let remaining = mostConstrainedRemaining(snap, now: now) {
            let cfg = NSImage.SymbolConfiguration(paletteColors: [Self.iconColor(remaining: remaining)])
            button.image = image?.withSymbolConfiguration(cfg)
            button.image?.isTemplate = false   // keep our color
        } else {
            // No reading yet — neutral glyph that adapts to the menu bar.
            button.image = image
            button.image?.isTemplate = true
        }
    }

    /// Sand falls as the 5-hour window counts down.
    private func hourglassSymbol(_ five: WindowUsage?, now: Date) -> String {
        guard let five, !five.hasResetSince(now: now) else { return "hourglass.tophalf.filled" }
        let fraction = five.timeRemaining(now: now) / Self.fiveHourWindow
        switch fraction {
        case 0.66...: return "hourglass.tophalf.filled"
        case 0.33..<0.66: return "hourglass"
        default: return "hourglass.bottomhalf.filled"
        }
    }

    /// The lower of the two windows' remaining %, so the color warns about
    /// whichever quota is closest to exhaustion. `nil` when there's no data.
    private func mostConstrainedRemaining(_ snap: UsageSnapshot?, now: Date) -> Double? {
        guard let snap else { return nil }
        return [snap.fiveHour, snap.sevenDay]
            .compactMap { $0?.remainingPercentage(now: now) }
            .min()
    }

    private static func iconColor(remaining: Double) -> NSColor {
        switch remaining {
        case 50...: return .systemGreen
        case 20..<50: return .systemOrange
        default: return .systemRed
        }
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
