import AppKit
import Observation

/// Holds the list of dropped images and handles incoming drops.
@MainActor
@Observable
final class DropModel {
    var items: [DroppedImage] = []

    /// Loads dropped file URLs, keeping only supported images. Loading happens off the
    /// main thread; each successfully loaded image is appended on the main actor.
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let self, let url, let item = DroppedImage(url: url) else { return }
                Task { @MainActor in self.items.append(item) }
            }
        }
        return handled
    }

    /// Imports file URLs directly (e.g. from the open panel), keeping only supported images.
    func importURLs(_ urls: [URL]) {
        for url in urls {
            if let item = DroppedImage(url: url) { items.append(item) }
        }
    }

    func clear() {
        items.removeAll()
    }

    /// Removes a single image.
    func remove(id: DroppedImage.ID) {
        items.removeAll { $0.id == id }
    }

    /// Moves the image with `id` into the slot currently occupied by `targetID`.
    /// Returns false when either id is unknown or the move would change nothing.
    @discardableResult
    func move(id: DroppedImage.ID, toSlotOf targetID: DroppedImage.ID) -> Bool {
        guard id != targetID,
              let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == targetID }) else { return false }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        return true
    }
}
