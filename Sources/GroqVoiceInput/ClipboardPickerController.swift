import AppKit
import ApplicationServices
import Carbon

private final class ClipboardPickerPanel: NSPanel {
    var onKey: ((NSEvent) -> Void)?
    var onKeyUp: ((NSEvent) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) { onKey?(event) }
    override func keyUp(with event: NSEvent) { onKeyUp?(event) }
    override func sendEvent(_ event: NSEvent) {
        // Route releases before a button or another first responder consumes them.
        switch event.type {
        case .keyDown: keyDown(with: event)
        case .keyUp: keyUp(with: event)
        default: super.sendEvent(event)
        }
    }
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
    struct Environment {
        var selectionKeysHeld: () -> Bool
        var schedule: (TimeInterval, @escaping () -> Void) -> Void

        static var system: Self {
            Self(selectionKeysHeld: {
                // A synthesized Cmd+V sets modifier flags without pressing a
                // Command key. Query the actual keys to avoid a stale flag wait.
                let keys = [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Command, kVK_RightCommand,
                            kVK_Control, kVK_RightControl, kVK_Option, kVK_RightOption,
                            kVK_Shift, kVK_RightShift, kVK_ANSI_V, kVK_UpArrow, kVK_DownArrow]
                return keys.contains { CGEventSource.keyState(.hidSystemState, key: CGKeyCode($0)) }
            }, schedule: { delay, action in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
            })
        }
    }

    var onInsertResult: ((TextInsertionResult) -> Void)?
    var isCurrentItem: ((ClipboardHistoryItem) -> Bool)?

    private let focusTargets: FocusTargetService
    private let textInsertion: TextInsertionService
    private let environment: Environment
    private var panel: ClipboardPickerPanel?
    private var rows: [NSButton] = []
    private var items: [ClipboardHistoryItem] = []
    private var selectedIndex = 0
    private var target: FocusTarget?
    private var captureFailure: FocusTargetError?
    private var resignObserver: NSObjectProtocol?
    private var generation = 0
    private var isSelecting = false
    private var heldConfirmationKeys: Set<UInt16> = []
    private var scrollView: NSScrollView?

    var isVisible: Bool { panel?.isVisible == true }

    init(focusTargets: FocusTargetService, textInsertion: TextInsertionService,
         environment: Environment = .system) {
        self.focusTargets = focusTargets
        self.textInsertion = textInsertion
        self.environment = environment
    }

    func toggle(items: [ClipboardHistoryItem], shortcutTitle: String,
                target: FocusTarget?, captureFailure: FocusTargetError?) {
        if isVisible { dismiss(); return }
        show(items: items, shortcutTitle: shortcutTitle, target: target, captureFailure: captureFailure)
    }

