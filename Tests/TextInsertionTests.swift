import Foundation
import ApplicationServices

private final class InsertionFixture {
    var trusted = true
    var now = Date(timeIntervalSince1970: 1_000)
    var pid: pid_t = 42
    var bundle = "example.editor"
    var window = "Draft"
    var windowElement: AnyObject? = NSObject()
    var localPasteTarget: Bool?
    var element: AnyObject = NSObject()
    var editable = true
    var hasSnapshot = true
    var clipboard: String?
    var copySucceeds = true
    var pasteSucceeds = true
    var submitSucceeds = true
    var events: [String] = []
    var scheduled: [(TimeInterval, () -> Void)] = []
    var responses: [RemoteMessage] = []
    var sessionCounter = 0

    lazy var focus = FocusTargetService(environment: .init(
        isAccessibilityTrusted: { [unowned self] in trusted },
        currentSnapshot: { [unowned self] in
            guard hasSnapshot else { return nil }
            return FocusTargetSnapshot(
                pid: pid,
                bundleIdentifier: bundle,
                appName: "Editor",
                windowTitle: window,
                element: element,
                isEditable: editable,
                isLocalPasteTarget: localPasteTarget,
                windowElement: windowElement
            )
        },
        elementsMatch: { $0 === $1 },
        now: { [unowned self] in now },
        newSessionID: { [unowned self] in
            sessionCounter += 1
            return "session-\(sessionCounter)"
        },
        macName: { "Test Mac" }
    ))

    lazy var insertion = TextInsertionService(focusTargets: focus, environment: .init(
        copyText: { [unowned self] text in
            events.append("copy")
            guard copySucceeds else { return false }
            clipboard = text
            return true
        },
        postPasteEvent: { [unowned self] in
            events.append("paste")
            return pasteSucceeds
        }
    ))

    lazy var remote = RemoteTargetController(
        focusTargets: focus,
        textInsertion: insertion,
        environment: .init(
            schedule: { [unowned self] delay, callback in scheduled.append((delay, callback)) },
            postSubmitEvent: { [unowned self] in
                events.append("submit")
                return submitSucceeds
            }
        )
    )

    func send(_ message: RemoteMessage) {
        remote.handle(message) { [unowned self] response in
            responses.append(response)
            return true
        }
    }

    func acquireRemoteTarget() -> RemoteTargetDescriptor {
        send(RemoteMessage(kind: .targetRequest))
        return responses.last!.target!
    }

    func runPasteCompletion() {
        guard let index = scheduled.firstIndex(where: { $0.0 == 0.28 }) else {
            preconditionFailure("Missing paste completion")
        }
        scheduled.remove(at: index).1()
    }
}

@main
enum TextInsertionTests {
    static func main() throws {
        testApplicationScopedFocusFallback()
        try testLocalInsertion()
        try testLocalKeyboardOnlyEditor()
        try testLocalTitleChangesKeepWindowIdentity()
        testRemoteTitleChangesRemainStrict()
        try testTargetChangesPreserveClipboard()
        try testPermissionAndCaptureFailures()
        try testExpiryAndEventFailures()
        testEditablePolicyExcludesPasswords()
        testLocalPastePolicy()
        testRemoteLifetimeAndActions()
        testRemoteSubmitRevalidates()
        testRemoteStaleSessionsAndDuplicateRequests()
        print("TextInsertionTests passed")
    }

    static func testApplicationScopedFocusFallback() {
        let expectedPID = ProcessInfo.processInfo.processIdentifier
        let expected = AXUIElementCreateApplication(expectedPID)
        let other = AXUIElementCreateApplication(expectedPID + 1)
        var appReads = 0
        let fallback = FocusTargetService.firstFocusedElement(
            matchingPID: expectedPID,
            readSystem: { nil },
            readApplication: { appReads += 1; return expected }
        )
        precondition(fallback.map { CFEqual($0, expected) } == true)
        precondition(appReads == 1)
        let system = FocusTargetService.firstFocusedElement(
            matchingPID: expectedPID,
            readSystem: { expected },
            readApplication: { appReads += 1; return other }
        )
        precondition(system.map { CFEqual($0, expected) } == true)
        precondition(appReads == 1, "Do not consult a second source when system focus is already valid")
        let wrongApp = FocusTargetService.firstFocusedElement(
            matchingPID: expectedPID,
            readSystem: { other },
            readApplication: { other }
        )
        precondition(wrongApp == nil, "A focus query must never select another application")
    }

    static func testLocalInsertion() throws {
        let f = InsertionFixture()
        let target = try f.focus.captureTarget(policy: .localDictation)
        precondition(target.expiresAt == f.now.addingTimeInterval(600))
        f.now = f.now.addingTimeInterval(360) // Five-minute recording plus transcription still works.
        precondition(f.insertion.insert("測試文字", target: target) == .pasteEventPosted)
        precondition(f.clipboard == "測試文字")
        precondition(f.events == ["copy", "paste"], "Local insertion must never submit")
    }

