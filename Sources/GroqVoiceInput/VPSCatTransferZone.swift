import CoreGraphics

/// Screen-coordinate hit region for the existing VPS window's desktop area.
struct VPSCatTransferZone {
    static func accepts(_ point: CGPoint, window: CGRect, connected: Bool,
                        collapsed: Bool, visible: Bool) -> Bool {
        guard connected, !collapsed, visible, window.width >= 220, window.height >= 120 else { return false }
        let desktop = CGRect(x: window.minX + 12, y: window.minY + 10,
                             width: window.width - 24, height: window.height - 60)
        // Highlight and acceptance share the same forgiving edge zone.
        return desktop.insetBy(dx: -24, dy: -24).contains(point)
    }

    static func hasExited(_ point: CGPoint, window: CGRect) -> Bool {
        !window.contains(point)
    }
}