    func show(items: [ClipboardHistoryItem], shortcutTitle: String,
              target: FocusTarget?, captureFailure: FocusTargetError?, initialIndex: Int = 0) {
        let panel = prepare(items: items, shortcutTitle: shortcutTitle,
                            target: target, captureFailure: captureFailure, initialIndex: initialIndex)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        panel.setFrameOrigin(NSPoint(x: screen.midX - panel.frame.width / 2,
                                     y: screen.maxY - panel.frame.height - 60))
        panel.orderFrontRegardless()
        panel.makeKey()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.dismiss() }
    }

    private func prepare(items: [ClipboardHistoryItem], shortcutTitle: String,
                         target: FocusTarget?, captureFailure: FocusTargetError?, initialIndex: Int = 0) -> ClipboardPickerPanel {
        dismiss()
        self.items = Array(items.filter { $0.kind == .text }.prefix(10))
        self.target = target
        self.captureFailure = captureFailure
        selectedIndex = min(max(0, initialIndex), max(0, self.items.count - 1))
        let panel = makePanel(shortcutTitle: shortcutTitle)
        self.panel = panel
        return panel
    }

    #if CLIPBOARD_PICKER_TESTING
    /// Build the real view without displaying a window or changing typing focus.
    func testPrepare(items: [ClipboardHistoryItem], shortcutTitle: String = "按住 ⌘V，再按 ↑／↓",
                     target: FocusTarget? = nil, captureFailure: FocusTargetError? = nil) -> NSPanel {
        prepare(items: items, shortcutTitle: shortcutTitle, target: target, captureFailure: captureFailure)
    }
    #endif

    func dismiss() {
        generation += 1
        isSelecting = false
        heldConfirmationKeys.removeAll()
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
        panel.title = "剪貼簿歷史"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onKey = { [weak self] event in self?.handleKey(event) }
        panel.onKeyUp = { [weak self] event in self?.heldConfirmationKeys.remove(event.keyCode) }
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
        _ = label("剪貼簿歷史", frame: NSRect(x: 34, y: 357, width: 250, height: 28), size: 19, weight: .bold)
        let count = self.items.count
        let countLabel = label("\(count) 筆文字", frame: NSRect(x: 380, y: 362, width: 86, height: 20),
                               size: 12, weight: .medium)
        countLabel.alignment = .right

        let scroll = NSScrollView(frame: NSRect(x: 26, y: 68, width: 448, height: 280))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = count > 4
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 428, height: max(280, count * 58)))
        scroll.documentView = document
        glass.addSubview(scroll)
        scrollView = scroll
        if self.items.isEmpty {
            let empty = NSTextField(labelWithString: "還沒有文字紀錄")
            empty.frame = NSRect(x: 100, y: 139, width: 240, height: 25)
            empty.alignment = .center
            empty.font = .systemFont(ofSize: 16, weight: .medium)
            empty.textColor = NSColor(calibratedWhite: 0.09, alpha: 1)
            document.addSubview(empty)
            let guidance = NSTextField(labelWithString: "錄音完成或複製文字後會出現在這裡")
            guidance.frame = NSRect(x: 14, y: 106, width: 400, height: 22)
            guidance.alignment = .center
            guidance.font = .systemFont(ofSize: 13)
            guidance.textColor = NSColor(calibratedWhite: 0.32, alpha: 1)
            document.addSubview(guidance)
        } else {
            for (index, item) in self.items.enumerated() {
                let y = document.frame.height - CGFloat(index + 1) * 58 + 4
                let text = item.text ?? ""
                // Preview only; the selected item's original UTF-8 payload is
                // never normalized, rendered as HTML, or copied from this label.
                let preview = String(text.prefix(180)) + (text.count > 180 ? "…" : "")
                let button = NSButton(title: preview, target: self, action: #selector(selectRow(_:)))
                button.tag = index
                button.frame = NSRect(x: 4, y: y, width: 416, height: 50)
                button.isBordered = false
                button.alignment = .left
                button.font = text.contains("\n") || text.contains("`") || text.contains("\t")
                    ? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
                    : .systemFont(ofSize: 14.5, weight: .medium)
                button.cell?.usesSingleLineMode = false
                button.cell?.wraps = true
                button.cell?.lineBreakMode = .byTruncatingTail
                button.toolTip = "保留原始 Markdown、換行與縮排貼上"
                button.wantsLayer = true
                button.layer?.cornerRadius = 12
                button.setAccessibilityLabel("第 \(index + 1) 筆，\(preview)")
                document.addSubview(button)
                rows.append(button)
            }
            updateSelection()
        }
        let hint = label("↑↓ 選擇　 ↩ 貼上（不送出）　 Esc 關閉",
                         frame: NSRect(x: 26, y: 37, width: 448, height: 19),
                         size: 12, weight: .medium,
                         color: NSColor(calibratedWhite: 0.32, alpha: 1))
        hint.alignment = .center
        hint.setAccessibilityLabel("上、下方向鍵選擇，Return 直接貼上，Escape 關閉。快捷鍵 \(shortcutTitle)")
        let shortcut = label("開啟快捷鍵：\(shortcutTitle)",
                             frame: NSRect(x: 26, y: 16, width: 448, height: 18),
                             size: 11, weight: .regular,
                             color: NSColor(calibratedWhite: 0.32, alpha: 1))
        shortcut.alignment = .center

        if let catImage = Bundle.main.url(forResource: "neko-base", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:)) {
            let cat = NSImageView(frame: NSRect(x: 170, y: 403, width: 200, height: 100))
            cat.image = catImage
            cat.imageScaling = .scaleAxesIndependently
            root.addSubview(cat)
        }
        for x in [194.0, 306.0] {
            let paw = RoundedPawView(frame: NSRect(x: x, y: 391, width: 40, height: 38))
            root.addSubview(paw)
        }
        return panel
    }

    private func handleKey(_ event: NSEvent) {
        if [kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode)) {
            heldConfirmationKeys.insert(event.keyCode)
        }
        if isSelecting {
            if Int(event.keyCode) == kVK_Escape { dismiss() }
            return
        }
        switch Int(event.keyCode) {
        case kVK_DownArrow:
            moveSelection(by: 1)
        case kVK_UpArrow:
            moveSelection(by: -1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            select(index: selectedIndex)
        case kVK_Escape:
            dismiss()
        default:
            NSSound.beep()
        }
    }

    func moveSelection(by delta: Int) {
        guard !isSelecting, !items.isEmpty else { return }
        selectedIndex = min(items.count - 1, max(0, selectedIndex + delta))
        updateSelection()
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
        guard !isSelecting, items.indices.contains(index) else { return }
        let item = items[index]
        let target = self.target
        let failure = captureFailure
        guard isCurrentItem?(item) == true, let text = item.text else { dismiss(); return }
        isSelecting = true
        let token = generation
        // Keep the panel key until Return and shortcut modifiers are released,
        // so a held confirmation key cannot repeat into the destination app.
        func attempt() {
            guard self.generation == token else { return }
            if !self.heldConfirmationKeys.isEmpty || self.environment.selectionKeysHeld() {
                self.environment.schedule(0.05) { attempt() }
                return
            }
            self.dismiss()
            let insertionToken = self.generation
            self.environment.schedule(0.12) {
                guard self.generation == insertionToken else { return }
                self.onInsertResult?(self.textInsertion.insert(text, target: target, captureFailure: failure))
            }
        }
        attempt()
    }
}
