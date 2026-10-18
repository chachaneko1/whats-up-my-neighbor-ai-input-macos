import AppKit

@main
final class PreviewApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var controller: DesktopPetController!
    private var state: NSTextField!
    private var releaseButton: NSButton!

    static func main() {
        let app = NSApplication.shared
        let delegate = PreviewApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let resources = Bundle.main.resourceURL!.appendingPathComponent("DesktopPet")
        let menu = NSMenu()
        let application = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "結束預覽", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = applicationMenu
        menu.addItem(application)
        NSApp.mainMenu = menu
        controller = DesktopPetController(resources: resources)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 430, height: 280),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "小黑貓・Gemini 補間試玩"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "Gemini 小黑貓・拖曳試玩")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(title)
        let hint = NSTextField(wrappingLabelWithString: "點一下，牠會回應你。\n按住拖曳，就能把牠拎起放下。\n平常安靜待機，閒置後洗臉、散步。")
        hint.font = .systemFont(ofSize: 14)
        stack.addArrangedSubview(hint)
        state = NSTextField(labelWithString: "")
        state.textColor = .secondaryLabelColor
        stack.addArrangedSubview(state)
        let buttons = NSStackView()
        buttons.spacing = 8
        for (text, selector) in [("逗一下", #selector(pet)), ("看洗臉", #selector(groom)),
                                 ("看散步", #selector(walk)), ("重設位置", #selector(reset))] {
            buttons.addArrangedSubview(NSButton(title: text, target: self, action: selector))
        }
        stack.addArrangedSubview(buttons)
        let bottom = NSStackView()
        bottom.spacing = 8
        releaseButton = NSButton(title: "收回小黑貓", target: self, action: #selector(toggle))
        bottom.addArrangedSubview(releaseButton)
        bottom.addArrangedSubview(NSButton(title: "結束預覽", target: self, action: #selector(quit)))
        stack.addArrangedSubview(bottom)
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22)
        ])
        controller.onStateChange = { [weak self] value in self?.state.stringValue = "狀態：" + value }
        controller.setReleased(true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Own-window IDs only, for binding native QA to the floating cat rather
        // than guessing a screen coordinate or inspecting other applications.
        let windows: [String: Int] = ["control": window.windowNumber, "cat": controller.panel.windowNumber]
        if let data = try? JSONSerialization.data(withJSONObject: windows, options: [.sortedKeys]) {
            try? data.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("preview-windows.json"))
        }
    }

    @objc private func pet() { controller.pet() }
    @objc private func groom() { controller.demonstrate(.grooming) }
    @objc private func walk() { controller.demonstrate(.walking) }
    @objc private func reset() { controller.setReleased(true) }
    @objc private func toggle() {
        controller.setReleased(!controller.model.released)
        releaseButton.title = controller.model.released ? "收回小黑貓" : "放出小黑貓"
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { controller?.dispose() }
}
