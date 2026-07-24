import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A small 100×100 dashed drop target that accepts PNG / JPG images, or opens a file picker when clicked.
struct DropZoneView: View {
    @ObservedObject var model: DropModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 22))
            Text("Drop\nPNG / JPG")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
        .frame(width: 100, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary,
                    style: StrokeStyle(lineWidth: 1.5, dash: [5])
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: openPanel)
        .help("Click to choose images, or drop them here")
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            model.handleDrop(providers: providers)
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg]
        panel.message = "Choose one or more images to import"
        if panel.runModal() == .OK {
            model.importURLs(panel.urls)
        }
    }
}
