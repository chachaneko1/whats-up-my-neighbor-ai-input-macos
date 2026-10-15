import AppKit
import ApplicationServices
import Carbon

private final class ClipboardPickerPanel: NSPanel {
    var onKey: ((NSEvent) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) { onKey?(event) }
}

private final class RoundedPawView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 2)).fill()
    }
}

/// Key panel remains nonactivating so the destination app can regain its editor
/// after the picker closes. It never reads live clipboard contents.
final class ClipboardPickerController: NSObject {
    var onInsertResult: ((TextInsertionResult) -> Void)?
    var isCurrentItem: ((ClipboardHistoryItem) -> Bool)?

    private let focusTargets: FocusTargetService
    private let textInsertion: TextInsertionService
    private var panel: ClipboardPickerPanel?
    private var rows: [NSButton] = []
    private var items: [ClipboardHistoryItem] = []
    private var selectedIndex = 0
    private var target: FocusTarget?
    private var captureFailure: FocusTargetError?
    private var resignObserver: NSObjectProtocol?
    private var generation = 0
    private var scrollView: NSScrollView?

    var isVisible: Bool { panel?.isVisible == true }

    init(focusTargets: FocusTargetService, textInsertion: TextInsertionService) {
        self.focusTargets = focusTargets
        self.textInsertion = textInsertion
    }

    func toggle(items: [ClipboardHistoryItem], shortcutTitle: String,
                target: FocusTarget?, captureFailure: FocusTargetError?) {
        if isVisible { dismiss(); return }
        show(items: items, shortcutTitle: shortcutTitle, target: target, captureFailure: captureFailure)
    }

