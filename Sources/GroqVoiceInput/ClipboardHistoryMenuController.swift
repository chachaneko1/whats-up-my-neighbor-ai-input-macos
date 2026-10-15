import AppKit

/// Small settings submenu. Text history is shown only in the cat picker.
final class ClipboardHistoryMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: "剪貼簿設定")
    var onWillOpen: (() -> Void)?
    var onToggleRecording: (() -> Void)?
    var onClear: (() -> Void)?

    private var isReloading = false

    override init() {
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        update(items: [], isEnabled: true)
    }

    func update(items: [ClipboardHistoryItem], isEnabled: Bool, error: String? = nil) {
        menu.removeAllItems()
        if let error, !error.isEmpty { addDisabledItem(Self.singleLinePrefix(error)) }
        addDisabledItem("已保留 \(items.filter { $0.kind == .text }.count) 筆文字")
        let pause = NSMenuItem(title: "暫停記錄", action: #selector(toggleRecording(_:)), keyEquivalent: "")
        pause.target = self
        pause.state = isEnabled ? .off : .on
        menu.addItem(pause)
        let clear = NSMenuItem(title: "清除全部紀錄…", action: #selector(clearHistory(_:)), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !items.isEmpty || error != nil
        menu.addItem(clear)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu, !isReloading else { return }
        isReloading = true
        defer { isReloading = false }
        onWillOpen?()
    }

    private func addDisabledItem(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @objc private func toggleRecording(_ sender: NSMenuItem) { onToggleRecording?() }

    @objc private func clearHistory(_ sender: NSMenuItem) {
        guard sender.isEnabled else { return }
        onClear?()
    }

    /// Stop after the displayed prefix rather than copying an entire long entry
    /// just to make a menu title. Never expose the full text through a tooltip.
    private static func singleLinePrefix(_ text: String) -> String {
        let limit = 50
        var characters: [Character] = []
        var needsSpace = false
        for character in text {
            if character.isWhitespace {
                needsSpace = !characters.isEmpty
                continue
            }
            if character.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) { continue }
            if needsSpace { characters.append(" "); needsSpace = false }
            characters.append(character)
            if characters.count > limit { return String(characters.prefix(limit - 1)) + "…" }
        }
        return String(characters)
    }

}
