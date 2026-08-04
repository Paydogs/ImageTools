import AppKit
import SwiftUI

struct AssetGeneratorView: View {
    @State private var model = DropModel()
    @State private var selectedID: DroppedImage.ID?
    @State private var destination: URL?
    @AppStorage("lastDestinationPath") private var lastDestinationPath: String = ""

    /// The image the export panel operates on for its size preview (selected, or first).
    private var selectedImage: DroppedImage? {
        model.items.first { $0.id == selectedID } ?? model.items.first
    }

    var body: some View {
        HSplitView {
            // Part 1 — the drop area
            ToolSidebar(model: model) {
                if !model.items.isEmpty {
                    Button("Clear") {
                        model.clear()
                        selectedID = nil
                    }
                    .buttonStyle(.link)
                }
            }

            // Part 2 — dropped image previews with their metadata (tap to select)
            Group {
                if model.items.isEmpty {
                    Text("Drop PNG or JPG images to inspect them")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach($model.items) { $item in
                                ImageRow(item: $item)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(item.id == selectedImage?.id
                                                  ? Color.accentColor.opacity(0.15) : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedID = item.id
                                        endEditing()
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(minWidth: 120, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity)

            // Part 3 — export panel
            ExportPanel(image: selectedImage, images: model.items, destination: $destination)
                .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 560, minHeight: 460)
        .contentShape(Rectangle())
        .onTapGesture { endEditing() }
        .onAppear(perform: restoreDestination)
        .onChange(of: destination) { _, newValue in
            lastDestinationPath = newValue?.path ?? ""
        }
    }

    /// Dismisses focus from any active text field.
    private func endEditing() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// Restores the last-used destination folder if it still exists.
    private func restoreDestination() {
        guard destination == nil, !lastDestinationPath.isEmpty else { return }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: lastDestinationPath, isDirectory: &isDirectory),
           isDirectory.boolValue {
            destination = URL(fileURLWithPath: lastDestinationPath, isDirectory: true)
        }
    }
}

#Preview {
    AssetGeneratorView()
}
