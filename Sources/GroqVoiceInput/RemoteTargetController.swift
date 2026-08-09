import AppKit
import ApplicationServices

final class RemoteTargetController {
    var onTargetChange: ((String) -> Void)?

    private struct LockedTarget {
        let descriptor: RemoteTargetDescriptor
        let pid: pid_t
        let bundleIdentifier: String
        let element: AXUIElement
    }

    private enum TargetError: Error {
        case accessibilityDenied
        case noEditableTarget
        case targetChanged
        case targetExpired

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

    private var lockedTarget: LockedTarget?
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
            let target = try captureTarget()
            lockedTarget = target
            onTargetChange?("已鎖定：\(target.descriptor.displayName)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
                guard self?.lockedTarget?.descriptor.sessionID == target.descriptor.sessionID else { return }
                self?.clearTarget()
            }
            _ = send(RemoteMessage(
                kind: .targetResponse,
                replyTo: request.id,
                target: target.descriptor,
                targetSessionID: target.descriptor.sessionID
            ))
        } catch let error as TargetError {
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

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)

        do {
            let target = try validateTarget(sessionID: requestedSessionID)
            postKey(virtualKey: 9, flags: .maskCommand)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                guard let self else { return }
                if action.submits {
                    do {
                        _ = try self.validateTarget(sessionID: target.descriptor.sessionID)
                        self.postKey(virtualKey: 36, flags: [])
                        self.clearTarget()
                        self.sendResult(
                            for: request,
                            payload: .init(success: true, code: .submitted, message: "文字已貼上並送出。"),
                            send: send
                        )
                    } catch let error as TargetError {
                        self.clearTarget()
                        self.sendResult(for: request, payload: error.result, send: send)
                    } catch {
                        self.clearTarget()
                        self.sendResult(
                            for: request,
                            payload: .init(success: false, code: .internalError, message: "文字已保留在剪貼簿，但無法確認送出。"),
                            send: send
                        )
                    }
                } else {
                    self.clearTarget()
                    self.sendResult(
                        for: request,
                        payload: .init(success: true, code: .pasted, message: "文字已貼到 Mac，沒有送出。"),
                        send: send
                    )
                }
            }
        } catch let error as TargetError {
            clearTarget()
            sendResult(for: request, payload: error.result, send: send)
        } catch {
            clearTarget()
            sendResult(
                for: request,
                payload: .init(success: false, code: .internalError, message: "文字已保留在剪貼簿，但 Mac 無法執行操作。"),
                send: send
            )
        }
    }

    private func captureTarget() throws -> LockedTarget {
        guard AXIsProcessTrusted() else { throw TargetError.accessibilityDenied }
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let element = focusedElement(),
              isEditable(element) else { throw TargetError.noEditableTarget }

        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element, &elementPID) == .success,
              elementPID == frontmost.processIdentifier else { throw TargetError.noEditableTarget }

        let windowTitle = focusedWindowTitle(pid: elementPID) ?? ""
        let appName = frontmost.localizedName ?? "Mac App"
        let bundleIdentifier = frontmost.bundleIdentifier ?? ""
        let descriptor = RemoteTargetDescriptor(
            sessionID: UUID().uuidString,
            macName: Host.current().localizedName ?? "Mac",
            appName: appName,
            windowTitle: windowTitle,
            expiresAt: Date().addingTimeInterval(300)
        )
        return LockedTarget(
            descriptor: descriptor,
            pid: elementPID,
            bundleIdentifier: bundleIdentifier,
            element: element
        )
    }

    private func validateTarget(sessionID: String) throws -> LockedTarget {
        guard AXIsProcessTrusted() else { throw TargetError.accessibilityDenied }
        guard let lockedTarget,
              lockedTarget.descriptor.sessionID == sessionID else { throw TargetError.targetChanged }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let currentElement = focusedElement()
        let failure = RemoteTargetValidationPolicy.evaluate(
            expectedPID: lockedTarget.pid,
            currentPID: frontmost?.processIdentifier,
            expectedBundleIdentifier: lockedTarget.bundleIdentifier,
            currentBundleIdentifier: frontmost?.bundleIdentifier ?? "",
            expectedWindowTitle: lockedTarget.descriptor.windowTitle,
            currentWindowTitle: focusedWindowTitle(pid: lockedTarget.pid) ?? "",
            elementMatches: currentElement.map { CFEqual($0, lockedTarget.element) } ?? false,
            isEditable: currentElement.map(isEditable) ?? false,
            expiresAt: lockedTarget.descriptor.expiresAt
        )
        switch failure {
        case .expired: throw TargetError.targetExpired
        case .changed: throw TargetError.targetChanged
        case nil: break
        }
        return lockedTarget
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value else { return nil }
        return (value as! AXUIElement)
    }

    private func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let windowValue else { return nil }
        let window = windowValue as! AXUIElement
        return stringAttribute(kAXTitleAttribute, from: window)
    }

    private func isEditable(_ element: AXUIElement) -> Bool {
        let subrole = stringAttribute(kAXSubroleAttribute, from: element)
        guard subrole != "AXSecureTextField" else { return false }

        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        )
        guard result == .success, settable.boolValue else { return false }

        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        return ["AXTextField", "AXTextArea", "AXComboBox"].contains(role)
            || role.localizedCaseInsensitiveContains("text")
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func postKey(virtualKey: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
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
