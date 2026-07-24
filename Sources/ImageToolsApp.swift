import SwiftUI

@main
struct ImageToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The launcher panel shown at startup.
        Window("ImageTools", id: "launcher") {
            LauncherView()
        }
        .windowResizability(.contentSize)

        // Value-based window groups: do not open at launch, only when requested from the launcher.
        WindowGroup("Image Asset Generator", id: Tool.imageAssetGenerator.windowID, for: String.self) { _ in
            ContentView()
        }
        .defaultSize(width: 1000, height: 560)

        WindowGroup("Comparison", id: Tool.comparison.windowID, for: String.self) { _ in
            ComparisonView()
        }
        .defaultSize(width: 1000, height: 620)
    }
}