    func show(items: [ClipboardHistoryItem], shortcutTitle: String,
              target: FocusTarget?, captureFailure: FocusTargetError?) {
        dismiss()
        self.items = Array(items.filter { $0.kind == .text }.prefix(10))
        self.target = target
        self.captureFailure = captureFailure
        selectedIndex = 0
        let panel = makePanel(shortcutTitle: shortcutTitle)
        self.panel = panel
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        panel.setFrameOrigin(NSPoint(x: screen.midX - panel.frame.width / 2,
                                     y: screen.maxY - panel.frame.height - 60))
        panel.orderFrontRegardless()
        panel.makeKey()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.dismiss() }
    }

    func dismiss() {
        generation += 1
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        panel?.orderOut(nil)
        panel = nil
        rows.removeAll()
        scrollView = nil
        items.removeAll()
        target = nil
        captureFailure = nil
    }

    private func makePanel(shortcutTitle: String) -> ClipboardPickerPanel {
        let frame = NSRect(x: 0, y: 0, width: 540, height: 530)
        let panel = ClipboardPickerPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onKey = { [weak self] event in self?.handleKey(event) }
        let root = NSView(frame: frame)
        panel.contentView = root

        let glass = NSVisualEffectView(frame: NSRect(x: 20, y: 15, width: 500, height: 405))
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 25
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 2
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.86).cgColor
        root.addSubview(glass)

        let tint = NSView(frame: glass.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(srgbRed: 1, green: 0.95, blue: 0.83, alpha: 0.54).cgColor
        glass.addSubview(tint)

        func label(_ value: String, frame: NSRect, size: CGFloat, weight: NSFont.Weight,
                   color: NSColor = NSColor(calibratedWhite: 0.09, alpha: 1)) -> NSTextField {
            let field = NSTextField(labelWithString: value)
            field.frame = frame
            field.font = .systemFont(ofSize: size, weight: weight)
            field.textColor = color
            field.lineBreakMode = .byTruncatingTail
            glass.addSubview(field)
            return field
        }
        _ = label("剪貼簿", frame: NSRect(x: 34, y: 357, width: 200, height: 28), size: 19, weight: .bold)
        let count = self.items.count
        let countLabel = label("\(count) 筆文字", frame: NSRect(x: 380, y: 362, width: 86, height: 20),
                               size: 12, weight: .medium)
        countLabel.alignment = .right

        let scroll = NSScrollView(frame: NSRect(x: 26, y: 48, width: 448, height: 300))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = count > 5
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 428, height: max(300, count * 58)))
        scroll.documentView = document
        glass.addSubview(scroll)
        scrollView = scroll
        if self.items.isEmpty {
            let empty = NSTextField(labelWithString: "還沒有文字紀錄")
            empty.frame = NSRect(x: 100, y: 139, width: 240, height: 25)
            empty.alignment = .center
            empty.font = .systemFont(ofSize: 16, weight: .medium)
            document.addSubview(empty)
        } else {
            for (index, item) in self.items.enumerated() {
                let y = document.frame.height - CGFloat(index + 1) * 58 + 4
                let text = (item.text ?? "").replacingOccurrences(of: "\\s+", with: " ",
                                                                   options: .regularExpression)
                let preview = text.count > 70 ? String(text.prefix(69)) + "…" : text
                let button = NSButton(title: preview, target: self, action: #selector(selectRow(_:)))
                button.tag = index
                button.frame = NSRect(x: 4, y: y, width: 416, height: 50)
                button.isBordered = false
                button.alignment = .left
                button.font = .systemFont(ofSize: 14.5, weight: .medium)
                button.cell?.lineBreakMode = .byTruncatingTail
                button.wantsLayer = true
                button.layer?.cornerRadius = 12
                button.setAccessibilityLabel("第 \(index + 1) 筆，\(preview)")
                document.addSubview(button)
                rows.append(button)
            }
            updateSelection()
        }
        let hint = label("↑↓ 選擇　 ↩ 直接貼上　 Esc 關閉",
                         frame: NSRect(x: 86, y: 16, width: 330, height: 19),
                         size: 12, weight: .medium,
                         color: NSColor(calibratedWhite: 0.32, alpha: 1))
        hint.alignment = .center
        hint.setAccessibilityLabel("上、下方向鍵選擇，Return 直接貼上，Escape 關閉。快捷鍵 \(shortcutTitle)")

        if let catImage = Bundle.main.url(forResource: "neko-base", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:)) {
            let cat = NSImageView(frame: NSRect(x: 170, y: 403, width: 200, height: 100))
            cat.image = catImage
            cat.imageScaling = .scaleAxesIndependently
            root.addSubview(cat)
        }
        for x in [194.0, 306.0] {
            let paw = RoundedPawView(frame: NSRect(x: x, y: 399, width: 40, height: 38))
            root.addSubview(paw)
        }
        return panel
    }

    private func handleKey(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_DownArrow:
            if !items.isEmpty { selectedIndex = min(selectedIndex + 1, items.count - 1); updateSelection() }
        case kVK_UpArrow:
            if !items.isEmpty { selectedIndex = max(0, selectedIndex - 1); updateSelection() }
        case kVK_Return, kVK_ANSI_KeypadEnter:
            select(index: selectedIndex)
        case kVK_Escape:
            dismiss()
        default:
            NSSound.beep()
        }
    }

    private func updateSelection() {
        for (index, row) in rows.enumerated() {
            row.layer?.backgroundColor = index == selectedIndex
                ? NSColor(srgbRed: 1, green: 0.82, blue: 0.58, alpha: 0.75).cgColor
                : NSColor.clear.cgColor
            if index == selectedIndex { row.scrollToVisible(row.bounds) }
        }
    }

    @objc private func selectRow(_ sender: NSButton) { select(index: sender.tag) }

    private func select(index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        let target = self.target
        let failure = captureFailure
        guard isCurrentItem?(item) == true, let text = item.text else { dismiss(); return }
        dismiss()
        let token = generation
        // Return and shortcut modifiers must be released before the destination
        // receives Cmd+V; otherwise key repeat can submit its form.
        func attempt(_ retries: Int) {
            guard self.generation == token else { return }
            let modifiers = CGEventSource.flagsState(.combinedSessionState)
            let returnHeld = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Return))
            let stillHeld = returnHeld || !modifiers.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
            if stillHeld {
                if retries == 0 {
                    self.onInsertResult?(self.textInsertion.insert(text, target: nil))
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { attempt(retries - 1) }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard self.generation == token else { return }
                self.onInsertResult?(self.textInsertion.insert(text, target: target, captureFailure: failure))
            }
        }
        attempt(30)
    }
}
