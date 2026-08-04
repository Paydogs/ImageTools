import AppKit
import ImageIO

/// A single image that was dropped onto the app, with its loaded preview and metadata.
struct DroppedImage: Identifiable {
    let id = UUID()
    let url: URL
    let image: NSImage
    let byteSize: Int64
    let pixelWidth: Int
    let pixelHeight: Int

    /// User-editable base name used for exported files. Defaults to the source file name.
    var exportName: String

    var name: String { url.lastPathComponent }
    var ext: String { url.pathExtension.uppercased() }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file) }
    var resolution: String { "\(pixelWidth) × \(pixelHeight)" }

    /// The export base name, falling back to the source file name if the field is left blank.
    var effectiveName: String {
        let trimmed = exportName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? url.deletingPathExtension().lastPathComponent : trimmed
    }
}

extension DroppedImage {
    /// File extensions this app accepts.
    static let acceptedExtensions: Set<String> = ["png", "jpg", "jpeg"]

    /// Loads the image and its metadata from a file URL. Returns nil for unsupported or unreadable files.
    init?(url: URL) {
        guard Self.acceptedExtensions.contains(url.pathExtension.lowercased()),
              let image = NSImage(contentsOf: url) else { return nil }
        self.url = url
        self.image = image
        self.exportName = url.deletingPathExtension().lastPathComponent

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.byteSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

        var width = 0
        var height = 0
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        }
        self.pixelWidth = width
        self.pixelHeight = height
    }
}
