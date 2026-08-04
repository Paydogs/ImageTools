import AppKit
import SwiftUI

/// The right-hand column: pick a destination folder, then drag each required asset size
/// straight into an Xcode asset catalog or an Android Studio res folder.
struct ExportPanel: View {
    let image: DroppedImage?
    let images: [DroppedImage]
    @Binding var destination: URL?
    @State private var exportStatus: String?
    @State private var enabledPlatforms: Set<String> = ["iOS", "macOS", "Android"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button("Select Destination…", action: chooseDestination)
                if let destination {
                    Text(destination.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(destination.path)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Button(action: export) {
                    Label("Export All", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(destination == nil || images.isEmpty || enabledPlatforms.isEmpty)
                .help(destination == nil ? "Select a destination folder first" : "Export imagesets and Android drawables to the destination")

                if let exportStatus {
                    Text(exportStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if let image {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(AssetCatalog.platforms) { platform in
                            platformSection(platform, image: image)
                        }
                    }
                }
            } else {
                Text("Drop an image and select it to see the required export sizes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .frame(minWidth: 260, idealWidth: 320, maxWidth: .infinity)
    }

    @ViewBuilder
    private func platformSection(_ platform: AssetPlatform, image: DroppedImage) -> some View {
        let isEnabled = enabledPlatforms.contains(platform.name)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(platform.name, systemImage: platform.systemImage)
                    .font(.headline)
                Spacer()
                Toggle("", isOn: enabledBinding(for: platform.name))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            ForEach(platform.sizes) { size in
                let dimensions = size.pixelSize(
                    sourceWidth: image.pixelWidth,
                    sourceHeight: image.pixelHeight,
                    maxScale: platform.maxScale
                )
                sizeRow(label: size.label, width: dimensions.width, height: dimensions.height)
                    .onDrag {
                        makeProvider(
                            platform: platform, size: size, image: image,
                            width: dimensions.width, height: dimensions.height
                        )
                    }
            }
            .opacity(isEnabled ? 1 : 0.35)
            .disabled(!isEnabled)
        }
    }

    private func enabledBinding(for platform: String) -> Binding<Bool> {
        Binding(
            get: { enabledPlatforms.contains(platform) },
            set: { isOn in
                if isOn { enabledPlatforms.insert(platform) } else { enabledPlatforms.remove(platform) }
            }
        )
    }

    private func sizeRow(label: String, width: Int, height: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.callout)
                Text("\(width) × \(height)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
        .contentShape(Rectangle())
    }

    private func export() {
        guard let destination, !images.isEmpty, !enabledPlatforms.isEmpty else { return }
        let result = AssetExporter.exportImageSets(
            images: images, destination: destination, enabledPlatforms: enabledPlatforms
        )
        if result.errors.isEmpty {
            exportStatus = "Exported \(result.imageSetCount) imagesets + Android drawables (\(result.fileCount) files)."
        } else {
            exportStatus = "Exported \(result.fileCount) files — \(result.errors.count) failed."
        }
        NSWorkspace.shared.open(destination)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose a destination folder for exported assets"
        if panel.runModal() == .OK {
            destination = panel.url
        }
    }

    private func makeProvider(
        platform: AssetPlatform,
        size: AssetSize,
        image: DroppedImage,
        width: Int,
        height: Int
    ) -> NSItemProvider {
        guard let url = AssetExporter.writeResized(
            image: image, platform: platform, size: size,
            width: width, height: height, destination: destination
        ), let provider = NSItemProvider(contentsOf: url) else {
            return NSItemProvider()
        }
        return provider
    }
}
