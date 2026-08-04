import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Fill the screen once the window exists (SwiftUI creates it after this callback).
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first,
                  let screen = window.screen ?? NSScreen.main else { return }
            window.setFrame(screen.visibleFrame, display: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
