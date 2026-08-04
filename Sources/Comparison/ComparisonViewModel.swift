import CoreGraphics
import Foundation
import Observation

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

/// Owns everything the comparison tab remembers — the images being compared and the
/// ruler / measure overlay — and every action the view can trigger on it.
@MainActor
@Observable
final class ComparisonViewModel {
    /// The images laid out in the strip.
    let images = DropModel()

    var rulers: [Ruler] = []
    var measurements: [Measurement] = []

    /// Height of the strip, tracked so a new ruler lands in its middle.
    var stripHeight: CGFloat = 0

    /// The image currently under a reorder drag, highlighted as the drop slot.
    var dropTargetID: DroppedImage.ID?

    // Measure tool state.
    private(set) var isMeasuring = false
    private(set) var pendingStart: CGPoint?
    private(set) var previewPoint: CGPoint?

    var hasImages: Bool { !images.items.isEmpty }
    var hasOverlay: Bool { !rulers.isEmpty || !measurements.isEmpty }

    /// The measurement being drawn right now, if the first point is down and the pointer is inside.
    var measurePreview: (a: CGPoint, b: CGPoint)? {
        guard isMeasuring, let pendingStart, let previewPoint else { return nil }
        return (pendingStart, previewPoint)
    }

    // MARK: - Images

    func removeImage(id: DroppedImage.ID) {
        images.remove(id: id)
    }

    func moveImage(id: DroppedImage.ID, toSlotOf targetID: DroppedImage.ID) -> Bool {
        images.move(id: id, toSlotOf: targetID)
    }

    // MARK: - Rulers

    func addRuler() {
        rulers.append(Ruler(y: max(0, stripHeight / 2)))
    }

    func deleteRuler(id: Ruler.ID) {
        rulers.removeAll { $0.id == id }
    }

    // MARK: - Measurements

    func toggleMeasuring() {
        isMeasuring.toggle()
        cancelPendingMeasure()
    }

    /// Handles a click in the strip while measuring: the first sets the start point, the
    /// second completes the measurement and switches the tool back off — one measurement
    /// per activation, so a stray click can't start another.
    func measureTap(at location: CGPoint) {
        if let start = pendingStart {
            measurements.append(Measurement(a: start, b: location))
            isMeasuring = false
            cancelPendingMeasure()
        } else {
            pendingStart = location
        }
    }

    /// Tracks the pointer so the in-progress measurement follows it.
    func updateMeasurePreview(to location: CGPoint?) {
        previewPoint = location
    }

    func deleteMeasurement(id: Measurement.ID) {
        measurements.removeAll { $0.id == id }
    }

    // MARK: - Clearing

    /// Drops a half-finished measurement and its hover preview.
    func cancelPendingMeasure() {
        pendingStart = nil
        previewPoint = nil
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
