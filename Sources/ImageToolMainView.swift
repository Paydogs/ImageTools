import SwiftUI

/// A tool the main window shows as a tab.
enum Tool: String, CaseIterable, Identifiable {
    case comparison
    case assetGenerator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assetGenerator: "Asset Generator"
        case .comparison: "Comparison"
        }
    }

    var icon: String {
        switch self {
        case .assetGenerator: "photo.on.rectangle.angled"
        case .comparison: "rectangle.split.2x1"
        }
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .assetGenerator: AssetGeneratorView()
        case .comparison: ComparisonView()
        }
    }
}

/// The app's single window: every tool lives in its own tab, filling the screen.
struct ImageToolMainView: View {
    @State private var selection: Tool = .comparison

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Tool.allCases) { tool in
                Tab(tool.title, systemImage: tool.icon, value: tool) {
                    tool.view
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ImageToolMainView()
}
