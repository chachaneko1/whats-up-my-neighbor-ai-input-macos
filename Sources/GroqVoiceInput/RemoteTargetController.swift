import AppKit
import ApplicationServices

final class RemoteTargetController {
    struct Environment {
        var schedule: (TimeInterval, @escaping () -> Void) -> Void
        var postSubmitEvent: () -> Bool

        static var system: Environment {
            Environment(
                schedule: { delay, action in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
                },
                postSubmitEvent: { RemoteTargetController.postSubmitEvent() }
            )
        }
    }

    var onTargetChange: ((String) -> Void)?

    private let focusTargets: FocusTargetService
    private let textInsertion: TextInsertionService
    private let environment: Environment
    private var lockedTarget: FocusTarget?

    init(
        focusTargets: FocusTargetService = FocusTargetService(),
        textInsertion: TextInsertionService? = nil,
        environment: Environment = .system
    ) {
        self.focusTargets = focusTargets
        self.textInsertion = textInsertion ?? TextInsertionService(focusTargets: focusTargets)
        self.environment = environment
    }

    private var processedRequestIDs = Set<String>()

    func handle(_ message: RemoteMessage, send: @escaping (RemoteMessage) -> Bool) {
        guard RemoteProtocolPolicy.supports(message.protocolVersion) else {
            sendResult(
                for: message,
                payload: .init(success: false, code: .unsupportedVersion, message: "iPhone 與 Mac App 版本不相容，請更新兩端。"),
                send: send
            )
            return
        }

        guard processedRequestIDs.insert(message.id).inserted else { return }
        if processedRequestIDs.count > 200 { processedRequestIDs.removeAll(keepingCapacity: true) }

        switch message.kind {
        case .targetRequest:
            handleTargetRequest(message, send: send)
        case .executeRequest:
            handleExecuteRequest(message, send: send)
        case .cancelRequest:
            clearTarget()
            sendResult(
                for: message,
                payload: .init(success: true, code: .cancelled, message: "已取消這次遠端輸入。"),
                send: send
            )
        case .targetResponse, .result:
            sendResult(
                for: message,
                payload: .init(success: false, code: .invalidRequest, message: "Mac 收到不適用的訊息。"),
                send: send
            )
        }
    }

    func clearTarget() {
        lockedTarget = nil
        onTargetChange?("尚未鎖定輸入框")
    }

    private func handleTargetRequest(_ request: RemoteMessage, send: @escaping (RemoteMessage) -> Bool) {
        do {
            let target = try focusTargets.captureTarget(ttl: 300)
            lockedTarget = target
            onTargetChange?("已鎖定：\(target.remoteDescriptor.displayName)")
            environment.schedule(300) { [weak self] in
                guard self?.lockedTarget?.remoteDescriptor.sessionID == target.remoteDescriptor.sessionID else { return }
                self?.clearTarget()
            }
            _ = send(RemoteMessage(
                kind: .targetResponse,
                replyTo: request.id,
                target: target.remoteDescriptor,
                targetSessionID: target.remoteDescriptor.sessionID
            ))
        } catch let error as FocusTargetError {
            clearTarget()
            sendResult(for: request, payload: error.result, send: send)
        } catch {
            clearTarget()
            sendResult(
                for: request,
                payload: .init(success: false, code: .internalError, message: "Mac 無法讀取目前輸入目標。"),
                send: send
            )
        }
    }

