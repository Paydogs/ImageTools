import SwiftUI

/// The left column shared by every tool tab: the drop target on top, the tool's own
/// controls beneath it, empty space below, and an optional footer pinned to the bottom.
/// Every tab gets the same fixed width so the tabs line up when switching between them.
struct ToolSidebar<Controls: View, Footer: View>: View {
    /// The width of the column on every tab, including its padding.
    static var width: CGFloat { 100 }

    let model: DropModel
    @ViewBuilder var controls: Controls
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 12) {
            DropZoneView(model: model)
            controls
            Spacer()
            footer
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
    }
}

extension ToolSidebar where Footer == EmptyView {
    /// For tabs that only need controls under the drop zone.
    init(model: DropModel, @ViewBuilder controls: () -> Controls) {
        self.init(model: model, controls: controls, footer: { EmptyView() })
    }
}
