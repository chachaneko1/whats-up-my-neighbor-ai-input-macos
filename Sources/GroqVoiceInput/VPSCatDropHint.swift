import AppKit

/// Preserves the 2026-10-26 DirectDropExperiment hint artwork and virtual geometry.
/// Only the coordinate adapter changes: the reference card becomes the real VPS window.
enum VPSCatDropHintGeometry {
    static let entry = CGRect(x: 455, y: 132, width: 185, height: 384)
    static let home = CGRect(x: 30, y: 180, width: 425, height: 365)

    static func screenRect(_ rect: CGRect, window: CGRect) -> CGRect {
        let scaleX = window.width / 580
        let scaleY = max(0, window.height - 60) / 381
        return CGRect(x: window.minX + (rect.minX - 500) * scaleX,
                      y: window.minY + 10 + (516 - rect.maxY) * scaleY,
                      width: rect.width * scaleX, height: rect.height * scaleY)
    }
}

private final class VPSCatDropHintPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class VPSCatDropHintView: NSView {
    enum Kind { case entry, home }
    var kind: Kind = .entry
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        // Copied from DirectDropExperiment/Sources/Main.swift, DropScene.draw.
        // Keep the accepted colors, opacity, radii, edge stroke, text and positions.
        if kind == .entry {
            NSColor.systemPink.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: VPSCatDropHintGeometry.entry, xRadius: 16, yRadius: 16).fill()
            NSColor.systemPink.withAlphaComponent(0.8).setStroke()
            let edge = NSBezierPath(); edge.lineWidth = 4
            edge.move(to: CGPoint(x: 501, y: 150)); edge.line(to: CGPoint(x: 501, y: 506)); edge.stroke()
            text("放開，貓咪就進去", at: CGPoint(x: 365, y: 285), color: .systemPink)
        } else {
            NSColor.systemTeal.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: VPSCatDropHintGeometry.home, xRadius: 18, yRadius: 18).fill()
            text("放開，回到本機", at: CGPoint(x: 170, y: 215), color: .systemTeal)
        }
    }

    private func text(_ value: String, at point: CGPoint, color: NSColor) {
        (value as NSString).draw(at: point, withAttributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: color
        ])
    }
}

/// A mouse-transparent hint surface, never another cat or VNC viewer.
@MainActor final class VPSCatDropHintController {
    private let view = VPSCatDropHintView()
    private let panel = VPSCatDropHintPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                           backing: .buffered, defer: false)

    init() {
        panel.title = "貓咪拖放提示"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = view
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.staticText)
    }

    func show(_ kind: VPSCatDropHintView.Kind, beside host: NSWindow) {
        let virtual = kind == .entry
            ? CGRect(x: 365, y: 132, width: 275, height: 384)
            : VPSCatDropHintGeometry.home
        let frame = VPSCatDropHintGeometry.screenRect(virtual, window: host.frame)
        view.kind = kind
        panel.setFrame(frame, display: false)
        view.frame = CGRect(origin: .zero, size: frame.size)
        view.bounds = virtual
        view.setAccessibilityLabel(kind == .entry ? "放開，貓咪就進去" : "放開，回到本機")
        view.needsDisplay = true
        // Insert immediately above the host, beneath the already-raised dragged cat.
        panel.order(.above, relativeTo: host.windowNumber)
    }

    func hide() { panel.orderOut(nil) }
}
