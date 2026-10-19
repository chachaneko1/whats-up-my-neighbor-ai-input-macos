import AppKit

/// Compare identical application poses; no source artwork is changed.
@main enum TabbyReview {
    static func main() throws {
        let before = NSImage(contentsOfFile: CommandLine.arguments[1])!
        let after = NSImage(contentsOfFile: CommandLine.arguments[2])!
        let size = NSSize(width: 1000, height: 490)
        let comparison = NSImage(size: size, flipped: true) { _ in
            NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            for (i, entry) in [(before, "調整前"), (after, "調整後")].enumerated() {
                let cg = entry.0.cgImage(forProposedRect: nil, context: nil, hints: nil)!
                let pose = NSImage(cgImage: cg.cropping(to: CGRect(x: 0, y: 28, width: 240, height: 195))!,
                                   size: NSSize(width: 240, height: 195))
                let x = CGFloat(i) * 500
                (entry.1 as NSString).draw(at: CGPoint(x: x + 208, y: 25),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 23), .foregroundColor: NSColor.labelColor])
                pose.draw(in: CGRect(x: x + 10, y: 60, width: 480, height: 390), from: .zero,
                    operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
            return true
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        try NSBitmapImageRep(data: comparison.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: output)
    }
}
