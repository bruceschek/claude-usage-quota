import SwiftUI
import AppKit

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
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                   accessibilityDescription: "Claude Usage Quota")
            button.image?.isTemplate = true
            button.title = " Quota"
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }
        NSLog("ClaudeUsageBar: status item created (button=%@)", statusItem.button == nil ? "nil" : "ok")

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: ContentView(store: store))
    }

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
