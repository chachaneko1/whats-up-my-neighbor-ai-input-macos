import AppKit

/// The cat stays black in every state; transparent glyphs carry status.
enum NekoMenuBarIcon {
    enum State: CaseIterable { case idle, recording, processing, retry, relay }

    static func image(for state: State = .idle) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw(state: state)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(state: State) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.black.setFill()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: 4, y: 3))
        head.curve(to: NSPoint(x: 0.5, y: 7), controlPoint1: NSPoint(x: 1.7, y: 3), controlPoint2: NSPoint(x: 0.5, y: 4.4))
        head.curve(to: NSPoint(x: 1.2, y: 10), controlPoint1: NSPoint(x: 0.5, y: 8.2), controlPoint2: NSPoint(x: 0.8, y: 9.2))
        head.line(to: NSPoint(x: 2.9, y: 15.1))
        head.curve(to: NSPoint(x: 4.1, y: 15.3), controlPoint1: NSPoint(x: 3.1, y: 15.8), controlPoint2: NSPoint(x: 3.6, y: 15.9))
        head.line(to: NSPoint(x: 6.8, y: 11.5))
        head.line(to: NSPoint(x: 11.2, y: 11.5))
        head.line(to: NSPoint(x: 13.9, y: 15.3))
        head.curve(to: NSPoint(x: 15.1, y: 15.1), controlPoint1: NSPoint(x: 14.4, y: 15.9), controlPoint2: NSPoint(x: 14.9, y: 15.8))
        head.line(to: NSPoint(x: 16.8, y: 10))
        head.curve(to: NSPoint(x: 17.5, y: 7), controlPoint1: NSPoint(x: 17.2, y: 9.2), controlPoint2: NSPoint(x: 17.5, y: 8.2))
        head.curve(to: NSPoint(x: 14, y: 3), controlPoint1: NSPoint(x: 17.5, y: 4.4), controlPoint2: NSPoint(x: 16.3, y: 3))
        head.close()
        head.fill()

        // Cutouts remain transparent, so both light and dark menu bars work.
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setStroke()
        func stroke(_ points: [NSPoint], width: CGFloat = 1.35) {
            let line = NSBezierPath()
            line.lineWidth = width
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            line.move(to: points[0])
            for point in points.dropFirst() { line.line(to: point) }
            line.stroke()
        }
        func dot(_ x: CGFloat, _ y: CGFloat, diameter: CGFloat = 1.6) {
            NSBezierPath(ovalIn: NSRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)).fill()
        }
        switch state {
        case .idle, .relay:
            stroke([NSPoint(x: 3.6, y: 6), NSPoint(x: 6, y: 8.4)])
            stroke([NSPoint(x: 3.6, y: 8.4), NSPoint(x: 6, y: 6)])
            if state == .relay {
                stroke([NSPoint(x: 11.2, y: 7.2), NSPoint(x: 14.2, y: 7.2)])
                stroke([NSPoint(x: 12.7, y: 5.7), NSPoint(x: 12.7, y: 8.7)])
            } else {
                stroke([NSPoint(x: 11, y: 7.1), NSPoint(x: 12.3, y: 5.9), NSPoint(x: 14.6, y: 8.6)])
            }
        case .recording:
            for (x, height): (CGFloat, CGFloat) in [(5.5, 2.4), (9, 5), (12.5, 3.5)] {
                stroke([NSPoint(x: x, y: 7.2 - height / 2), NSPoint(x: x, y: 7.2 + height / 2)], width: 1.6)
            }
        case .processing:
            for x: CGFloat in [5.2, 9, 12.8] { dot(x, 7.1) }
        case .retry:
            stroke([NSPoint(x: 9, y: 7.3), NSPoint(x: 9, y: 9.5)], width: 1.6)
            dot(9, 5)
        }
    }
}
