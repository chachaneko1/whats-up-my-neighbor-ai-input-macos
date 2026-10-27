import AppKit
import Carbon

/// Real picker views with synthetic focus, clipboard, held keys and scheduling.
/// No window is shown, no system clipboard is read, and no keyboard event is posted.
private final class PickerFixture {
    let store = ClipboardHistoryStore(directoryURL: nil)
    var element: AnyObject = NSObject()
    let window: AnyObject = NSObject()
    var held = false
    var scheduled: [(TimeInterval, () -> Void)] = []
    var copied: [String] = []
    var pasteCount = 0
    var results: [TextInsertionResult] = []
    lazy var focus = FocusTargetService(environment: .init(
        isAccessibilityTrusted: { true },
        currentSnapshot: { [unowned self] in
            FocusTargetSnapshot(pid: 42, bundleIdentifier: "test.editor", appName: "Synthetic",
                                windowTitle: "Fixture", element: element, isEditable: true,
                                windowElement: window)
        },
        elementsMatch: { $0 === $1 }, now: { Date(timeIntervalSince1970: 1_000) },
        newSessionID: { UUID().uuidString }, macName: { "Synthetic Mac" }
    ))
    lazy var insertion = TextInsertionService(focusTargets: focus, environment: .init(
        copyText: { [unowned self] in
            copied.append($0)
            return store.add(kind: .text, data: Data($0.utf8))
        },
        postPasteEvent: { [unowned self] in pasteCount += 1; return true }
    ))
    lazy var picker: ClipboardPickerController = {
        let picker = ClipboardPickerController(focusTargets: focus, textInsertion: insertion, environment: .init(
            selectionKeysHeld: { [unowned self] in held },
            schedule: { [unowned self] delay, action in scheduled.append((delay, action)) }
        ))
        picker.isCurrentItem = { [unowned self] in store.item(id: $0.id) == $0 }
        picker.onInsertResult = { [unowned self] in results.append($0) }
        return picker
    }()

    init() {
        for text in ["測試語音 A", "測試複製 B", "測試語音 C"] {
            _ = store.add(kind: .text, data: Data(text.utf8))
        }
    }

    func prepare(initialIndex: Int = 0) throws -> NSPanel {
        picker.testPrepare(items: store.items, target: try focus.captureTarget(policy: .localDictation),
                           initialIndex: initialIndex)
    }

    func key(_ code: Int, panel: NSPanel, release: Bool = true) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                    windowNumber: panel.windowNumber, context: nil, characters: "",
                                    charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code))!
        panel.sendEvent(event)
        if release { keyUp(code, panel: panel) }
    }

    func keyUp(_ code: Int, panel: NSPanel) {
        let event = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0,
                                    windowNumber: panel.windowNumber, context: nil, characters: "",
                                    charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code))!
        panel.sendEvent(event)
    }

    func next() { scheduled.removeFirst().1() }
    func drain() {
        var count = 0
        while !scheduled.isEmpty { precondition(count < 10); next(); count += 1 }
    }
}

