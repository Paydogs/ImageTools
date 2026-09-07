import AppKit
import SwiftUI

/// Compares images side by side, flush against each other with only a 1px red divider between them.
/// Supports draggable horizontal and vertical rulers and two-click pixel measurements.
/// All state and behaviour live in `ComparisonViewModel`.
struct ComparisonView: View {
    @State private var viewModel = ComparisonViewModel()

    /// True while the pointer is over the strip, so ⌘-scroll only zooms what it is pointing at.
    @State private var isPointerInStrip = false
    /// The ⌘-scroll watcher, kept so it can be torn down with the view.
    @State private var zoomMonitor: Any?

    /// Drives the strip's scroll offset, so zooming can keep the cursor over the same pixel.
    @State private var scrollPosition = ScrollPosition()
    /// Where the strip is scrolled to now, in zoomed points.
    @State private var contentOffset: CGPoint = .zero

    var body: some View {
        HStack(spacing: 0) {
            // Left — the drop / select area and tool commands
            ToolSidebar(model: viewModel.images) {
                HStack(spacing: 8) {
                    ComparisonToolView(
                        title: "Add Horizontal Ruler",
                        icon: "ruler",
                        key: "h",
                        help: "Adds a cyan horizontal guide line. Drag it up or down, or click the red ✕ to delete it.",
                        action: { viewModel.addRuler(.horizontal) }
                    )
                    .disabled(!viewModel.hasImages)

                    ComparisonToolView(
                        title: "Add Vertical Ruler",
                        icon: "ruler",
                        key: "v",
                        iconRotation: .degrees(90),
                        help: "Adds a cyan vertical guide line. Drag it left or right, or click the red ✕ to delete it.",
                        action: { viewModel.addRuler(.vertical) }
                    )
                    .disabled(!viewModel.hasImages)

                    ComparisonToolView(
                        title: "Measure",
                        icon: "arrow.up.left.and.arrow.down.right",
                        key: "m",
                        help: "Click two points to draw a dashed line showing the distance between them in pixels. Click on a ruler to measure to it instead of to a point. Toggle off when done.",
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
            } footer: {
                ZoomField(zoom: $viewModel.zoom, range: ComparisonViewModel.zoomRange)
                    .disabled(!viewModel.hasImages)
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
            let scale = viewModel.scale
            // Both axes: above 100% the images are taller and wider than the strip.
            ScrollView([.horizontal, .vertical]) {
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
                            .frame(height: geometry.size.height * scale)
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
                // Tracked whenever the pointer is over the images, so a new ruler can land
                // under it. Sits under the overlays, which report it themselves where they
                // take the hover instead.
                .onContinuousHover { phase in
                    viewModel.updatePointer(to: hoverLocation(phase, scale: scale))
                }
                // The overlays sit on the images rather than on the strip, so they zoom and
                // scroll with them. Everything inside is stored unzoomed and drawn at `scale`.
                .overlay(alignment: .topLeading) { rulers(scale: scale) }
                .overlay { measurements(scale: scale) }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    viewModel.contentSize = size.scaled(by: 1 / viewModel.scale)
                }
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { _, offset in
                contentOffset = offset
            }
            .onChange(of: viewModel.zoom) { old, new in
                zoomAroundPointer(from: CGFloat(old) / 100, to: CGFloat(new) / 100,
                                  viewport: geometry.size)
            }
            .onHover { isPointerInStrip = $0 }
            .onAppear(perform: startZoomMonitor)
            .onDisappear(perform: stopZoomMonitor)
        }
    }

    /// Keeps whatever the cursor is over under the cursor as the zoom changes, by scrolling the
    /// strip by exactly as much as that point moved. Does nothing when the pointer is off the
    /// images — zooming from the text box has no point to keep still.
    private func zoomAroundPointer(from old: CGFloat, to new: CGFloat, viewport: CGSize) {
        guard let pointer = viewModel.pointer, old != new else { return }

        let content = viewModel.contentSize.scaled(by: new)
        let target = CGPoint(
            x: contentOffset.x + pointer.x * (new - old),
            y: contentOffset.y + pointer.y * (new - old)
        )
        // Clamped the way the strip itself would, so a run of ⌘-scrolls does not build up an
        // offset it was never able to honour.
        let clamped = CGPoint(
            x: min(max(0, target.x), max(0, content.width - viewport.width)),
            y: min(max(0, target.y), max(0, content.height - viewport.height))
        )
        // Recorded straight away so the next notch builds on the offset just asked for rather
        // than the one the strip has caught up to.
        contentOffset = clamped
        scrollPosition.scrollTo(point: clamped)
    }

    /// A hover phase as an unzoomed point on the images, or nil once the pointer leaves.
    private func hoverLocation(_ phase: HoverPhase, scale: CGFloat) -> CGPoint? {
        guard case .active(let location) = phase else { return nil }
        return location.scaled(by: 1 / scale)
    }

    /// Watches for ⌘-scroll over the strip and steps the zoom instead of scrolling. A plain
    /// scroll is passed straight through, so the strip still pans normally.
    private func startZoomMonitor() {
        guard zoomMonitor == nil else { return }
        zoomMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard isPointerInStrip, event.modifierFlags.contains(.command) else { return event }
            let delta = event.scrollingDeltaY
            guard delta != 0 else { return nil }
            viewModel.stepZoom(up: delta > 0)
            // Swallowed, so the strip does not scroll while zooming.
            return nil
        }
    }

    private func stopZoomMonitor() {
        if let zoomMonitor { NSEvent.removeMonitor(zoomMonitor) }
        zoomMonitor = nil
    }

    /// The ruler lines, drawn at the current zoom.
    private func rulers(scale: CGFloat) -> some View {
        // The explicit ZStack matters: `overlay(alignment:)` aligns its content as a unit, so
        // the implicit stack around a ForEach would centre the differently sized horizontal and
        // vertical lines against each other and shift both off their position.
        ZStack(alignment: .topLeading) {
            ForEach($viewModel.rulers) { $ruler in
                RulerLine(
                    ruler: $ruler,
                    bounds: viewModel.contentSize,
                    scale: scale,
                    isHighlighted: viewModel.highlightedRulerIDs.contains(ruler.id)
                ) {
                    viewModel.deleteRuler(id: ruler.id)
                }
                .offset(ruler.offset.scaled(by: scale))
            }
        }
    }

    /// The measurements and, while the tool is on, the clicks that create them.
    private func measurements(scale: CGFloat) -> some View {
        let bounds = viewModel.contentSize.scaled(by: scale)

        return ZStack(alignment: .topLeading) {
            // Non-interactive dashed lines.
            ForEach(viewModel.measurements) { measurement in
                let ends = viewModel.endpoints(of: measurement)
                MeasureLine(a: ends.a.scaled(by: scale), b: ends.b.scaled(by: scale))
            }
            if let preview = viewModel.measurePreview {
                let a = preview.a.scaled(by: scale)
                let b = preview.b.scaled(by: scale)
                MeasureLine(a: a, b: b)
                MeasureLabel(a: a, b: b, bounds: bounds, scale: scale)
            }

            // Distance labels; each ✕ has its own tap gesture that (as a descendant)
            // takes priority over the container's measure tap below.
            ForEach(viewModel.measurements) { measurement in
                let ends = viewModel.endpoints(of: measurement)
                MeasureLabel(a: ends.a.scaled(by: scale), b: ends.b.scaled(by: scale), bounds: bounds, scale: scale) {
                    viewModel.deleteMeasurement(id: measurement.id)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Measure interaction lives on the container, active only while measuring. Clicks come
        // in at the current zoom and are stored unzoomed.
        .applyIf(viewModel.isMeasuring) { view in
            view
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    viewModel.updatePointer(to: hoverLocation(phase, scale: scale))
                }
                .onTapGesture(count: 1, coordinateSpace: .local) { location in
                    viewModel.measureTap(at: location.scaled(by: 1 / scale))
                }
        }
    }
}

private extension CGPoint {
    func scaled(by scale: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
}

private extension CGSize {
    func scaled(by scale: CGFloat) -> CGSize { CGSize(width: width * scale, height: height * scale) }
}

/// The zoom box at the bottom of the sidebar. It takes whole percentages only — anything
/// that is not a digit is refused as it is typed — and clamps to the allowed range when the
/// field is committed or loses focus, since a partly typed number cannot be clamped yet.
private struct ZoomField: View {
    @Binding var zoom: Int
    let range: ClosedRange<Int>

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("Zoom")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    // Return keeps the value, Escape puts back the one in force; both hand
                    // focus back so the tool shortcuts work again without reaching for the mouse.
                    .onSubmit {
                        commit()
                        leave()
                    }
                    .onExitCommand {
                        text = String(zoom)
                        leave()
                    }
                    .onChange(of: text) { _, typed in
                        let digits = String(typed.filter(\.isNumber).prefix(3))
                        if digits != typed { text = digits }
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commit() }
                    }

                Text("%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { text = String(zoom) }
        // Keep in step with the model when something else changes the zoom.
        .onChange(of: zoom) { _, value in
            if !isFocused { text = String(value) }
        }
        .help("Zoom every image, and the rulers and measurements on them, from \(range.lowerBound)% to \(range.upperBound)%. ⌘-scroll over the images to step it.")
    }

    private func commit() {
        zoom = min(max(Int(text) ?? zoom, range.lowerBound), range.upperBound)
        text = String(zoom)
    }

    /// Gives up focus. Dropping `isFocused` is not enough on its own — the field is the only
    /// thing in the window that takes focus, so it is handed straight back unless the window
    /// itself takes over as first responder.
    private func leave() {
        isFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
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

/// A draggable, deletable ruler line spanning the strip along its orientation: a horizontal
/// ruler runs the full width and drags up and down, a vertical one the full height and drags
/// left and right.
private struct RulerLine: View {
    @Binding var ruler: Ruler
    /// The unzoomed content the ruler is confined to.
    let bounds: CGSize
    /// Current zoom, to turn a drag in screen points back into unzoomed units.
    let scale: CGFloat
    /// Set while the measure tool is about to attach a measurement to this ruler.
    var isHighlighted = false
    let onDelete: () -> Void

    @State private var dragBase: CGFloat?

    private var isHorizontal: Bool { ruler.orientation == .horizontal }

    /// Wider transparent band so the thin line is easy to grab.
    private static let grabWidth: CGFloat = 20

    var body: some View {
        // The two orientations are mirror images, so the same content just swaps its axes.
        let lineAndControls = isHorizontal
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 2))
        let controls = isHorizontal
            ? AnyLayout(HStackLayout(spacing: 4))
            : AnyLayout(VStackLayout(spacing: 4))

        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(
                    width: isHorizontal ? nil : Self.grabWidth,
                    height: isHorizontal ? Self.grabWidth : nil
                )
                .contentShape(Rectangle())

            lineAndControls {
                Rectangle()
                    .fill(isHighlighted ? Color.accentColor : .cyan)
                    .frame(
                        width: isHorizontal ? nil : (isHighlighted ? 3 : 1),
                        height: isHorizontal ? (isHighlighted ? 3 : 1) : nil
                    )

                controls {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete ruler")

                    Image(systemName: isHorizontal ? "arrow.up.and.down" : "arrow.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }
                .padding(isHorizontal ? .leading : .top, 6)
            }
        }
        .frame(
            maxWidth: isHorizontal ? .infinity : nil,
            maxHeight: isHorizontal ? nil : .infinity,
            alignment: .topLeading
        )
        .onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    cursor.set()
                    let base = dragBase ?? ruler.position
                    if dragBase == nil { dragBase = base }
                    let moved = base + ruler.orientation.extent(of: value.translation) / scale
                    ruler.position = min(max(0, moved), ruler.orientation.extent(of: bounds))
                }
                .onEnded { _ in dragBase = nil }
        )
    }

    private var cursor: NSCursor {
        isHorizontal ? .resizeUpDown : .resizeLeftRight
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

/// The pixel-distance label for a measurement, with an optional delete affordance. It sits
/// clear of the line — 5px above it, or 5px under when there is no room above — rather than
/// on top of it, so it never hides what is being measured.
private struct MeasureLabel: View {
    let a: CGPoint
    let b: CGPoint
    /// The strip, so the bubble can flip under the line and stay inside the left and right edges.
    let bounds: CGSize
    /// Current zoom. The ends arrive zoomed, for placement; the distance is reported unzoomed,
    /// so it describes the images themselves and does not change as you zoom in and out.
    let scale: CGFloat
    var onDelete: (() -> Void)?

    /// The bubble's own size, measured so it can be centred on the line and cleared of it exactly.
    @State private var size: CGSize = .zero

    private static let gap: CGFloat = 5

    var body: some View {
        let distance = Int((hypot(b.x - a.x, b.y - a.y) / scale).rounded())
        // Clearing the line's highest and lowest points keeps the bubble off it at any angle.
        let above = min(a.y, b.y) - Self.gap - size.height
        let y = above >= 0 ? above : max(a.y, b.y) + Self.gap
        let centred = (a.x + b.x) / 2 - size.width / 2
        let x = min(max(0, centred), max(0, bounds.width - size.width))

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
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        // Hidden until measured, so it never flashes at an unplaced position.
        .opacity(size == .zero ? 0 : 1)
        // Offset (not .position) so the label only occupies its own rect and never blocks clicks.
        .offset(x: x, y: y)
    }
}

private extension View {
    @ViewBuilder
    func applyIf(_ condition: Bool, _ transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}
