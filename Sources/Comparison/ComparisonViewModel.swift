import CoreGraphics
import Foundation
import Observation

/// A guide line placed across the comparison strip. It runs along one axis and pins the
/// coordinate on the other: a horizontal ruler fixes `y`, a vertical one fixes `x`.
struct Ruler: Identifiable {
    enum Orientation {
        case horizontal
        case vertical

        /// The coordinate a ruler of this orientation pins — y for horizontal, x for vertical.
        func coordinate(of point: CGPoint) -> CGFloat {
            switch self {
            case .horizontal: point.y
            case .vertical: point.x
            }
        }

        /// The matching size component: the strip's height bounds a horizontal ruler, its
        /// width a vertical one. Also picks the component of a drag translation that moves it.
        func extent(of size: CGSize) -> CGFloat {
            switch self {
            case .horizontal: size.height
            case .vertical: size.width
            }
        }
    }

    let id = UUID()
    let orientation: Orientation
    /// Distance from the top of the strip for a horizontal ruler, from its leading edge for a vertical one.
    var position: CGFloat

    /// The x this ruler pins, if it pins one — a horizontal ruler leaves x free.
    var x: CGFloat? { orientation == .vertical ? position : nil }
    /// The y this ruler pins, if it pins one — a vertical ruler leaves y free.
    var y: CGFloat? { orientation == .horizontal ? position : nil }

    /// Where the line sits, as an offset from the strip's top-leading corner.
    var offset: CGSize {
        switch orientation {
        case .horizontal: CGSize(width: 0, height: position)
        case .vertical: CGSize(width: position, height: 0)
        }
    }
}

/// A two-point measurement drawn across the comparison strip. It keeps its ends as anchors
/// rather than fixed points, so one made against a ruler follows that ruler as it moves.
struct Measurement: Identifiable {
    let id = UUID()
    var a: MeasureAnchor
    var b: MeasureAnchor
    /// Where the pointer was when the measurement was made, filling the coordinate neither
    /// end pins — the case where both ends are rulers.
    var pointer: CGPoint
}

/// One end of a measurement being drawn. A free point pins both coordinates; a ruler pins
/// only the one it runs along, leaving the other to be resolved against the opposite end.
enum MeasureAnchor {
    case point(CGPoint)
    case ruler(Ruler)

    var x: CGFloat? {
        switch self {
        case .point(let point): point.x
        case .ruler(let ruler): ruler.x
        }
    }

    var y: CGFloat? {
        switch self {
        case .point(let point): point.y
        case .ruler(let ruler): ruler.y
        }
    }

    /// The ruler this anchor is attached to, so the view can highlight it.
    var rulerID: Ruler.ID? {
        switch self {
        case .point: nil
        case .ruler(let ruler): ruler.id
        }
    }

    var isPoint: Bool {
        if case .point = self { return true }
        return false
    }

    /// Re-reads the ruler this anchor is pinned to, so a measurement follows it as it moves.
    /// A ruler that is gone keeps the position stored here, leaving the measurement where it was.
    func current(in rulers: [Ruler]) -> MeasureAnchor {
        guard case .ruler(let ruler) = self else { return self }
        return .ruler(rulers.first { $0.id == ruler.id } ?? ruler)
    }

    /// Re-pins this anchor to `ruler` if that is the ruler it references, capturing where the
    /// ruler stands now.
    func repinned(to ruler: Ruler) -> MeasureAnchor {
        guard case .ruler(let pinned) = self, pinned.id == ruler.id else { return self }
        return .ruler(ruler)
    }
}

/// Owns everything the comparison tab remembers — the images being compared and the
/// ruler / measure overlay — and every action the view can trigger on it.
@MainActor
@Observable
final class ComparisonViewModel {
    /// The images laid out in the strip.
    let images = DropModel()

    var rulers: [Ruler] = []
    var measurements: [Measurement] = []

    /// Size of the image content at 100%, tracked so a new ruler lands in its middle and
    /// drags stay inside it. Rulers and measurements are all stored in these unzoomed
    /// coordinates, so they keep their place on the images at any zoom.
    var contentSize: CGSize = .zero

    /// Zoom applied to the images and everything overlaid on them, as a percentage. Always
    /// inside `zoomRange` — anything outside is clamped on the way in. Clamping has to happen
    /// in the setter rather than a `didSet`: `@Observable` rewrites stored properties as
    /// computed ones, where assigning to the property from its own observer recurses forever.
    var zoom: Int {
        get { rawZoom }
        set { rawZoom = min(max(Self.zoomRange.lowerBound, newValue), Self.zoomRange.upperBound) }
    }

    private var rawZoom = 100

    static let zoomRange = 10...500
    /// How much one notch of ⌘-scroll changes the zoom.
    static let zoomStep = 5

    var scale: CGFloat { CGFloat(zoom) / 100 }

    /// The image currently under a reorder drag, highlighted as the drop slot.
    var dropTargetID: DroppedImage.ID?

    // Measure tool state.
    private(set) var isMeasuring = false
    private(set) var pendingAnchor: MeasureAnchor?

    /// Where the pointer is over the images, in unzoomed coordinates, or nil while it is
    /// elsewhere. Drives both the measurement being drawn and where a new ruler lands.
    private(set) var pointer: CGPoint?

    /// How close a click has to land to a ruler to snap onto it instead of being a free point,
    /// in screen points — so it stays equally easy to hit whatever the zoom.
    private static let snapDistance: CGFloat = 8

    var hasImages: Bool { !images.items.isEmpty }
    var hasOverlay: Bool { !rulers.isEmpty || !measurements.isEmpty }

