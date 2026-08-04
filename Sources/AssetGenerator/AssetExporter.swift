import AppKit
import ImageIO

/// Resizes source images and writes correctly-named PNG files for each asset size.
enum AssetExporter {
    /// High-quality resize of the source image to an exact pixel size, encoded as PNG.
    static func resizedPNGData(from source: URL, width: Int, height: Int) -> Data? {
        guard width > 0, height > 0,
              let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let context = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])
    }

    /// Writes a resized file into the destination (or a temp folder) using platform-correct
    /// naming and folder layout, and returns its URL. Apple imagesets use `name@2x.png` files
    /// grouped under `ios/` `macos/`; Android uses `name.png` inside `drawable-<density>/`.
    static func writeResized(
        image: DroppedImage,
        platform: AssetPlatform,
        size: AssetSize,
        width: Int,
        height: Int,
        destination: URL?
    ) -> URL? {
        guard let data = resizedPNGData(from: image.url, width: width, height: height) else { return nil }

        let root = destination ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageAssetTools", isDirectory: true)
        let baseName = image.effectiveName

        let directory: URL
        let fileName: String
        if let folder = size.folder {
            directory = root.appendingPathComponent(folder, isDirectory: true)
            fileName = androidResourceName(baseName) + ".png"
        } else {
            directory = root.appendingPathComponent(platform.name.lowercased(), isDirectory: true)
            fileName = baseName + size.fileSuffix + ".png"
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(fileName)
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    /// Result summary of a full export.
    struct ExportResult {
        var fileCount = 0
        var imageSetCount = 0
        var errors: [String] = []
    }

    /// Exports every dropped image to the destination as proper platform assets:
    /// `ios/<name>.imageset/` and `macos/<name>.imageset/` (each with a Contents.json),
    /// plus `android/drawable-<density>/<name>.png`.
    static func exportImageSets(
        images: [DroppedImage],
        destination: URL,
        enabledPlatforms: Set<String>
    ) -> ExportResult {
        var result = ExportResult()
        let fileManager = FileManager.default

        for image in images {
            let baseName = image.effectiveName

            for platform in AssetCatalog.platforms where enabledPlatforms.contains(platform.name) {
                if platform.name == "Android" {
                    for size in platform.sizes {
                        let dimensions = size.pixelSize(
                            sourceWidth: image.pixelWidth, sourceHeight: image.pixelHeight,
                            maxScale: platform.maxScale
                        )
                        guard let data = resizedPNGData(from: image.url, width: dimensions.width, height: dimensions.height) else {
                            result.errors.append("\(baseName) \(size.label)")
                            continue
                        }
                        let directory = destination.appendingPathComponent("android/\(size.folder ?? "drawable")", isDirectory: true)
                        let fileURL = directory.appendingPathComponent(androidResourceName(baseName) + ".png")
                        do {
                            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                            try data.write(to: fileURL)
                            result.fileCount += 1
                        } catch {
                            result.errors.append("\(baseName) \(size.label)")
                        }
                    }
                } else {
                    let setDirectory = destination
                        .appendingPathComponent(platform.name.lowercased(), isDirectory: true)
                        .appendingPathComponent("\(baseName).imageset", isDirectory: true)
                    var entries: [[String: String]] = []
                    do {
                        try fileManager.createDirectory(at: setDirectory, withIntermediateDirectories: true)
                    } catch {
                        result.errors.append("\(baseName) \(platform.name)")
                        continue
                    }
                    for size in platform.sizes {
                        let dimensions = size.pixelSize(
                            sourceWidth: image.pixelWidth, sourceHeight: image.pixelHeight,
                            maxScale: platform.maxScale
                        )
                        let fileName = baseName + size.fileSuffix + ".png"
                        guard let data = resizedPNGData(from: image.url, width: dimensions.width, height: dimensions.height) else {
                            result.errors.append("\(baseName) \(size.label)")
                            continue
                        }
                        do {
                            try data.write(to: setDirectory.appendingPathComponent(fileName))
                            result.fileCount += 1
                            entries.append([
                                "idiom": "universal",
                                "filename": fileName,
                                "scale": "\(Int(size.scale))x",
                            ])
                        } catch {
                            result.errors.append("\(baseName) \(size.label)")
                        }
                    }
                    writeContentsJSON(images: entries, to: setDirectory)
                    result.imageSetCount += 1
                }
            }
        }
        return result
    }

    private static func writeContentsJSON(images: [[String: String]], to directory: URL) {
        let contents: [String: Any] = [
            "images": images,
            "info": ["version": 1, "author": "xcode"],
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: directory.appendingPathComponent("Contents.json"))
    }

    /// Sanitizes a name to a valid Android resource name: [a-z0-9_], not starting with a digit.
    static func androidResourceName(_ name: String) -> String {
        let mapped = name.lowercased().map { character -> Character in
            let isValid = (character.isASCII && (character.isLetter || character.isNumber)) || character == "_"
            return isValid ? character : "_"
        }
        var result = String(mapped)
        if let first = result.first, first.isNumber { result = "_" + result }
        return result.isEmpty ? "image" : result
    }
}
