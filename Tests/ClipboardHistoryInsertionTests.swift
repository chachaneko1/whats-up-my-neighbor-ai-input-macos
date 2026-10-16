import AppKit

/// Every clipboard, focus and keyboard boundary below is synthetic. The live
/// monitor initializer, NSPasteboard.general and AX focus queries are never used.
private final class HistoryInsertionFixture {
    let suite = "ClipboardHistoryInsertionTests-" + UUID().uuidString
    let defaults: UserDefaults
    let store = ClipboardHistoryStore(directoryURL: nil)
    var generation = 1
    var clipboard = Data("synthetic initial clipboard".utf8)
    var copySucceeds = true
    var pasteSucceeds = true
    var trusted = true
    var now = Date(timeIntervalSince1970: 1_000)
    var element: AnyObject = NSObject()
    let window: AnyObject = NSObject()
    var events: [String] = []
    var payloadReads = 0
    var historyAtPaste: [[ClipboardHistoryItem]] = []
    var clipboardAtPaste: [Data] = []
    var scheduled: [(TimeInterval, () -> Void)] = []
    var responses: [RemoteMessage] = []

    lazy var monitor = ClipboardHistoryMonitor(store: store, defaults: defaults, environment: .init(
        changeCount: { [unowned self] in generation },
        metadata: { .init(rootTypes: [.string], itemTypes: [[.string]]) },
        data: { [unowned self] type in
            payloadReads += 1
            return type == .string ? clipboard : nil
        },
        write: { [unowned self] data, type in
            precondition(type == .string)
            events.append("copy")
            guard copySucceeds else { return nil }
            generation += 1
            clipboard = data
            return generation
        }
    ))

    lazy var focus = FocusTargetService(environment: .init(
        isAccessibilityTrusted: { [unowned self] in trusted },
        currentSnapshot: { [unowned self] in
            FocusTargetSnapshot(pid: 42, bundleIdentifier: "test.synthetic-editor", appName: "Synthetic",
                                windowTitle: "Fixture", element: element, isEditable: true,
                                isLocalPasteTarget: true, windowElement: window)
        },
        elementsMatch: { $0 === $1 },
        now: { [unowned self] in now },
        newSessionID: { UUID().uuidString },
        macName: { "Synthetic Mac" }
    ))

    lazy var insertion = TextInsertionService(focusTargets: focus, environment: .init(
        copyText: { [unowned self] in monitor.copyText($0) },
        postPasteEvent: { [unowned self] in
            historyAtPaste.append(store.items)
            clipboardAtPaste.append(clipboard)
            events.append("paste")
            return pasteSucceeds
        }
    ))

    lazy var remote = RemoteTargetController(focusTargets: focus, textInsertion: insertion, environment: .init(
        schedule: { [unowned self] delay, action in scheduled.append((delay, action)) },
        postSubmitEvent: { [unowned self] in events.append("submit"); return true }
    ))

    init() {
        defaults = UserDefaults(suiteName: suite)!
        monitor.checkForChanges() // Baseline without installing a timer or reading data.
        store.onChange = { [weak self] in self?.events.append("history") }
    }

    deinit {
        monitor.stop()
        defaults.removePersistentDomain(forName: suite)
    }

    func send(_ message: RemoteMessage) {
        remote.handle(message) { [unowned self] in responses.append($0); return true }
    }

    func remoteTarget() -> RemoteTargetDescriptor {
        send(RemoteMessage(kind: .targetRequest))
        return responses.last!.target!
    }

    func completeRemotePaste() {
        let index = scheduled.firstIndex { $0.0 == 0.28 }!
        scheduled.remove(at: index).1()
    }
}

@main
enum ClipboardHistoryInsertionTests {
    private static var checks = 0

    private static func check(_ condition: Bool, _ message: String = "",
                              file: StaticString = #file, line: UInt = #line) {
        checks += 1
        precondition(condition, message, file: file, line: line)
    }

