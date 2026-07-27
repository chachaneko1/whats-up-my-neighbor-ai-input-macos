import Foundation

@main
enum RemoteProtocolTests {
    static func main() throws {
        let target = RemoteTargetDescriptor(
            sessionID: "session-test",
            macName: "Test Mac",
            appName: "Google Chrome",
            windowTitle: "ChatGPT",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let original = RemoteMessage(
            id: "request-test",
            kind: .targetResponse,
            replyTo: "target-request",
            target: target,
            targetSessionID: target.sessionID
        )
        let decoded = try RemoteMessageCodec.decode(
            RemoteMessage.self,
            from: RemoteMessageCodec.encode(original)
        )
        precondition(decoded == original, "Remote message JSON round-trip failed")

        precondition(RemoteAction.pasteAndSubmit.submits, "pasteAndSubmit must be the only submit action")
        precondition(!RemoteAction.paste.submits, "paste must never submit")
        precondition(!RemoteAction.cancel.submits, "cancel must never submit")
        precondition(RemoteProtocolPolicy.supports(1), "Current protocol version must be supported")
        precondition(!RemoteProtocolPolicy.supports(99), "Unknown protocol versions must be rejected")
        precondition(RemoteActionPolicy.canExecute(hasText: true, hasTarget: true, isConnected: true, isWaiting: false))
        precondition(!RemoteActionPolicy.canExecute(hasText: false, hasTarget: true, isConnected: true, isWaiting: false))
        precondition(!RemoteActionPolicy.canExecute(hasText: true, hasTarget: false, isConnected: true, isWaiting: false))
        precondition(!RemoteActionPolicy.canExecute(hasText: true, hasTarget: true, isConnected: false, isWaiting: false))
        precondition(!RemoteActionPolicy.canExecute(hasText: true, hasTarget: true, isConnected: true, isWaiting: true))

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let valid = RemoteTargetValidationPolicy.evaluate(
            expectedPID: 42,
            currentPID: 42,
            expectedBundleIdentifier: "test.app",
            currentBundleIdentifier: "test.app",
            expectedWindowTitle: "Chat",
            currentWindowTitle: "Chat",
            elementMatches: true,
            isEditable: true,
            expiresAt: now.addingTimeInterval(60),
            now: now
        )
        precondition(valid == nil)
        precondition(RemoteTargetValidationPolicy.evaluate(
            expectedPID: 42,
            currentPID: 99,
            expectedBundleIdentifier: "test.app",
            currentBundleIdentifier: "test.app",
            expectedWindowTitle: "Chat",
            currentWindowTitle: "Chat",
            elementMatches: true,
            isEditable: true,
            expiresAt: now.addingTimeInterval(60),
            now: now
        ) == .changed)
        precondition(RemoteTargetValidationPolicy.evaluate(
            expectedPID: 42,
            currentPID: 42,
            expectedBundleIdentifier: "test.app",
            currentBundleIdentifier: "test.app",
            expectedWindowTitle: "Chat",
            currentWindowTitle: "Other",
            elementMatches: false,
            isEditable: true,
            expiresAt: now.addingTimeInterval(60),
            now: now
        ) == .changed)
        precondition(RemoteTargetValidationPolicy.evaluate(
            expectedPID: 42,
            currentPID: 42,
            expectedBundleIdentifier: "test.app",
            currentBundleIdentifier: "test.app",
            expectedWindowTitle: "Chat",
            currentWindowTitle: "Chat",
            elementMatches: true,
            isEditable: true,
            expiresAt: now,
            now: now
        ) == .expired)

        let execute = RemoteMessage(
            kind: .executeRequest,
            action: .pasteAndSubmit,
            text: "測試文字",
            targetSessionID: target.sessionID
        )
        let executeDecoded = try RemoteMessageCodec.decode(
            RemoteMessage.self,
            from: RemoteMessageCodec.encode(execute)
        )
        precondition(executeDecoded.action == .pasteAndSubmit)
        precondition(executeDecoded.text == "測試文字")

        let unknownAction = Data("{\"protocolVersion\":1,\"id\":\"x\",\"kind\":\"executeRequest\",\"action\":\"deleteEverything\"}".utf8)
        precondition(
            (try? RemoteMessageCodec.decode(RemoteMessage.self, from: unknownAction)) == nil,
            "Unknown remote actions must be rejected"
        )

        print("Remote protocol tests passed")
    }
}
