import SwiftUI

@main
struct AIUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(store)
        } label: {
            Image(nsImage: store.statusImage)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock tile, no menu bar of its own — LSUIElement covers this too,
        // but setting it here keeps an unbundled debug run honest.
        NSApp.setActivationPolicy(.accessory)
        Notifier.requestAuthorization()
    }
}