    static func testLocalKeyboardOnlyEditor() throws {
        let f = InsertionFixture()
        f.editable = false // AXValue is not directly writable, as in some web editors.
        f.localPasteTarget = true
        let target = try f.focus.captureTarget(policy: .localDictation)
        precondition(f.insertion.insert("鍵盤可貼上", target: target) == .pasteEventPosted)
        precondition(f.events == ["copy", "paste"])
        f.send(RemoteMessage(kind: .targetRequest))
        precondition(f.responses.last?.result?.code == .noEditableTarget,
                     "Local compatibility must not relax the relay's capture policy")
    }

    static func testLocalTitleChangesKeepWindowIdentity() throws {
        let f = InsertionFixture()
        let target = try f.focus.captureTarget(policy: .localDictation)
        f.window = "Renamed chat"
        precondition(f.insertion.insert("same caret", target: target) == .pasteEventPosted,
                     "A title update in the same window and element must not block local paste")
        f.events = []
        f.windowElement = NSObject()
        precondition(f.insertion.insert("different window", target: target) == .copiedOnly(.targetChanged))
        precondition(f.events == ["copy"])

        let unknown = InsertionFixture()
        unknown.windowElement = nil
        let unknownTarget = try unknown.focus.captureTarget(policy: .localDictation)
        unknown.window = "Another window"
        precondition(unknown.insertion.insert("saved", target: unknownTarget) == .copiedOnly(.targetChanged),
                     "Without window identity, a changed title is still rejected")
    }

    static func testRemoteTitleChangesRemainStrict() {
        for action in [RemoteAction.paste, .pasteAndSubmit] {
            let f = InsertionFixture()
            let target = f.acquireRemoteTarget()
            f.window = "Changed title"
            f.send(RemoteMessage(kind: .executeRequest, action: action, text: "遠端保存", targetSessionID: target.sessionID))
            precondition(f.events == ["copy"], "Relay title changes must never paste or submit")
            precondition(f.responses.last?.result?.code == .targetChanged)
        }
    }

    static func testTargetChangesPreserveClipboard() throws {
        let changes: [(InsertionFixture) -> Void] = [
            { $0.pid = 99 },
            { $0.bundle = "example.other" },
            { $0.element = NSObject() },
            { $0.editable = false },
            { $0.hasSnapshot = false }
        ]
        for policy in [FocusTargetPolicy.remoteStrict, .localDictation] {
            for change in changes {
                let f = InsertionFixture()
                let target = try f.focus.captureTarget(policy: policy)
                change(f)
                precondition(f.insertion.insert("保留這段", target: target) == .copiedOnly(.targetChanged))
                precondition(f.clipboard == "保留這段")
                precondition(f.events == ["copy"], "A changed target must never receive keyboard events")
            }
        }
    }

    static func testPermissionAndCaptureFailures() throws {
        let f = InsertionFixture()
        let target = try f.focus.captureTarget()
        f.trusted = false
        do {
            _ = try f.focus.captureTarget()
            preconditionFailure("Capture must require accessibility permission")
        } catch let error as FocusTargetError {
            precondition(error == .accessibilityDenied)
        }
        precondition(f.insertion.insert("keep", target: target) == .copiedOnly(.accessibilityDenied))
        precondition(f.clipboard == "keep")
        precondition(f.events == ["copy"])

        let unavailable = InsertionFixture()
        unavailable.editable = false
        do {
            _ = try unavailable.focus.captureTarget()
            preconditionFailure("Noneditable targets must be rejected")
        } catch let error as FocusTargetError {
            precondition(error == .noEditableTarget)
        }
        precondition(unavailable.insertion.insert("saved", target: nil, captureFailure: .noEditableTarget)
            == .copiedOnly(.noEditableTarget))
        precondition(unavailable.insertion.insert("missing", target: nil) == .copiedOnly(.noTarget))
        precondition(unavailable.clipboard == "missing")
        precondition(unavailable.events == ["copy", "copy"])
    }

    static func testExpiryAndEventFailures() throws {
        let expired = InsertionFixture()
        let target = try expired.focus.captureTarget(ttl: 300)
        expired.now = target.expiresAt
        precondition(expired.insertion.insert("expired", target: target) == .copiedOnly(.targetExpired))
        precondition(expired.events == ["copy"])
        precondition(expired.clipboard == "expired")

        let f = InsertionFixture()
        let valid = try f.focus.captureTarget()
        f.pasteSucceeds = false
        precondition(f.insertion.insert("saved", target: valid) == .copiedOnly(.eventUnavailable))
        precondition(f.clipboard == "saved")
        f.events = []
        f.copySucceeds = false
        precondition(f.insertion.insert("not copied", target: valid) == .copyFailed)
        precondition(f.events == ["copy"], "Never paste old clipboard contents after a copy failure")
        precondition(f.clipboard == "saved")
    }

    static func testEditablePolicyExcludesPasswords() {
        precondition(!FocusTargetService.isEditable(role: "AXTextField", subrole: "AXSecureTextField", canSetValue: true))
        precondition(!FocusTargetService.isEditable(role: "AXTextArea", subrole: nil, canSetValue: false))
        precondition(!FocusTargetService.isEditable(role: "AXButton", subrole: nil, canSetValue: true))
        precondition(FocusTargetService.isEditable(role: "AXTextArea", subrole: nil, canSetValue: true))
    }

