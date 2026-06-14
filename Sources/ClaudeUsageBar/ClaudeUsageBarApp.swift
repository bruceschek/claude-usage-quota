import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra("Claude Usage Quota", systemImage: "gauge.with.dots.needle.33percent") {
            ContentView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
