import Foundation

/// One required output size within a platform's imageset (a scale factor relative to 1x).
struct AssetSize: Identifiable {
    let id = UUID()
    let label: String       // "@1x", "@2x", "@3x", "mdpi", …
    let scale: Double        // relative to 1x (mdpi)
    let folder: String?      // Android density folder (nil for Apple imagesets)
    let fileSuffix: String   // Apple filename suffix ("", "@2x", "@3x")

    /// Target pixel dimensions given the source treated as the platform's largest scale.
    func pixelSize(sourceWidth: Int, sourceHeight: Int, maxScale: Double) -> (width: Int, height: Int) {
        let factor = scale / maxScale
        return (
            max(1, Int((Double(sourceWidth) * factor).rounded())),
            max(1, Int((Double(sourceHeight) * factor).rounded()))
        )
    }
}

/// A platform and the full set of imageset sizes it requires.
struct AssetPlatform: Identifiable {
    let id = UUID()
    let name: String
    let systemImage: String
    let maxScale: Double
    let sizes: [AssetSize]
}

enum AssetCatalog {
    static let platforms: [AssetPlatform] = [
        AssetPlatform(name: "iOS", systemImage: "iphone", maxScale: 3, sizes: [
            AssetSize(label: "@1x", scale: 1, folder: nil, fileSuffix: ""),
            AssetSize(label: "@2x", scale: 2, folder: nil, fileSuffix: "@2x"),
            AssetSize(label: "@3x", scale: 3, folder: nil, fileSuffix: "@3x"),
        ]),
        AssetPlatform(name: "macOS", systemImage: "macbook", maxScale: 2, sizes: [
            AssetSize(label: "@1x", scale: 1, folder: nil, fileSuffix: ""),
            AssetSize(label: "@2x", scale: 2, folder: nil, fileSuffix: "@2x"),
        ]),
        AssetPlatform(name: "Android", systemImage: "square.grid.2x2", maxScale: 4, sizes: [
            AssetSize(label: "mdpi", scale: 1, folder: "drawable-mdpi", fileSuffix: ""),
            AssetSize(label: "hdpi", scale: 1.5, folder: "drawable-hdpi", fileSuffix: ""),
            AssetSize(label: "xhdpi", scale: 2, folder: "drawable-xhdpi", fileSuffix: ""),
            AssetSize(label: "xxhdpi", scale: 3, folder: "drawable-xxhdpi", fileSuffix: ""),
            AssetSize(label: "xxxhdpi", scale: 4, folder: "drawable-xxxhdpi", fileSuffix: ""),
        ]),
    ]
}
