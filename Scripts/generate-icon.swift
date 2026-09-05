import AppKit
import Darwin
import Foundation

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "")
let fileManager = FileManager.default

func drawIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "NodeBarIcon", code: 1)
    }

    NSGraphicsContext.current = context
    let size = CGFloat(pixels)
    let cg = context.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: size, height: size))

    cg.setFillColor(NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.16, alpha: 1).cgColor)
    cg.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerWidth: size * 0.2, cornerHeight: size * 0.2, transform: nil))
    cg.fillPath()

    let inset = size * 0.20
    let rackWidth = size - (inset * 2)
    let rackHeight = max(2, size * 0.10)
    let rackGap = max(3, size * 0.12)
    cg.setFillColor(NSColor(calibratedRed: 0.22, green: 0.78, blue: 0.92, alpha: 1).cgColor)
    for row in 0..<3 {
        let y = inset + CGFloat(row) * (rackHeight + rackGap)
        cg.addPath(CGPath(roundedRect: CGRect(x: inset, y: y, width: rackWidth, height: rackHeight), cornerWidth: rackHeight / 2, cornerHeight: rackHeight / 2, transform: nil))
        cg.fillPath()
        cg.setFillColor(NSColor(calibratedRed: 0.95, green: 0.82, blue: 0.32, alpha: 1).cgColor)
        cg.fillEllipse(in: CGRect(x: size - inset - rackHeight * 2.2, y: y + rackHeight * 0.18, width: rackHeight * 0.64, height: rackHeight * 0.64))
        cg.setFillColor(NSColor(calibratedRed: 0.22, green: 0.78, blue: 0.92, alpha: 1).cgColor)
    }

    guard let data = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
        throw NSError(domain: "NodeBarIcon", code: 2)
    }
    return data
}

func generate() throws {
    guard CommandLine.arguments.count > 1 else {
        throw NSError(domain: "NodeBarIcon", code: 3)
    }
    try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    let images: [(String, Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]
    for (name, pixels) in images {
        try drawIcon(pixels: pixels).write(to: iconsetURL.appendingPathComponent(name))
    }
}

do {
    try generate()
} catch {
    fputs("NodeBar icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
