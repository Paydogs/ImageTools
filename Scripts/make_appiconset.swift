#!/usr/bin/env swift
import AppKit
import Foundation

// Renders an SF Symbol into a macOS AppIcon.appiconset (PNGs + Contents.json).
// Usage: swift make_appiconset.swift <output .appiconset dir> [symbolName]

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("Usage: make_appiconset.swift <appiconset dir> [symbolName]\n".utf8))
    exit(1)
}
let outputDir = args[1]
let symbolName = args.count >= 3 ? args[2] : "photo.tv"

let fm = FileManager.default
try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

/// Draws the SF Symbol into its own transparent image tinted with `color`,
/// so the tint applies only to the glyph (not a surrounding rectangle).
func tintedSymbol(pointSize: CGFloat, color: NSColor) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
          let symbol = base.withSymbolConfiguration(config) else { return nil }
    let size = symbol.size
    let image = NSImage(size: size)
    image.lockFocus()
    symbol.draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: 1)
    color.set()
    NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
    image.unlockFocus()
    return image
}

func renderPNG(pixelSize: Int) -> Data {
    let s = CGFloat(pixelSize)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("Could not create bitmap rep") }
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded-rect background matching the macOS icon grid (824/1024 side, ~185/1024 radius).
    let side = s * 0.8047
    let origin = (s - side) / 2
    let bgRect = NSRect(x: origin, y: origin, width: side, height: side)
    let radius = s * 0.1807
    let path = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.32, blue: 0.85, alpha: 1),
    ])!
    gradient.draw(in: path, angle: -90)

    // White symbol centered, ~50% of the canvas.
    if let symbol = tintedSymbol(pointSize: s * 0.42, color: .white) {
        let symSize = symbol.size
        let symRect = NSRect(
            x: (s - symSize.width) / 2, y: (s - symSize.height) / 2,
            width: symSize.width, height: symSize.height
        )
        symbol.draw(in: symRect, from: NSRect(origin: .zero, size: symSize), operation: .sourceOver, fraction: 1)
    } else {
        FileHandle.standardError.write(Data("Could not load SF Symbol: \(symbolName)\n".utf8))
        exit(1)
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG")
    }
    return data
}

struct Entry { let size: Int; let scale: Int }
let entries = [
    Entry(size: 16, scale: 1), Entry(size: 16, scale: 2),
    Entry(size: 32, scale: 1), Entry(size: 32, scale: 2),
    Entry(size: 128, scale: 1), Entry(size: 128, scale: 2),
    Entry(size: 256, scale: 1), Entry(size: 256, scale: 2),
    Entry(size: 512, scale: 1), Entry(size: 512, scale: 2),
]

var images: [[String: String]] = []
for e in entries {
    let pixels = e.size * e.scale
    let suffix = e.scale == 2 ? "@2x" : ""
    let filename = "icon_\(e.size)x\(e.size)\(suffix).png"
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(filename)
    try renderPNG(pixelSize: pixels).write(to: url)
    images.append([
        "size": "\(e.size)x\(e.size)",
        "idiom": "mac",
        "filename": filename,
        "scale": "\(e.scale)x",
    ])
    print("wrote \(filename) (\(pixels)px)")
}

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "xcode"],
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: outputDir).appendingPathComponent("Contents.json"))
print("wrote Contents.json")