    /// The measurement being drawn right now, if the first end is down and the pointer is inside.
    /// The pointer end snaps to a ruler under it, so the preview shows exactly what a click lands.
    var measurePreview: (a: CGPoint, b: CGPoint)? {
        guard isMeasuring, let pendingAnchor, let pointer else { return nil }
        return endpoints(pendingAnchor.current(in: rulers), anchor(at: pointer), pointer: pointer)
    }

    /// Rulers taking part in the measurement being drawn — the pinned end and the one under
    /// the pointer — so the view can show which ones the measurement will attach to.
    var highlightedRulerIDs: Set<Ruler.ID> {
        guard isMeasuring else { return [] }
        var ids: Set<Ruler.ID> = []
        if let id = pendingAnchor?.rulerID { ids.insert(id) }
        if let pointer, let id = anchor(at: pointer).rulerID { ids.insert(id) }
        return ids
    }

    // MARK: - Images

    func removeImage(id: DroppedImage.ID) {
        images.remove(id: id)
    }

    func moveImage(id: DroppedImage.ID, toSlotOf targetID: DroppedImage.ID) -> Bool {
        images.move(id: id, toSlotOf: targetID)
    }

    /// Steps the zoom one notch up or down, for ⌘-scroll. Clamped like any other change.
    func stepZoom(up: Bool) {
        zoom += up ? Self.zoomStep : -Self.zoomStep
    }

    // MARK: - Rulers

    /// Adds a ruler under the pointer — a horizontal one at its y, a vertical one at its x —
    /// falling back to the middle of the images when the pointer is not over them.
    func addRuler(_ orientation: Ruler.Orientation) {
        let extent = orientation.extent(of: contentSize)
        let wanted = pointer.map { orientation.coordinate(of: $0) } ?? extent / 2
        rulers.append(Ruler(orientation: orientation, position: min(max(0, wanted), extent)))
    }

    func deleteRuler(id: Ruler.ID) {
        // Measurements pinned to this ruler stay where it was rather than snapping back to
        // wherever it stood when they were made.
        if let ruler = rulers.first(where: { $0.id == id }) {
            for index in measurements.indices {
                measurements[index].a = measurements[index].a.repinned(to: ruler)
                measurements[index].b = measurements[index].b.repinned(to: ruler)
            }
        }
        rulers.removeAll { $0.id == id }
    }

    // MARK: - Measurements

    func toggleMeasuring() {
        isMeasuring.toggle()
        cancelPendingMeasure()
    }

    /// Handles a click in the strip while measuring: the first sets the start end, the
    /// second completes the measurement and switches the tool back off — one measurement
    /// per activation, so a stray click can't start another. Either end snaps onto a ruler
    /// clicked near enough to it.
    func measureTap(at location: CGPoint) {
        let clicked = anchor(at: location)
        if let start = pendingAnchor {
            measurements.append(Measurement(a: start, b: clicked, pointer: location))
            isMeasuring = false
            cancelPendingMeasure()
        } else {
            pendingAnchor = clicked
        }
    }

    /// Snaps a click onto the nearest ruler within `snapDistance`, or keeps it a free point.
    private func anchor(at location: CGPoint) -> MeasureAnchor {
        let tolerance = Self.snapDistance / scale
        let nearest = rulers
            .map { (ruler: $0, distance: abs($0.position - $0.orientation.coordinate(of: location))) }
            .filter { $0.distance <= tolerance }
            .min { $0.distance < $1.distance }

        return nearest.map { .ruler($0.ruler) } ?? .point(location)
    }

    /// Where a stored measurement's ends sit now, following any rulers they are pinned to.
    func endpoints(of measurement: Measurement) -> (a: CGPoint, b: CGPoint) {
        endpoints(
            measurement.a.current(in: rulers),
            measurement.b.current(in: rulers),
            pointer: measurement.pointer
        )
    }

    /// Turns the two ends into concrete points. A ruler end is missing one coordinate: it
    /// takes it from the opposite end when that end is a free point, and from the pointer
    /// when both ends are rulers.
    private func endpoints(
        _ a: MeasureAnchor,
        _ b: MeasureAnchor,
        pointer: CGPoint
    ) -> (CGPoint, CGPoint) {
        (resolve(a, against: b, pointer: pointer), resolve(b, against: a, pointer: pointer))
    }

    private func resolve(_ anchor: MeasureAnchor, against other: MeasureAnchor, pointer: CGPoint) -> CGPoint {
        let fallback = other.isPoint ? CGPoint(x: other.x ?? pointer.x, y: other.y ?? pointer.y) : pointer
        return CGPoint(x: anchor.x ?? fallback.x, y: anchor.y ?? fallback.y)
    }

    /// Tracks where the pointer is over the images.
    func updatePointer(to location: CGPoint?) {
        pointer = location
    }

    func deleteMeasurement(id: Measurement.ID) {
        measurements.removeAll { $0.id == id }
    }

    // MARK: - Clearing

    /// Drops a half-finished measurement. The pointer is left alone: it tracks where the
    /// mouse actually is, not what the measure tool is doing.
    func cancelPendingMeasure() {
        pendingAnchor = nil
    }

    /// Removes every ruler and measurement, leaving the images in place.
    func clearOverlay() {
        rulers.removeAll()
        measurements.removeAll()
        cancelPendingMeasure()
    }

    /// Removes the images along with the whole overlay and leaves measure mode.
    func clearWorkspace() {
        images.clear()
        clearOverlay()
        isMeasuring = false
    }
}
