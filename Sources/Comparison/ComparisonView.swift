import AppKit
import SwiftUI

/// Compares images side by side, flush against each other with only a 1px red divider between them.
/// Supports draggable horizontal rulers and two-click pixel measurements.
/// All state and behaviour live in `ComparisonViewModel`.
struct ComparisonView: View {
    @State private var viewModel = ComparisonViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // Left — the drop / select area and tool commands
            ToolSidebar(model: viewModel.images) {
                HStack(spacing: 8) {
                    ComparisonToolView(
                        title: "Add Ruler",
                        icon: "ruler",
                        help: "Adds a cyan horizontal guide line. Drag it up or down, or click the red ✕ to delete it.",
                        action: viewModel.addRuler
                    )
                    .disabled(!viewModel.hasImages)

                    ComparisonToolView(
                        title: "Measure",
                        icon: "arrow.up.left.and.arrow.down.right",
                        help: "Click two points to draw a dashed line showing the distance between them in pixels. Toggle off when done.",
                        isActive: viewModel.isMeasuring,
                        action: viewModel.toggleMeasuring
                    )
                    .disabled(!viewModel.hasImages)
                }

                if viewModel.hasOverlay {
                    Button("Clear Overlay", action: viewModel.clearOverlay)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }

                if viewModel.hasImages {
                    Button("Clear Workspace", role: .destructive, action: viewModel.clearWorkspace)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }

            Divider()

            // Right — the flush comparison strip with overlays
            Group {
                if viewModel.hasImages {
                    comparisonStrip
                } else {
                    Text("Drop or select images to compare")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var comparisonStrip: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(viewModel.images.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 1)
                        }
                        Image(nsImage: item.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: geometry.size.height)
                            .overlay(alignment: .topLeading) {
                                ImageControls(item: item) {
                                    viewModel.removeImage(id: item.id)
                                }
                                .padding(6)
                            }
                            // Drop target: the dragged image takes over this image's slot.
                            .overlay(alignment: .leading) {
                                if viewModel.dropTargetID == item.id {
                                    Rectangle()
                                        .fill(Color.accentColor)
                                        .frame(width: 3)
                                        .allowsHitTesting(false)
                                }
                            }
                            .dropDestination(for: String.self) { identifiers, _ in
                                viewModel.dropTargetID = nil
                                guard let dragged = identifiers.first,
                                      let id = UUID(uuidString: dragged) else { return false }
                                return viewModel.moveImage(id: id, toSlotOf: item.id)
                            } isTargeted: { targeted in
                                if targeted {
                                    viewModel.dropTargetID = item.id
                                } else if viewModel.dropTargetID == item.id {
                                    viewModel.dropTargetID = nil
                                }
                            }
                    }
                }
            }
            // Rulers
            .overlay(alignment: .top) {
                ForEach($viewModel.rulers) { $ruler in
                    RulerLine(ruler: $ruler, maxY: geometry.size.height) {
                        viewModel.deleteRuler(id: ruler.id)
                    }
                    .offset(y: ruler.y)
                }
            }
            // Measurements + measure interaction
            .overlay {
                ZStack(alignment: .topLeading) {
                    // Non-interactive dashed lines.
                    ForEach(viewModel.measurements) { measurement in
                        MeasureLine(a: measurement.a, b: measurement.b)
                    }
                    if let preview = viewModel.measurePreview {
                        MeasureLine(a: preview.a, b: preview.b)
                        MeasureLabel(a: preview.a, b: preview.b)
                    }

                    // Distance labels; each ✕ has its own tap gesture that (as a descendant)
                    // takes priority over the container's measure tap below.
                    ForEach(viewModel.measurements) { measurement in
                        MeasureLabel(a: measurement.a, b: measurement.b) {
                            viewModel.deleteMeasurement(id: measurement.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Measure interaction lives on the container, active only while measuring.
                .applyIf(viewModel.isMeasuring) { view in
                    view
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if case .active(let location) = phase {
                                viewModel.updateMeasurePreview(to: location)
                            }
                        }
                        .onTapGesture(count: 1, coordinateSpace: .local) { location in
                            viewModel.measureTap(at: location)
                        }
                }
            }
            .onAppear { viewModel.stripHeight = geometry.size.height }
            .onChange(of: geometry.size.height) { _, newHeight in
                viewModel.stripHeight = newHeight
            }
        }
    }
}

/// The per-image badge shown in the strip: a hamburger handle to drag the image to a
/// new position, and an ✕ to drop it from the comparison.
private struct ImageControls: View {
    let item: DroppedImage
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .draggable(item.id.uuidString) {
                    Image(nsImage: item.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                }
                .onHover { inside in
                    if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                }
                .help("Drag onto another image to reorder")

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove this image")
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.25)))
    }
}

/// A draggable, deletable horizontal ruler line spanning the full width of the strip.
private struct RulerLine: View {
    @Binding var ruler: Ruler
    let maxY: CGFloat
    let onDelete: () -> Void

    @State private var dragBase: CGFloat?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Wider transparent band so the thin line is easy to grab.
            Color.clear
                .frame(height: 20)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 2) {
                Rectangle()
                    .fill(Color.cyan)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 4) {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete ruler")

                    Image(systemName: "arrow.up.and.down")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }
                .padding(.leading, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onHover { inside in
            if inside {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    NSCursor.resizeUpDown.set()
                    let base = dragBase ?? ruler.y
                    if dragBase == nil { dragBase = base }
                    ruler.y = min(max(0, base + value.translation.height), maxY)
                }
                .onEnded { _ in dragBase = nil }
        )
    }
}

/// The dashed red measure line between two points. Never intercepts clicks.
private struct MeasureLine: View {
    let a: CGPoint
    let b: CGPoint

    var body: some View {
        Path { path in
            path.move(to: a)
            path.addLine(to: b)
        }
        .stroke(Color.red, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// The pixel-distance label at a measurement's midpoint, with an optional delete affordance.
private struct MeasureLabel: View {
    let a: CGPoint
    let b: CGPoint
    var onDelete: (() -> Void)?

    var body: some View {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let distance = Int(hypot(dx, dy).rounded())
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let isHorizontal = abs(dx) >= abs(dy)
        // Horizontal → label above the line; vertical → label to the right of the line.
        let anchor = isHorizontal
            ? CGPoint(x: mid.x - 16, y: mid.y - 26)
            : CGPoint(x: mid.x + 10, y: mid.y - 10)

        HStack(spacing: 6) {
            Text("\(distance) px")
                .font(.caption.bold())
                .foregroundStyle(.red)
            if let onDelete {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.medium)
                    .foregroundStyle(.red)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture { onDelete() }
                    .help("Delete measurement")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .fixedSize()
        // Offset (not .position) so the label only occupies its own rect and never blocks clicks.
        .offset(x: anchor.x, y: anchor.y)
    }
}

private extension View {
    @ViewBuilder
    func applyIf(_ condition: Bool, _ transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}
