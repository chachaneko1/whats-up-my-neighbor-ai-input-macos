import AppKit

@main final class CatCoatMenuPreview: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var coatItems: [String: NSMenuItem] = [:]

    static func main() {
        let app = NSApplication.shared
        let preview = CatCoatMenuPreview()
        app.delegate = preview
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🐈"
        statusItem.button?.setAccessibilityLabel("貓咪花色選單預覽")

        let menu = NSMenu()
        let heading = NSMenuItem(title: "選色選單預覽 · 不修改個人設定", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        let (coatMenu, items) = CatCoatMenu.make(target: self, action: #selector(selectCoat(_:)))
        coatItems = items
        menu.addItem(coatMenu)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "結束預覽", action: #selector(quitPreview), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        updateSelection("original")
    }

    @objc private func selectCoat(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let coat = CatAppearance.makePreset(id) else { return }
        updateSelection(id)
        let alert = NSAlert()
        alert.messageText = "已選擇\(coat.title)"
        alert.informativeText = "這是隔離的選單預覽，沒有修改你正在使用的 App 或貓咪設定。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func updateSelection(_ id: String) {
        for (coat, item) in coatItems { item.state = coat == id ? .on : .off }
    }

    @objc private func quitPreview() { NSApp.terminate(nil) }
}
