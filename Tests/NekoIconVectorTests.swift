import AppKit
import Foundation

@main
enum NekoIconVectorTests {
    static func require(_ condition: Bool, _ message: String) {
        if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }

    static func render(_ image: NSImage, width: Int, height: Int) -> NSBitmapImageRep {
        let size = NSSize(width: width, height: height)
        let canvas = NSImage(size: size, flipped: true) { _ in
            image.draw(in: NSRect(origin: .zero, size: size), from: .zero,
                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
        let bitmap = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
        require(bitmap.pixelsWide == width && bitmap.pixelsHigh == height, "requested native render resolution")
        return bitmap
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = root.appendingPathComponent("build/vector-proof")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let source = try String(contentsOf: root.appendingPathComponent("Resources/DesktopPet/walk-front-face.svg"), encoding: .utf8)
        let vector = try String(contentsOf: root.appendingPathComponent("Resources/AppIcon.svg"), encoding: .utf8)
        require(!vector.contains("<image") && !vector.contains("data:image") && !vector.contains("<foreignObject"), "SVG contains vector geometry, not an embedded bitmap")
        let pattern = try NSRegularExpression(pattern: "<path[^>]+/>")
        let paths = pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).map { String(source[Range($0.range, in: source)!]) }
        require(paths.count == 4 && paths.allSatisfy(vector.contains), "all four approved paths remain unchanged")
        let appImage = NSImage(data: Data(vector.utf8))!
        let large = render(appImage, width: 4096, height: 4096)
        try large.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("app-vector-4096.png"))
        if let detail = large.cgImage?.cropping(to: CGRect(x: 800, y: 1040, width: 700, height: 600)) {
            try NSBitmapImageRep(cgImage: detail).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("app-vector-detail.png"))
        }

        let reference = render(NSImage(data: Data(vector.utf8))!, width: 1024, height: 1024)
        let installed = NSBitmapImageRep(data: try Data(contentsOf: root.appendingPathComponent("Resources/AppIcon-source.png")))!
        var difference = 0.0, count = 0
        // Compare opaque geometry; the native ICNS generator supplies the shadow.
        for y in stride(from: 120, to: 904, by: 2) {
            for x in stride(from: 120, to: 904, by: 2) {
                let a = reference.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                let b = installed.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                if a.alphaComponent > 0.999 && b.alphaComponent > 0.999 {
                    difference += Double(abs(a.redComponent-b.redComponent) + abs(a.greenComponent-b.greenComponent) + abs(a.blueComponent-b.blueComponent)) / 3
                    count += 1
                }
            }
        }
        let appError = difference / Double(count)
        require(appError < 0.005, "portable SVG matches packaged app geometry")

        func artwork(_ paths: [String]) -> NSImage {
            NSImage(data: Data(("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"325\" height=\"218\" viewBox=\"20 12 325 218\" fill=\"none\">" + paths.joined() + "</svg>").utf8))!
        }
        let original = NSImage(size: NSSize(width: 24, height: 18), flipped: true) { _ in
            let rect = NSRect(x: 0, y: (18-24*218/325)/2, width: 24, height: 24*218/325)
            artwork([paths[0]]).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            artwork(Array(paths.dropFirst())).draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
        let expected = render(original, width: 1200, height: 900)
        let menu = render(NekoMenuBarIcon.image(), width: 1200, height: 900)
        try menu.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("menu-native-1200.png"))
        var alphaDifference = 0.0
        for y in stride(from: 0, to: 900, by: 2) {
            for x in stride(from: 0, to: 1200, by: 2) {
                alphaDifference += abs(Double(expected.colorAt(x: x, y: y)!.alphaComponent-menu.colorAt(x: x, y: y)!.alphaComponent))
            }
        }
        let menuError = alphaDifference / Double(600*450)
        // Independent SVG and AppKit renderers antialias boundary pixels differently.
        require(menuError < 0.01, "50x native menu render matches the SVG curves")
        let result: [String: Any] = ["svg_has_embedded_bitmap": false, "approved_paths_unchanged": true,
            "app_vector_render_pixels": 4096, "app_geometry_mean_channel_error": appError,
            "menu_render_pixels": [1200,900], "menu_svg_mean_alpha_error": menuError,
            "icns_maximum_pixels": 1024, "portable_svg_omits_native_outer_shadow": true]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("verification.json"))
        print("Vector checks passed: no embedded bitmap; unchanged SVG paths; 4096 px app render; 50x native menu match. ICNS remains limited to its 1024 px representation.")
        print("Geometry error: app \(appError), menu \(menuError).")
    }
}