    static func main() throws {
        try testCopiedOnlyKeepsHistory()
        try testPasteObservesHistoryBeforePosting()
        try testMixedHistoryAndReinsertion()
        try testCopyFailureDoesNotSaveOrPaste()
        try testEventFailureKeepsSuccessfulCopy()
        try testPausedHistoryStillCopiesAndPastes()
        try testRemoteUsesTheSameWriter()
        testRemoteRefusalStillKeepsHistory()
        print("ClipboardHistoryInsertionTests passed: \(checks) injected integration checks; no general clipboard, disk history or external UI access")
    }

    private static func testCopiedOnlyKeepsHistory() throws {
        for failure in [TextInsertionCopyReason.noTarget, .targetChanged, .targetExpired, .accessibilityDenied] {
            let f = HistoryInsertionFixture()
            var target: FocusTarget? = try f.focus.captureTarget(policy: .localDictation)
            switch failure {
            case .noTarget: target = nil
            case .targetChanged: f.element = NSObject()
            case .targetExpired: f.now.addTimeInterval(601)
            case .accessibilityDenied: f.trusted = false
            default: preconditionFailure("Unexpected fixture")
            }
            let text = "保留這次辨識文字\n"
            check(f.insertion.insert(text, target: target) == .copiedOnly(failure))
            check(f.store.items.map(\.text) == [text], "Refused paste still saves the successfully copied transcript")
            check(f.clipboard == Data(text.utf8))
            check(f.events == ["copy", "history"] && f.historyAtPaste.isEmpty)
            f.monitor.checkForChanges()
            check(f.store.items.count == 1 && f.payloadReads == 0, "Own output is not read back or duplicated")
        }
    }

    private static func testPasteObservesHistoryBeforePosting() throws {
        let f = HistoryInsertionFixture()
        let target = try f.focus.captureTarget(policy: .localDictation)
        let text = "  貼上時歷史已保留\n下一行  "
        check(f.insertion.insert(text, target: target) == .pasteEventPosted)
        check(f.historyAtPaste.count == 1 && f.historyAtPaste[0].first?.text == text)
        check(f.clipboardAtPaste == [Data(text.utf8)])
        check(f.events == ["copy", "history", "paste"], "Exactly one paste; history is present before posting")
        let savedID = f.store.items[0].id
        f.monitor.checkForChanges()
        f.monitor.checkForChanges()
        f.store.flush()
        check(f.clipboard == Data(text.utf8), "The old clipboard must not be restored after Cmd+V")
        check(f.events == ["copy", "history", "paste"] && f.store.items[0].id == savedID)
        check(f.payloadReads == 0)
    }

    private static func testMixedHistoryAndReinsertion() throws {
        let f = HistoryInsertionFixture()
        let target = try f.focus.captureTarget(policy: .localDictation)
        check(f.insertion.insert("語音 A", target: target) == .pasteEventPosted)
        let originalA = f.store.items[0]
        f.clipboard = Data("複製 B".utf8)
        f.generation += 1
        f.monitor.checkForChanges()
        check(f.insertion.insert("語音 C", target: target) == .pasteEventPosted)
        check(f.store.items.map(\.text) == ["語音 C", "複製 B", "語音 A"])
        check(f.store.items.last == originalA)

        f.events.removeAll()
        check(f.insertion.insert(originalA.text!, target: target) == .pasteEventPosted)
        check(f.store.items.map(\.text) == ["語音 A", "語音 C", "複製 B"])
        check(f.store.items.first == originalA, "Selection keeps the original item identity and timestamp")
        check(f.clipboard == originalA.data && f.clipboardAtPaste.last == originalA.data)
        check(f.events == ["copy", "history", "paste"], "One paste without submitting or duplicating the history item")
        f.monitor.checkForChanges()
        check(f.store.items.count == 3, "The picker write must not be captured twice")
    }

