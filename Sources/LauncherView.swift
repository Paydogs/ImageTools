import SwiftUI

/// A tool the launcher can open in its own window.
enum Tool: CaseIterable {
    case imageAssetGenerator
    case comparison

    var title: String {
        switch self {
        case .imageAssetGenerator: "Image Asset Generator"
        case .comparison: "Comparison"
        }
    }

    var icon: String {
        switch self {
        case .imageAssetGenerator: "photo.on.rectangle.angled"
        case .comparison: "rectangle.split.2x1"
        }
    }

    var windowID: String {
        switch self {
        case .imageAssetGenerator: "image-asset-generator"
        case .comparison: "comparison"
        }
    }
}

/// The startup panel: a vertical stack of tool buttons.
struct LauncherView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ImageTools")
                .font(.title2.bold())

            VStack(spacing: 8) {
                ForEach(Tool.allCases, id: \.self) { tool in
                    LauncherButton(icon: tool.icon, title: tool.title) {
                        openWindow(id: tool.windowID, value: "main")
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

private struct LauncherButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 26)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering
                          ? Color.accentColor.opacity(0.18)
                          : Color(nsColor: .controlBackgroundColor))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
