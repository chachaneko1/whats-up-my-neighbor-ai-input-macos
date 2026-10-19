#if CAT_COAT_TESTS
// Legacy local preview fixture. Cat acquisition belongs to the website;
// this window is excluded from the shipping app.
import AppKit

/// Candidate changes are private to this explicitly opened window. Only
/// adoption (or choosing the original) changes the desktop and preferences.
final class CatAdoptionController: NSWindowController {
    var onAdopt: ((CatCoat) -> Bool)?
    private(set) var candidate: CatCoat = .original
    private let preview: DesktopPetView
    private let name = NSTextField(labelWithString: "")
    private let traits = NSTextField(wrappingLabelWithString: "")
    private let identifier = NSTextField(labelWithString: "")
    private let current = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let adoptButton = NSButton(title: "帶回桌面", target: nil, action: nil)
    private let drawButton = NSButton(title: "再抽一隻", target: nil, action: nil)
    private let originalButton = NSButton(title: "使用原版黑貓", target: nil, action: nil)
    private var generate: () -> CatCoat

    init(resources: URL? = Bundle.main.resourceURL?.appendingPathComponent("DesktopPet"),
         generate: @escaping () -> CatCoat = { var rng = SystemRandomNumberGenerator(); return CatCoat.draw(using: &rng) }) {
        self.generate = generate
        preview = DesktopPetView(resources: resources)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 610),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "抽一隻貓咪"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 610))
        root.wantsLayer = true
        root.layer?.backgroundColor = CatCoatArtwork.color("#F6F2EB").cgColor
        window.contentView = root
        func label(_ field: NSTextField, frame: NSRect, size: CGFloat, weight: NSFont.Weight = .regular) {
            field.frame = frame; field.font = .systemFont(ofSize: size, weight: weight)
            field.textColor = CatCoatArtwork.color("#51443A"); field.alignment = .center
            root.addSubview(field)
        }
        let heading = NSTextField(labelWithString: "今天，遇見哪一隻？")
        label(heading, frame: NSRect(x: 28, y: 522, width: 564, height: 40), size: 27, weight: .semibold)
        label(current, frame: NSRect(x: 28, y: 490, width: 564, height: 24), size: 13)
        let card = NSView(frame: NSRect(x: 118, y: 242, width: 384, height: 232))
        card.wantsLayer = true; card.layer?.backgroundColor = NSColor.white.cgColor; card.layer?.cornerRadius = 24
        root.addSubview(card)
        preview.frame = NSRect(x: 70, y: 5, width: 244, height: 228)
        // Scale the actual 128pt production canvas; no separate mock artwork.
        preview.bounds = NSRect(origin: .zero, size: DesktopPetModel.size)
        preview.reduceMotion = true
        card.addSubview(preview)
        label(name, frame: NSRect(x: 28, y: 198, width: 564, height: 35), size: 24, weight: .semibold)
        label(traits, frame: NSRect(x: 38, y: 155, width: 544, height: 37), size: 13)
        label(identifier, frame: NSRect(x: 28, y: 128, width: 564, height: 22), size: 11)
        for (button, x, width, action) in [
            (originalButton, 36.0, 174.0, #selector(restoreOriginal)),
            (drawButton, 223.0, 144.0, #selector(drawAgain)),
            (adoptButton, 380.0, 204.0, #selector(adoptCandidate))
        ] {
            button.frame = NSRect(x: x, y: 68, width: width, height: 38)
            button.bezelStyle = .rounded; button.target = self; button.action = action
            root.addSubview(button)
        }
        adoptButton.keyEquivalent = "\r"
        label(status, frame: NSRect(x: 28, y: 14, width: 564, height: 40), size: 12)
        status.stringValue = "花色在這台 Mac 產生。喜歡再帶回桌面，原版黑貓隨時都在。"
    }
    required init?(coder: NSCoder) { nil }

    func present(current coat: CatCoat) {
        current.stringValue = "桌面上的是：" + coat.title
        if window?.isVisible != true { drawAgain() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func drawAgain() {
        let next = generate()
        guard preview.setCoat(next) else {
            status.stringValue = "花色預覽暫時無法載入，請再試一次。"
            return
        }
        candidate = next
        name.stringValue = next.title
        traits.stringValue = next.details
        identifier.stringValue = "花色編號 " + next.identifier
        preview.setAccessibilityLabel(next.title + "，" + next.details)
        status.stringValue = "輪廓、表情與動作維持原樣；每一隻都有自己的花紋。"
        adoptButton.isEnabled = true
    }

    @objc private func adoptCandidate() { adopt(candidate) }
    @objc private func restoreOriginal() { adopt(.original) }
    private func adopt(_ coat: CatCoat) {
        guard onAdopt?(coat) == true else {
            status.stringValue = "暫時無法套用花色，原本的貓咪仍會保留。"
            return
        }
        current.stringValue = "桌面上的是：" + coat.title
        close()
    }

    #if CAT_COAT_TESTS
    func testDraw() { drawAgain() }
    func testAdopt() { adoptCandidate() }
    func testRestore() { restoreOriginal() }
    var testPreview: DesktopPetView { preview }
    var testButtons: [NSButton] { [drawButton, adoptButton, originalButton] }
    #endif
}

#endif