    private static func testCopyFailureDoesNotSaveOrPaste() throws {
        let f = HistoryInsertionFixture()
        let target = try f.focus.captureTarget(policy: .localDictation)
        let initialClipboard = f.clipboard
        f.copySucceeds = false
        check(f.insertion.insert("未成功複製", target: target) == .copyFailed)
        check(f.events == ["copy"] && f.historyAtPaste.isEmpty)
        check(f.store.items.isEmpty && f.clipboard == initialClipboard)
        f.monitor.checkForChanges()
        check(f.store.items.isEmpty && f.payloadReads == 0)
    }

    private static func testEventFailureKeepsSuccessfulCopy() throws {
        let f = HistoryInsertionFixture()
        let target = try f.focus.captureTarget(policy: .localDictation)
        f.pasteSucceeds = false
        check(f.insertion.insert("按鍵無法送出仍保留", target: target) == .copiedOnly(.eventUnavailable))
        check(f.store.items.first?.text == "按鍵無法送出仍保留")
        check(f.events == ["copy", "history", "paste"])
    }

    private static func testPausedHistoryStillCopiesAndPastes() throws {
        let f = HistoryInsertionFixture()
        _ = f.store.add(kind: .text, data: Data("existing history".utf8))
        let originalHistory = f.store.items
        f.events.removeAll()
        f.monitor.setEnabled(false)
        let target = try f.focus.captureTarget(policy: .localDictation)
        check(f.insertion.insert("暫停時仍正常貼上", target: target) == .pasteEventPosted)
        check(f.events == ["copy", "paste"])
        check(f.store.items == originalHistory && f.historyAtPaste == [originalHistory])
        check(f.clipboard == Data("暫停時仍正常貼上".utf8))
        check(f.insertion.insert("暫停時僅複製", target: nil) == .copiedOnly(.noTarget))
        check(f.store.items == originalHistory && f.clipboard == Data("暫停時僅複製".utf8))
        f.monitor.setEnabled(true)
        f.monitor.checkForChanges()
        check(f.store.items == originalHistory, "Resume cannot import the paused transcript retrospectively")
    }

    private static func testRemoteUsesTheSameWriter() throws {
        for action in [RemoteAction.paste, .pasteAndSubmit] {
            let f = HistoryInsertionFixture()
            let localTarget = try f.focus.captureTarget(policy: .localDictation)
            check(f.insertion.insert("本機語音", target: localTarget) == .pasteEventPosted)
            let localID = f.store.items[0].id
            f.events.removeAll()
            let target = f.remoteTarget()
            f.send(RemoteMessage(kind: .executeRequest, action: action, text: "遠端語音", targetSessionID: target.sessionID))
            check(f.store.items.map(\.text) == ["遠端語音", "本機語音"])
            check(f.store.items[1].id == localID && f.historyAtPaste.last?.first?.text == "遠端語音")
            check(f.events == ["copy", "history", "paste"])
            f.completeRemotePaste()
            check(f.events == (action.submits ? ["copy", "history", "paste", "submit"] : ["copy", "history", "paste"]))
            check(f.responses.last?.result?.code == (action.submits ? .submitted : .pasted))
            check(f.clipboard == Data("遠端語音".utf8) && f.store.items.count == 2)
            f.monitor.checkForChanges()
            check(f.store.items.count == 2 && f.payloadReads == 0)
        }
    }

    private static func testRemoteRefusalStillKeepsHistory() {
        let f = HistoryInsertionFixture()
        let target = f.remoteTarget()
        f.element = NSObject()
        f.send(RemoteMessage(kind: .executeRequest, action: .pasteAndSubmit,
                             text: "遠端目標改變仍保留", targetSessionID: target.sessionID))
        check(f.responses.last?.result?.code == .targetChanged)
        check(f.store.items.first?.text == "遠端目標改變仍保留")
        check(f.events == ["copy", "history"] && f.historyAtPaste.isEmpty)
        check(!f.scheduled.contains { $0.0 == 0.28 }, "Refused remote insertion must not schedule submission")
    }
}
