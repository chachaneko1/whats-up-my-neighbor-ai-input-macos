import AppKit
import SwiftUI

/// Floating VPS desktop opened from the cat menu; it never adds a second status item.
/// Closing or collapsing keeps the connection; only 中斷 or quitting the app ends it.
@MainActor final class VPSDesktopWindowController {
    private let connection = VPSDesktopConnection()
    private let panel = VPSDesktopPanel()
    private let window: NSWindow
    private let minimumSize = NSSize(width: 400, height: 330)
    // 48pt title bar plus a 450-wide view of the VPS's 1440×900 desktop.
    private var expandedSize = NSSize(width: 450, height: 330)
    private var hasConnected = false

    init() {
        window = VPSDesktopWindow(contentRect: NSRect(origin: .zero, size: expandedSize), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "VPS 遠端桌面"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .white
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentMinSize = minimumSize
        window.hasShadow = true
        window.tabbingMode = .disallowed
        window.contentView = NSHostingView(rootView: VPSDesktopView(panel: panel, connection: connection))
        panel.toggle = { [weak self] in self?.toggleCollapsed() }
        placeTopRight()
    }

    func present() {
        if panel.collapsed { toggleCollapsed() }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Connect once on first open; after a disconnect the user chooses when to retry.
        if !hasConnected {
            hasConnected = true
            connection.connect()
        }
    }

    func shutdown() { connection.disconnect() }

    private func placeTopRight() {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let width = min(expandedSize.width, visible.width - 48)
        window.setFrame(NSRect(x: visible.maxX - width - 24, y: visible.maxY - expandedSize.height - 22, width: width, height: expandedSize.height), display: true)
    }

    private func toggleCollapsed() {
        let collapsing = !panel.collapsed
        if collapsing { expandedSize = window.frame.size }
        panel.collapsed = collapsing
        let old = window.frame
        window.contentMinSize = collapsing ? NSSize(width: 320, height: 48) : minimumSize
        let size = collapsing ? NSSize(width: 340, height: 48) : expandedSize
        window.setFrame(NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height), display: true)
        if collapsing { window.styleMask.remove(.resizable) } else { window.styleMask.insert(.resizable) }
    }
}

/// The app has no Edit menu, so route the standard editing shortcuts here (e.g. pasting the VNC password).
private final class VPSDesktopWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let actions: [String: Selector] = [
            "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
            "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
            "w": #selector(NSWindow.performClose(_:)),
        ]
        if let action = actions[key], NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
