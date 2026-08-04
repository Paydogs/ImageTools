import SwiftUI

@main
struct ImageToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A single window holding every tool as a tab; AppDelegate sizes it to the screen at launch.
        Window("ImageTools", id: "main") {
            ImageToolMainView()
        }
        .defaultSize(width: 1400, height: 900)
        .windowResizability(.contentMinSize)
    }
}
