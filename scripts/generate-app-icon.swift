import AppKit
import Foundation

// Run from any directory: swift /path/to/scripts/generate-app-icon.swift
// Selected proposal A: pure white tile and the approved original round face.
// Keep neko-base.png as the separate recording HUD artwork.
enum IconBuildError: Error {
    case invalidArtwork
    case renderFailed(Int)
    case iconutilFailed(Int32)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let source = resources.appendingPathComponent("DesktopPet/walk-front-face.svg")
let original = try String(contentsOf: source, encoding: .utf8)
guard let headerEnd = original.firstIndex(of: ">") else { throw IconBuildError.invalidArtwork }
// Trim the unused 400x400 body canvas, keeping every original path intact.
let cropped = """
<svg xmlns="http://www.w3.org/2000/svg" width="325" height="218" viewBox="20 12 325 218" fill="none">
""" + original[original.index(after: headerEnd)...]
guard let artwork = NSImage(data: Data(cropped.utf8)) else { throw IconBuildError.invalidArtwork }

let temporary = root.appendingPathComponent("build", isDirectory: true)
    .appendingPathComponent("neighbor-icon-\(UUID().uuidString)", isDirectory: true)
let iconset = temporary.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func png(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
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
    // Match proposal A: 6% outer margin, 22.5% corner radius, and a 6.5%
    // inner inset around the original face canvas. The remaining margin
    // contains the soft shadow without clipping at any icon resolution.
    let tile = NSRect(x: canvas * 0.06, y: canvas * 0.06,
                      width: canvas * 0.88, height: canvas * 0.88)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
    shadow.shadowBlurRadius = tile.width * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -tile.width * 0.012)
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225,
                 yRadius: tile.height * 0.225).fill()
    NSGraphicsContext.restoreGraphicsState()
    let faceCanvas = tile.insetBy(dx: tile.width * 0.065, dy: tile.height * 0.065)
    let width = faceCanvas.width * 0.94
    let height = width * 218 / 325
    artwork.draw(in: NSRect(x: (canvas - width) / 2, y: (canvas - height) / 2,
                           width: width, height: height),
                 from: .zero, operation: .sourceOver, fraction: 1)
    context.flushGraphics()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconBuildError.renderFailed(size)
    }
    return data
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try png(size: points * scale).write(
            to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
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
try Data(contentsOf: generatedIcon).write(to: resources.appendingPathComponent("AppIcon.icns"), options: .atomic)
try Data(contentsOf: iconset.appendingPathComponent("icon_512x512@2x.png"))
    .write(to: resources.appendingPathComponent("AppIcon-source.png"), options: .atomic)
print("Packaged selected A: pure white tile with the original round cat face (16–1024 px).")
