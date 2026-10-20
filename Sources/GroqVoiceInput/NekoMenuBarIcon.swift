import AppKit

/// The approved round-face artwork, with transparent status glyphs.
enum NekoMenuBarIcon {
    enum State: CaseIterable { case idle, recording, processing, retry, relay }

    static func image(for state: State = .idle) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 18), flipped: true) { _ in
            draw(state: state)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(state: State) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Same 325 × 218 crop and unmodified paths as walk-front-face.svg.
        let scale: CGFloat = 24 / 325
        let transform = NSAffineTransform()
        transform.translateX(by: -20 * scale, yBy: (18 - 218 * scale) / 2 - 12 * scale)
        transform.scale(by: scale)
        transform.concat()

        NSColor(srgbRed: 16 / 255, green: 17 / 255, blue: 20 / 255, alpha: 1).setFill()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: 28, y: 132.103))
        head.curve(to: NSPoint(x: 59, y: 68.7), controlPoint1: NSPoint(x: 31, y: 110.365), controlPoint2: NSPoint(x: 41, y: 87.721))
        head.line(to: NSPoint(x: 75, y: 27.0351))
        head.curve(to: NSPoint(x: 97, y: 26.1293), controlPoint1: NSPoint(x: 80, y: 17.9775), controlPoint2: NSPoint(x: 88, y: 17.9775))
        head.line(to: NSPoint(x: 135, y: 65.9828))
        head.curve(to: NSPoint(x: 226, y: 65.9828), controlPoint1: NSPoint(x: 164, y: 63.2655), controlPoint2: NSPoint(x: 196, y: 63.2655))
        head.line(to: NSPoint(x: 263, y: 27.0351))
        head.curve(to: NSPoint(x: 286, y: 27.9408), controlPoint1: NSPoint(x: 273, y: 17.0717), controlPoint2: NSPoint(x: 281, y: 17.9775))
        head.line(to: NSPoint(x: 304, y: 71.4173))
        head.curve(to: NSPoint(x: 333, y: 136.632), controlPoint1: NSPoint(x: 324, y: 93.1556), controlPoint2: NSPoint(x: 331, y: 112.177))
        head.curve(to: NSPoint(x: 286, y: 214.527), controlPoint1: NSPoint(x: 339, y: 181.92), controlPoint2: NSPoint(x: 322, y: 208.187))
        head.curve(to: NSPoint(x: 76, y: 214.527), controlPoint1: NSPoint(x: 232, y: 224.491), controlPoint2: NSPoint(x: 131, y: 224.491))
        head.curve(to: NSPoint(x: 28, y: 132.103), controlPoint1: NSPoint(x: 38, y: 208.187), controlPoint2: NSPoint(x: 19, y: 181.014))
        head.close()
        head.fill()

        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setStroke()
        NSColor.black.setFill()
        func stroke(_ points: [NSPoint], width: CGFloat = 14) {
            let line = NSBezierPath()
            line.lineWidth = width
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            line.move(to: points[0])
            for point in points.dropFirst() { line.line(to: point) }
            line.stroke()
        }
        func dot(_ x: CGFloat, _ y: CGFloat, diameter: CGFloat = 20) {
            NSBezierPath(ovalIn: NSRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)).fill()
        }
        switch state {
        case .idle, .relay:
            stroke([NSPoint(x: 80, y: 147), NSPoint(x: 108, y: 175)], width: 13)
            stroke([NSPoint(x: 108, y: 147), NSPoint(x: 80, y: 175)], width: 13)
            if state == .relay {
                stroke([NSPoint(x: 246, y: 161), NSPoint(x: 282, y: 161)])
                stroke([NSPoint(x: 264, y: 143), NSPoint(x: 264, y: 179)])
            } else {
                stroke([NSPoint(x: 247, y: 162), NSPoint(x: 259, y: 174), NSPoint(x: 286, y: 145)])
            }
            let mouth = NSBezierPath()
            mouth.move(to: NSPoint(x: 163, y: 187))
            mouth.curve(to: NSPoint(x: 181, y: 187), controlPoint1: NSPoint(x: 164, y: 199), controlPoint2: NSPoint(x: 177, y: 199))
            mouth.curve(to: NSPoint(x: 199, y: 187), controlPoint1: NSPoint(x: 184, y: 199), controlPoint2: NSPoint(x: 198, y: 199))
            mouth.lineWidth = 7
            mouth.lineCapStyle = .round
            mouth.stroke()
        case .recording:
            for (x, height): (CGFloat, CGFloat) in [(110, 30), (180, 65), (250, 45)] {
                stroke([NSPoint(x: x, y: 161 - height / 2), NSPoint(x: x, y: 161 + height / 2)], width: 18)
            }
        case .processing:
            for x: CGFloat in [110, 180, 250] { dot(x, 161) }
        case .retry:
            stroke([NSPoint(x: 180, y: 138), NSPoint(x: 180, y: 169)], width: 18)
            dot(180, 193)
        }
    }
}