    static func testLocalPastePolicy() {
        for role in ["AXTextField", "AXTextArea"] {
            precondition(FocusTargetService.isLocalPasteTarget(role: role, subrole: nil, canSetValue: false))
            precondition(!FocusTargetService.isLocalPasteTarget(role: role, subrole: "AXSecureTextField", canSetValue: true))
            precondition(!FocusTargetService.isLocalPasteTarget(role: role, subrole: nil, canSetValue: true, isEnabled: false))
            precondition(!FocusTargetService.isLocalPasteTarget(role: role, subrole: nil, canSetValue: true, isReadOnly: true))
            precondition(!FocusTargetService.isLocalPasteTarget(role: role, subrole: nil, canSetValue: true, isExplicitlyEditable: false))
            precondition(!FocusTargetService.isLocalPasteTarget(role: role, subrole: nil, canSetValue: true, hasProtectedContent: true))
        }
        for role in ["AXStaticText", "AXSecureTextField", "AXButton", "AXWebArea", "AXUnknownText"] {
            precondition(!FocusTargetService.isLocalPasteTarget(role: role, subrole: nil, canSetValue: true))
        }
        precondition(!FocusTargetService.isLocalPasteTarget(role: "AXComboBox", subrole: nil, canSetValue: false))
        precondition(FocusTargetService.isLocalPasteTarget(role: "AXComboBox", subrole: nil, canSetValue: true))
    }

    static func testRemoteLifetimeAndActions() {
        for action in [RemoteAction.paste, .pasteAndSubmit] {
            let f = InsertionFixture()
            let target = f.acquireRemoteTarget()
            precondition(target.expiresAt == f.now.addingTimeInterval(300), "Relay TTL must remain five minutes")
            f.send(RemoteMessage(kind: .executeRequest, action: action, text: "遠端文字", targetSessionID: target.sessionID))
            precondition(f.events == ["copy", "paste"])
            f.runPasteCompletion()
            precondition(f.events == (action.submits ? ["copy", "paste", "submit"] : ["copy", "paste"]))
            precondition(f.responses.last?.result?.code == (action.submits ? .submitted : .pasted))
        }
    }

    static func testRemoteSubmitRevalidates() {
        let f = InsertionFixture()
        let target = f.acquireRemoteTarget()
        f.send(RemoteMessage(kind: .executeRequest, action: .pasteAndSubmit, text: "保存", targetSessionID: target.sessionID))
        f.element = NSObject()
        f.runPasteCompletion()
        precondition(f.events == ["copy", "paste"], "Focus changed during paste delay: no Enter")
        precondition(f.responses.last?.result?.code == .targetChanged)
        precondition(f.clipboard == "保存")

        let cancelled = InsertionFixture()
        let initial = cancelled.acquireRemoteTarget()
        cancelled.send(RemoteMessage(kind: .executeRequest, action: .pasteAndSubmit, text: "保存", targetSessionID: initial.sessionID))
        cancelled.send(RemoteMessage(kind: .cancelRequest))
        cancelled.runPasteCompletion()
        precondition(cancelled.events == ["copy", "paste"])
        precondition(cancelled.responses.last?.result?.code == .targetChanged)

        let replacement = InsertionFixture()
        let old = replacement.acquireRemoteTarget()
        replacement.send(RemoteMessage(kind: .executeRequest, action: .pasteAndSubmit, text: "舊", targetSessionID: old.sessionID))
        let new = replacement.acquireRemoteTarget()
        replacement.runPasteCompletion()
        precondition(replacement.responses.last?.result?.code == .targetChanged)
        replacement.send(RemoteMessage(kind: .executeRequest, action: .paste, text: "新", targetSessionID: new.sessionID))
        replacement.runPasteCompletion()
        precondition(replacement.responses.last?.result?.code == .pasted,
                     "An old completion must not clear a newly captured target")
        precondition(replacement.events == ["copy", "paste", "copy", "paste"])
    }

    static func testRemoteStaleSessionsAndDuplicateRequests() {
        let f = InsertionFixture()
        _ = f.acquireRemoteTarget()
        let request = RemoteMessage(kind: .executeRequest, action: .pasteAndSubmit, text: "保留", targetSessionID: "stale")
        f.send(request)
        precondition(f.events == ["copy"])
        precondition(f.responses.last?.result?.code == .targetChanged)
        precondition(f.clipboard == "保留")
        f.send(request)
        precondition(f.events == ["copy"], "Duplicate request must not execute twice")

        let invalid = InsertionFixture()
        let target = invalid.acquireRemoteTarget()
        invalid.send(RemoteMessage(kind: .executeRequest, action: .paste, text: "   ", targetSessionID: target.sessionID))
        precondition(invalid.responses.last?.result?.code == .invalidRequest)
        precondition(invalid.events.isEmpty)
    }
}
