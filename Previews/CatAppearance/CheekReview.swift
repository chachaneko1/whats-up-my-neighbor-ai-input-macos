import AppKit

@main enum CheekReview {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let maps = CatAnatomy.pickupMaps(at: root.appendingPathComponent("Resources/DesktopPet/Pickup/anatomy.json"))!
        let source = NSImage(contentsOf: root.appendingPathComponent("Resources/DesktopPet/Pickup/00.png"))!
        let painter = CatAppearanceArtwork(CatAppearance.makePreset("calico")!)
        let colored = painter.image(source, layout: .pickup(maps[0]))!
        let cg = colored.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let cropped = NSImage(cgImage: cg.cropping(to: CGRect(x: 120, y: 45, width: 180, height: 128))!, size: NSSize(width: 180, height: 128))
        let image = NSImage(size: NSSize(width: 1080, height: 768), flipped: true) { _ in
            NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: 1080, height: 768)).fill()
            cropped.draw(in: CGRect(x: 0, y: 0, width: 1080, height: 768), from: .zero,
                operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
            return true
        }
        try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: output)
        if CommandLine.arguments.count > 3, let before = NSImage(contentsOfFile: CommandLine.arguments[3]) {
            let comparison = NSImage(size: NSSize(width: 1080, height: 430), flipped: true) { _ in
                NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: 1080, height: 430)).fill()
                for (i, entry) in [(before, "修正前：臉頰外緣白縫"), (image, "修正後")].enumerated() {
                    let x = CGFloat(i) * 540
                    (entry.1 as NSString).draw(at: CGPoint(x: x + 20, y: 12), withAttributes: [.font: NSFont.systemFont(ofSize: 20)])
                    entry.0.draw(in: CGRect(x: x + 15, y: 50, width: 510, height: 363), from: .zero,
                        operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
                }
                return true
            }
            try NSBitmapImageRep(data: comparison.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                .write(to: output.deletingLastPathComponent().appendingPathComponent("cheek-comparison.png"))
        }
    }
}
