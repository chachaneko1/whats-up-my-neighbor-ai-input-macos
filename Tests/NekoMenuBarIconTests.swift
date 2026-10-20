import AppKit
import Foundation

@main
enum NekoMenuBarIconTests {
    static func require(_ condition: Bool, _ message: String) {
        if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }

    static func raster(_ image: NSImage, scale: Int = 10) -> NSBitmapImageRep {
        let size = NSSize(width: image.size.width * CGFloat(scale), height: image.size.height * CGFloat(scale))
        let canvas = NSImage(size: size, flipped: true) { _ in
            image.draw(in: NSRect(origin: .zero, size: size), from: .zero,
                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
        return NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = root.appendingPathComponent("build/icon-render")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let svg = try String(contentsOf: root.appendingPathComponent("Resources/DesktopPet/walk-front-face.svg"), encoding: .utf8)
        let matches = try NSRegularExpression(pattern: "<path[^>]+/>").matches(in: svg, range: NSRange(svg.startIndex..., in: svg))
        let paths = matches.map { String(svg[Range($0.range, in: svg)!]) }
        func artwork(_ parts: [String]) -> NSImage {
            let text = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"325\" height=\"218\" viewBox=\"20 12 325 218\" fill=\"none\">" + parts.joined() + "</svg>"
            return NSImage(data: Data(text.utf8))!
        }
        let reference = NSImage(size: NSSize(width: 24, height: 18), flipped: true) { _ in
            let rect = NSRect(x: 0, y: (18 - 24 * 218 / 325) / 2, width: 24, height: 24 * 218 / 325)
            artwork([paths[0]]).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            artwork(Array(paths.dropFirst())).draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
        let expected = raster(reference)
        var statePNGs = Set<Data>()
        for state in NekoMenuBarIcon.State.allCases {
            let image = NekoMenuBarIcon.image(for: state)
            require(image.size == NSSize(width: 24, height: 18), "menu fits a 24 × 18 pt status item")
            require(!image.isTemplate, "approved black cat does not become a solid template")
            let bitmap = raster(image)
            var coverage = 0
            var alphaDifference = 0.0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let pixel = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    if pixel.alphaComponent > 0.9 {
                        coverage += 1
                        require(max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.12, "state glyphs are transparent, not white paint")
                    }
                    if state == .idle {
                        alphaDifference += abs(Double(pixel.alphaComponent - expected.colorAt(x: x, y: y)!.alphaComponent))
                    }
                }
            }
            require(coverage > bitmap.pixelsWide * bitmap.pixelsHigh / 3, "cat silhouette is present")
            require(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0, "menu corners remain transparent")
            if state == .idle {
                require(alphaDifference / Double(bitmap.pixelsWide * bitmap.pixelsHigh) < 0.02, "idle face matches the approved SVG geometry and expression")
            }
            let png = bitmap.representation(using: .png, properties: [:])!
            statePNGs.insert(png)
            try png.write(to: output.appendingPathComponent("menu-\(state).png"))
            for scale in [1, 2] {
                let small = raster(image, scale: scale)
                try small.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("menu-\(state)-\(scale)x.png"))
            }
        }
        require(statePNGs.count == NekoMenuBarIcon.State.allCases.count, "all five statuses remain distinct")
        let icon = NSBitmapImageRep(data: try Data(contentsOf: root.appendingPathComponent("Resources/AppIcon-source.png")))!
        require(icon.pixelsWide == 1024 && icon.pixelsHigh == 1024, "app master is 1024 px")
        for (x, y) in [(512, 120), (120, 512), (900, 512)] {
            let p = icon.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            require(p.alphaComponent == 1 && min(p.redComponent, p.greenComponent, p.blueComponent) > 0.999, "app tile stays pure white")
        }
        print("Icon rendering checks passed: approved SVG match, pure-white app tile, transparent menu glyphs, five distinct statuses, 1x/2x renders.")
    }
}
