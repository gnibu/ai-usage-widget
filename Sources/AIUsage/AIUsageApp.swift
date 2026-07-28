import AppKit
import SwiftUI

/// Plain AppKit rather than a SwiftUI `App`: the only scene this ever had was a
/// `MenuBarExtra`, and that window comes with chrome we cannot turn off — see
/// `MenuBarItem`. Without it there is no scene left to declare.
@main
enum AIUsageApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock tile, no menu bar of its own — LSUIElement covers this too,
        // but setting it here keeps an unbundled debug run honest.
        NSApp.setActivationPolicy(.accessory)
        Notifier.requestAuthorization()
        MainActor.assumeIsolated {
            MenuBarItem.shared.start()
            DesktopCard.shared.start()
        }
    }
}