    private func handleExecuteRequest(_ request: RemoteMessage, send: @escaping (RemoteMessage) -> Bool) {
        let trimmed = request.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let action = request.action,
              action == .paste || action == .pasteAndSubmit,
              !trimmed.isEmpty,
              trimmed.count <= 100_000,
              let requestedSessionID = request.targetSessionID else {
            sendResult(
                for: request,
                payload: .init(success: false, code: .invalidRequest, message: "遠端文字或動作無效。"),
                send: send
            )
            return
        }

        let target = lockedTarget.flatMap { $0.sessionID == requestedSessionID ? $0 : nil }
        let insertion = textInsertion.insert(trimmed, target: target, captureFailure: .targetChanged)
        guard insertion == .pasteEventPosted, let target else {
            clearTarget()
            let payload: RemoteResultPayload
            switch insertion {
            case .copiedOnly(let reason):
                payload = result(for: reason)
            case .copyFailed:
                payload = .init(success: false, code: .internalError, message: "無法將文字放入 Mac 剪貼簿，尚未執行貼上。")
            case .pasteEventPosted:
                payload = FocusTargetError.targetChanged.result
            }
            sendResult(for: request, payload: payload, send: send)
            return
        }

        environment.schedule(0.28) { [weak self] in
            guard let self else { return }
            if action.submits {
                do {
                    guard self.lockedTarget?.sessionID == target.sessionID else {
                        throw FocusTargetError.targetChanged
                    }
                    try self.focusTargets.validateTarget(target)
                    guard self.environment.postSubmitEvent() else {
                        self.clearTarget(ifMatching: target.sessionID)
                        self.sendResult(
                            for: request,
                            payload: .init(success: false, code: .internalError, message: "文字已保留在剪貼簿，但無法發送送出按鍵。"),
                            send: send
                        )
                        return
                    }
                    self.clearTarget(ifMatching: target.sessionID)
                    self.sendResult(
                        for: request,
                        payload: .init(success: true, code: .submitted, message: "已發送貼上與送出按鍵，請確認 Mac 目標 App 的結果。"),
                        send: send
                    )
                } catch let error as FocusTargetError {
                    self.clearTarget(ifMatching: target.sessionID)
                    self.sendResult(for: request, payload: error.result, send: send)
                } catch {
                    self.clearTarget(ifMatching: target.sessionID)
                    self.sendResult(
                        for: request,
                        payload: .init(success: false, code: .internalError, message: "文字已保留在剪貼簿，但無法確認送出。"),
                        send: send
                    )
                }
            } else {
                self.clearTarget(ifMatching: target.sessionID)
                self.sendResult(
                    for: request,
                    payload: .init(success: true, code: .pasted, message: "已向 Mac 發送貼上按鍵，沒有送出；請確認目標 App 的結果。"),
                    send: send
                )
            }
        }
    }

    private func clearTarget(ifMatching sessionID: String) {
        guard lockedTarget?.sessionID == sessionID else { return }
        clearTarget()
    }

    private func result(for reason: TextInsertionCopyReason) -> RemoteResultPayload {
        switch reason {
        case .accessibilityDenied: return FocusTargetError.accessibilityDenied.result
        case .noEditableTarget: return FocusTargetError.noEditableTarget.result
        case .targetChanged, .noTarget: return FocusTargetError.targetChanged.result
        case .targetExpired: return FocusTargetError.targetExpired.result
        case .eventUnavailable:
            return .init(success: false, code: .internalError, message: "文字已保留在剪貼簿，但無法發送貼上按鍵。")
        }
    }

    private static func postSubmitEvent() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else { return false }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func sendResult(
        for request: RemoteMessage,
        payload: RemoteResultPayload,
        send: (RemoteMessage) -> Bool
    ) {
        _ = send(RemoteMessage(
            kind: .result,
            replyTo: request.id,
            targetSessionID: request.targetSessionID,
            result: payload
        ))
    }
}

private extension FocusTarget {
    var remoteDescriptor: RemoteTargetDescriptor {
        RemoteTargetDescriptor(
            sessionID: sessionID,
            macName: macName,
            appName: appName,
            windowTitle: windowTitle,
            expiresAt: expiresAt
        )
    }
}

private extension FocusTargetError {
    var result: RemoteResultPayload {
        switch self {
        case .accessibilityDenied:
            return .init(
                success: false,
                code: .accessibilityDenied,
                message: "Mac 尚未允許輔助使用，因此不能鎖定或控制輸入框。"
            )
        case .noEditableTarget:
            return .init(
                success: false,
                code: .noEditableTarget,
                message: "Mac 目前沒有可編輯的文字輸入框。請先點一下聊天輸入框。"
            )
        case .targetChanged:
            return .init(
                success: false,
                code: .targetChanged,
                message: "Mac 的 App、視窗或輸入框已改變，為避免誤送已取消操作。"
            )
        case .targetExpired:
            return .init(
                success: false,
                code: .targetExpired,
                message: "Mac 輸入目標已逾時，請重新開始一次錄音。"
            )
        }
    }
}
