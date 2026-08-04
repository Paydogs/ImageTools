import SwiftUI

/// The left column shared by every tool tab: the drop target on top, the tool's own
/// controls beneath it, and empty space below. Every tab gets the same fixed width so
/// the tabs line up when switching between them.
struct ToolSidebar<Controls: View>: View {
    /// The width of the column on every tab, including its padding.
    static var width: CGFloat { 100 }

    let model: DropModel
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(spacing: 12) {
            DropZoneView(model: model)
            controls
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
    }
}
