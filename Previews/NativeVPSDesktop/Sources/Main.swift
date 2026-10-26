import AppKit
import SwiftUI

@main enum NativePreviewMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = PreviewDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
@MainActor final class PreviewDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = PreviewState()
    let connection = RemoteConnection()
    var chat: NSWindow!
    var remote: NSWindow!
    var statusItem: NSStatusItem!
    var chatExpandedSize = NSSize(width: 470, height: 600)
    var remoteExpandedSize = NSSize(width: 450, height: 360)
    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        chat = makeWindow(title: "小貓聊天 · 原生 Preview", size: NSSize(width: 470, height: 600), minimum: NSSize(width: 400, height: 460))
        remote = makeWindow(title: "VPS 遠端工作區 · Preview", size: NSSize(width: 450, height: 360), minimum: NSSize(width: 400, height: 330))
        chat.contentView = NSHostingView(rootView: ChatView(state: state))
        remote.contentView = NSHostingView(rootView: RemoteView(state: state, connection: connection))
        state.showRemote = { [weak self] in self?.showRemote() }
        state.toggleChat = { [weak self] in self?.toggleChat() }
        state.toggleRemote = { [weak self] in self?.toggleRemote() }
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        if let button = statusItem.button {
            button.image = NekoMenuBarIcon.image()
            button.toolTip = "Neko 桌面 Preview：點一下展開，右鍵選單"
            button.setAccessibilityLabel("Neko 桌面 Preview")
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        resetPositions()
        remote.orderFrontRegardless()
        chat.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        connection.connect()
    }
    func makeWindow(title: String, size: NSSize, minimum: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .white
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentMinSize = minimum
        window.delegate = self
        window.hasShadow = true
        window.tabbingMode = .disallowed
        return window
    }
    @objc func resetPositions() {
        guard let screen = chat?.screen ?? NSScreen.main else { return }
        if state.chatCollapsed { toggleChat() }
        if state.remoteCollapsed { toggleRemote() }
        let visible = screen.visibleFrame
        let cw = min(470, visible.width - 48)
        let ch = min(600, visible.height - 48)
        chat.setFrame(NSRect(x: visible.minX + 36, y: visible.minY + 26, width: cw, height: ch), display: true)
        let rw = min(450, visible.width - 48)
        remote.setFrame(NSRect(x: visible.maxX - rw - 24, y: visible.maxY - 360 - 22, width: rw, height: 360), display: true)
    }
    @objc func showBoth() {
        if state.chatCollapsed { toggleChat() }
        if state.remoteCollapsed { toggleRemote() }
        chat.deminiaturize(nil); remote.deminiaturize(nil)
        remote.orderFrontRegardless(); chat.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showRemote() {
        if state.remoteCollapsed { toggleRemote() }
        remote.deminiaturize(nil); remote.makeKeyAndOrderFront(nil)
    }
    @objc func hideBoth() { chat.orderOut(nil); remote.orderOut(nil) }
    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            for (title, selector) in [("展開聊天與 VPS 視窗", #selector(showBoth)), ("隱藏兩個視窗", #selector(hideBoth)), ("恢復桌面位置", #selector(resetPositions))] {
                let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: ""); item.target = self
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "結束 Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
        } else { showBoth() }
    }
    func toggleChat() {
        let collapsing = !state.chatCollapsed
        if collapsing { chatExpandedSize = chat.frame.size }
        state.chatCollapsed = collapsing
        resizePanel(chat, collapsed: collapsing, expanded: chatExpandedSize, minimum: NSSize(width: 400, height: 460))
    }
    func toggleRemote() {
        let collapsing = !state.remoteCollapsed
        if collapsing { remoteExpandedSize = remote.frame.size }
        state.remoteCollapsed = collapsing
        resizePanel(remote, collapsed: collapsing, expanded: remoteExpandedSize, minimum: NSSize(width: 400, height: 330))
    }
    func resizePanel(_ window: NSWindow, collapsed: Bool, expanded: NSSize, minimum: NSSize) {
        let old = window.frame
        window.contentMinSize = collapsed ? NSSize(width: 320, height: 48) : minimum
        let size = collapsed ? NSSize(width: 340, height: 48) : expanded
        window.setFrame(NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height), display: true)
        if collapsed { window.styleMask.remove(.resizable) } else { window.styleMask.insert(.resizable) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showBoth(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { state.shutdown(); connection.disconnect() }
    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu(); appItem.submenu = app
        app.addItem(withTitle: "結束 Neko 桌面 Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "編輯"); editItem.submenu = edit
        edit.addItem(withTitle: "剪下", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "複製", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "貼上", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全選", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let window = NSMenu(title: "視窗"); windowItem.submenu = window
        for (title, selector, key) in [("顯示兩個面板", #selector(showBoth), "1"), ("顯示 VPS 遠端工作區", #selector(showRemote), "2"), ("恢復桌面位置", #selector(resetPositions), "0")] {
            let item = window.addItem(withTitle: title, action: selector, keyEquivalent: key); item.target = self
        }
        NSApp.mainMenu = main
    }
}
