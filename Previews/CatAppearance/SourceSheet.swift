import AppKit

@main enum SourceSheet {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let image = NSImage(size: NSSize(width: 1440, height: 1260), flipped: true) { _ in
            NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1440, height: 1260)).fill()
            for i in 0..<36 {
                let x = CGFloat(i % 6) * 240, y = CGFloat(i / 6) * 210
                let source = NSImage(contentsOf: root.appendingPathComponent(String(format: "%02d.png", i)))!
                source.draw(in: NSRect(x: x, y: y, width: 216, height: 199.4), from: .zero, operation: .sourceOver,
                            fraction: 1, respectFlipped: true, hints: nil)
                (String(format: "%02d", i) as NSString).draw(at: NSPoint(x: x + 10, y: y + 8), withAttributes: [.font: NSFont.systemFont(ofSize: 16)])
            }
            return true
        }
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
