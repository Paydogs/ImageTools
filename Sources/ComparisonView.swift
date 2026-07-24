import AppKit
import SwiftUI

/// A horizontal guide line placed across the comparison strip.
struct Ruler: Identifiable {
    let id = UUID()
    var y: CGFloat
}

/// A two-point measurement drawn across the comparison strip.
struct Measurement: Identifiable {
    let id = UUID()
    var a: CGPoint
    var b: CGPoint
}

/// Compares images side by side, flush against each other with only a 1px red divider between them.
/// Supports draggable horizontal rulers and two-click pixel measurements.
struct ComparisonView: View {
    @StateObject private var model = DropModel()
    @State private var rulers: [Ruler] = []
    @State private var stripHeight: CGFloat = 0

    /// The image currently under a reorder drag, highlighted as the drop slot.
    @State private var dropTargetID: DroppedImage.ID?

    // Measure tool state.
    @State private var measuring = false
    @State private var measurements: [Measurement] = []
    @State private var pendingStart: CGPoint?
    @State private var previewPoint: CGPoint?

    var body: some View {
        HStack(spacing: 0) {
            // Left — the drop / select area and tool commands
            VStack(spacing: 12) {
                DropZoneView(model: model)

                HStack(spacing: 8) {
                    Button {
                        rulers.append(Ruler(y: max(0, stripHeight / 2)))
                    } label: {
                        Label("Add Ruler", systemImage: "ruler")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .disabled(model.items.isEmpty)
                    .hoverHelp("Adds a cyan horizontal guide line. Drag it up or down, or click the red ✕ to delete it.")

                    Button {
                        measuring.toggle()
                        pendingStart = nil
                        previewPoint = nil
                    } label: {
                        Label("Measure", systemImage: "arrow.up.left.and.arrow.down.right")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .tint(measuring ? .accentColor : .secondary)
                    .disabled(model.items.isEmpty)
                    .hoverHelp("Click two points to draw a dashed line showing the distance between them in pixels. Toggle off when done.")
                }

                if !rulers.isEmpty || !measurements.isEmpty {
                    Button("Clear Overlay") {
                        rulers.removeAll()
                        measurements.removeAll()
                        pendingStart = nil
                        previewPoint = nil
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }

                if !model.items.isEmpty {
                    Button("Clear Workspace", role: .destructive) {
                        model.clear()
                        rulers.removeAll()
                        measurements.removeAll()
                        pendingStart = nil
                        previewPoint = nil
                        measuring = false
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                Spacer()
            }
            .padding()
            .frame(width: 160)

            Divider()

            // Right — the flush comparison strip with overlays
            Group {
                if model.items.isEmpty {
                    Text("Drop or select images to compare")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    comparisonStrip
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
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
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
                                    model.remove(id: item.id)
                                }
                                .padding(6)
                            }
                            // Drop target: the dragged image takes over this image's slot.
                            .overlay(alignment: .leading) {
                                if dropTargetID == item.id {
                                    Rectangle()
                                        .fill(Color.accentColor)
                                        .frame(width: 3)
                                        .allowsHitTesting(false)
                                }
                            }
                            .dropDestination(for: String.self) { identifiers, _ in
                                dropTargetID = nil
                                guard let dragged = identifiers.first,
                                      let id = UUID(uuidString: dragged) else { return false }
                                return model.move(id: id, toSlotOf: item.id)
                            } isTargeted: { targeted in
                                if targeted {
                                    dropTargetID = item.id
                                } else if dropTargetID == item.id {
                                    dropTargetID = nil
                                }
                            }
                    }
                }
            }
            // Rulers
            .overlay(alignment: .top) {
                ForEach($rulers) { $ruler in
                    RulerLine(ruler: $ruler, maxY: geometry.size.height) {
                        rulers.removeAll { $0.id == ruler.id }
                    }
                    .offset(y: ruler.y)
                }
            }
            // Measurements + measure interaction
            .overlay {
                ZStack(alignment: .topLeading) {
                    // Non-interactive dashed lines.
                    ForEach(measurements) { measurement in
                        MeasureLine(a: measurement.a, b: measurement.b)
                    }
                    if measuring, let start = pendingStart, let preview = previewPoint {
                        MeasureLine(a: start, b: preview)
                        MeasureLabel(a: start, b: preview)
                    }

                    // Distance labels; each ✕ has its own tap gesture that (as a descendant)
                    // takes priority over the container's measure tap below.
                    ForEach(measurements) { measurement in
                        MeasureLabel(a: measurement.a, b: measurement.b) {
                            measurements.removeAll { $0.id == measurement.id }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Measure interaction lives on the container, active only while measuring.
                .applyIf(measuring) { view in
                    view
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if case .active(let location) = phase { previewPoint = location }
                        }
                        .onTapGesture(count: 1, coordinateSpace: .local) { location in
                            if pendingStart == nil {
                                pendingStart = location
                            } else if let start = pendingStart {
                                measurements.append(Measurement(a: start, b: location))
                                pendingStart = nil
                            }
                        }
                }
            }
            .onAppear { stripHeight = geometry.size.height }
            .onChange(of: geometry.size.height) { _, newHeight in stripHeight = newHeight }
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

/// Shows a helper popover after hovering over a view for 3 seconds.
private struct HoverHelp: ViewModifier {
    let text: String
    @State private var showHelp = false
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                task?.cancel()
                if inside {
                    task = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if !Task.isCancelled { showHelp = true }
                    }
                } else {
                    showHelp = false
                }
            }
            .popover(isPresented: $showHelp, arrowEdge: .trailing) {
                Text(text)
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: 260)
            }
    }
}

private extension View {
    func hoverHelp(_ text: String) -> some View {
        modifier(HoverHelp(text: text))
    }
}
