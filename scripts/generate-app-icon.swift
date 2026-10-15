import AppKit
import Foundation

// Repackage the existing cat artwork without stretching it or introducing a new logo.
// Usage: swift scripts/generate-app-icon.swift /path/to/Resources
enum IconBuildError: Error {
    case invalidArguments
    case missingArtwork
    case renderFailed(Int)
    case iconutilFailed(Int32)
}

guard CommandLine.arguments.count == 2 else { throw IconBuildError.invalidArguments }
let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard let artwork = NSImage(contentsOf: resources.appendingPathComponent("neko-base.png")),
      artwork.size.width > 0, artwork.size.height > 0 else {
    throw IconBuildError.missingArtwork
}

let temporary = FileManager.default.temporaryDirectory
    .appendingPathComponent("neighbor-icon-\(UUID().uuidString)", isDirectory: true)
let iconset = temporary.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func png(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconBuildError.renderFailed(size)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    context.imageInterpolation = .high
    let canvas = CGFloat(size)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill(using: .copy)
    let scale = canvas * 0.94 / max(artwork.size.width, artwork.size.height)
    let width = artwork.size.width * scale
    let height = artwork.size.height * scale
    artwork.draw(
        in: NSRect(x: (canvas - width) / 2, y: (canvas - height) / 2, width: width, height: height),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    context.flushGraphics()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconBuildError.renderFailed(size)
    }
    return data
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(points)x\(points)\(suffix).png"
        try png(size: points * scale).write(to: iconset.appendingPathComponent(filename))
    }
}

let generatedIcon = temporary.appendingPathComponent("AppIcon.icns")
let converter = Process()
converter.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
converter.arguments = ["-c", "icns", iconset.path, "-o", generatedIcon.path]
try converter.run()
converter.waitUntilExit()
guard converter.terminationStatus == 0 else {
    throw IconBuildError.iconutilFailed(converter.terminationStatus)
}

// Atomic writes leave the previously packaged icon intact if rendering fails.
try Data(contentsOf: generatedIcon).write(to: resources.appendingPathComponent("AppIcon.icns"), options: .atomic)
try Data(contentsOf: iconset.appendingPathComponent("icon_512x512@2x.png"))
    .write(to: resources.appendingPathComponent("AppIcon-source.png"), options: .atomic)
print("Packaged the black cat app icon (16–1024 px).")