@main
enum ClipboardPickerTests {
    private static var checks = 0
    private static func check(_ value: Bool, _ message: String = "",
                              file: StaticString = #file, line: UInt = #line) {
        checks += 1
        precondition(value, message, file: file, line: line)
    }

    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try testKeyboardAndMouse()
        try testHeldPasteNavigation()
        try testHeldConfirmationAndCancellation()
        try testStaleAndChangedTargets()
        try renderStates()
        print("ClipboardPickerTests passed: \(checks) view/selection checks; no displayed windows, system clipboard or external input")
    }

    private static func testKeyboardAndMouse() throws {
        let f = PickerFixture()
        let panel = try f.prepare()
        check(!panel.isVisible && panel.styleMask.contains(.nonactivatingPanel))
        f.key(kVK_DownArrow, panel: panel)
        f.key(kVK_DownArrow, panel: panel)
        f.key(kVK_Return, panel: panel)
        check(f.copied.isEmpty && f.scheduled.count == 1, "Wait for focus restoration before inserting")
        f.drain()
        check(f.copied == ["測試語音 A"] && f.pasteCount == 1)
        check(f.results == [.pasteEventPosted])
        check(f.store.items.map(\.text) == ["測試語音 A", "測試語音 C", "測試複製 B"])

        let mouse = PickerFixture()
        let mousePanel = try mouse.prepare()
        let rows = descendants(mousePanel.contentView!).compactMap { $0 as? NSButton }
        rows.first { $0.tag == 1 }!.performClick(nil)
        mouse.next()
        check(mouse.copied == ["測試複製 B"] && mouse.pasteCount == 1)
    }

    private static func testHeldPasteNavigation() throws {
        let f = PickerFixture()
        let panel = try f.prepare(initialIndex: 1)
        check(f.copied.isEmpty && f.scheduled.isEmpty, "Opening history must not first paste the current clipboard")
        f.picker.moveSelection(by: 1)
        f.picker.moveSelection(by: -1)
        f.held = true
        f.key(kVK_Return, panel: panel)
        f.picker.moveSelection(by: 1)
        f.next()
        check(f.copied.isEmpty, "Confirmation waits until Command, V and arrows are all released")
        f.held = false
        f.drain()
        check(f.copied == ["測試複製 B"] && f.pasteCount == 1,
              "Gesture starts on the previous item and locks selection while confirming")

        for (index, expected) in [(-1, "測試語音 C"), (999, "測試語音 A")] {
            let bound = PickerFixture()
            let boundPanel = try bound.prepare(initialIndex: index)
            bound.key(kVK_Return, panel: boundPanel)
            bound.drain()
            check(bound.copied == [expected], "Initial selection stays within available history")
        }

        let cancelled = PickerFixture()
        let cancelledPanel = try cancelled.prepare(initialIndex: 1)
        cancelled.key(kVK_Escape, panel: cancelledPanel)
        check(cancelled.copied.isEmpty && cancelled.scheduled.isEmpty,
              "Escape closes a gesture picker without replaying normal paste")
    }

    private static func testHeldConfirmationAndCancellation() throws {
        for code in [kVK_Return, kVK_ANSI_KeypadEnter] {
            let f = PickerFixture()
            let panel = try f.prepare()
            f.key(code, panel: panel, release: false)
            f.key(code, panel: panel, release: false)
            check(f.scheduled.count == 1 && f.copied.isEmpty, "Key repeat cannot select twice")
            for _ in 0..<40 { f.next() }
            check(f.pasteCount == 0 && f.copied.isEmpty, "Long holds cannot dismiss and paste early")
            f.keyUp(code, panel: panel)
            f.next()
            check(f.copied.isEmpty && f.scheduled.first?.0 == 0.12)
            f.next()
            check(f.copied == ["測試語音 C"] && f.pasteCount == 1)
        }

        let f = PickerFixture()
        let panel = try f.prepare()
        f.held = true
        f.key(kVK_Return, panel: panel)
        f.key(kVK_Escape, panel: panel)
        f.held = false
        f.next()
        check(f.scheduled.isEmpty && f.copied.isEmpty && f.pasteCount == 0, "Escape cancels a pending held-key selection")

        let modifiers = PickerFixture()
        let modifierPanel = try modifiers.prepare()
        modifiers.held = true
        modifiers.key(kVK_Return, panel: modifierPanel)
        modifiers.next()
        check(modifiers.copied.isEmpty, "Released Enter must still wait for held shortcut modifiers")
        modifiers.held = false
        modifiers.drain()
        check(modifiers.pasteCount == 1)
    }

    private static func testStaleAndChangedTargets() throws {
        let stale = PickerFixture()
        let stalePanel = try stale.prepare()
        stale.store.clear()
        stale.key(kVK_Return, panel: stalePanel)
        check(stale.scheduled.isEmpty && stale.copied.isEmpty, "A removed history row cannot insert")

        let changed = PickerFixture()
        let panel = try changed.prepare()
        changed.key(kVK_Return, panel: panel)
        changed.element = NSObject()
        changed.drain()
        check(changed.copied == ["測試語音 C"] && changed.pasteCount == 0)
        check(changed.results == [.copiedOnly(.targetChanged)])

        let replaced = PickerFixture()
        let old = try replaced.prepare()
        replaced.key(kVK_Return, panel: old)
        _ = try replaced.prepare()
        replaced.next()
        check(replaced.copied.isEmpty, "Reopening invalidates the old delayed insertion")
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private static func renderStates() throws {
        let f = PickerFixture()
        for (name, items) in [("empty", [ClipboardHistoryItem]()), ("populated", f.store.items)] {
            let panel = f.picker.testPrepare(items: items)
            let view = panel.contentView!
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = bitmap.representation(using: .png, properties: [:])!
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1])
                .appendingPathComponent("clipboard-picker-\(name).png"))
            check(!panel.isVisible, "Rendering cannot steal typing focus")
        }
        let empty = f.picker.testPrepare(items: [])
        f.key(kVK_Return, panel: empty)
        check(f.scheduled.isEmpty && f.copied.isEmpty)
        f.key(kVK_Escape, panel: empty)
    }
}
