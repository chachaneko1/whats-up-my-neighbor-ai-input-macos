import AppKit
import ApplicationServices
import Carbon

enum TextInsertionCopyReason: Equatable {
    case accessibilityDenied
    case noEditableTarget
    case targetChanged
    case targetExpired
    case noTarget
    case eventUnavailable

    init(_ error: FocusTargetError) {
        switch error {
        case .accessibilityDenied: self = .accessibilityDenied
        case .noEditableTarget: self = .noEditableTarget
        case .targetChanged: self = .targetChanged
        case .targetExpired: self = .targetExpired
        }
    }
}

enum TextInsertionResult: Equatable {
    case copiedOnly(TextInsertionCopyReason)
    /// The system accepted the keyboard events; the destination has not acknowledged insertion.
    case pasteEventPosted
    case copyFailed
}

/// Local insertion posts Cmd+V only. Submission remains an explicit relay action.
final class TextInsertionService {
    struct Environment {
        var copyText: (String) -> Bool
        var postPasteEvent: () -> Bool

        static var system: Environment {
            Environment(
                copyText: { text in
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    return pasteboard.setString(text, forType: .string)
                },
                postPasteEvent: {
                    if PasteDiagnostics.shared.isEnabled {
                        PasteDiagnostics.shared.record(.init(
                            tag: .postPreparation, postEventPermission: CGPreflightPostEventAccess(),
                            modifierFlags: CGEventSource.flagsState(.combinedSessionState).rawValue,
                            secureEventInputEnabled: IsSecureEventInputEnabled()
                        ))
                    }
                    let source = CGEventSource(stateID: .combinedSessionState)
                    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
                    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
                    PasteDiagnostics.shared.record(.init(tag: .postCreation, eventSourceCreated: source != nil,
                                                          keyDownCreated: keyDown != nil, keyUpCreated: keyUp != nil))
                    guard let keyDown, let keyUp else { return false }
                    // 系統按鍵合成細節（virtualKey 9 代表 ANSI 鍵盤的 'V'）：
                    // 1. keyDown 必須包含 .maskCommand 以構成 ⌘V 組合鍵。
                    // 2. keyUp 必須將 flags 清空為 []。
                    // 容易誤用之處：若 keyUp 仍帶著 .maskCommand，macOS 的事件系統可能殘留修飾鍵狀態
                    // （Sticky Modifier），導致使用者後續的單鍵按壓（如方向鍵或選單快捷手勢）被誤判為 Command 組合鍵。
                    keyDown.flags = .maskCommand
                    // Release the synthesized modifier state after paste; leaving
                    // Command on key-up can make the next history choice wait.
                    keyUp.flags = []
                    keyDown.post(tap: .cghidEventTap)
                    keyUp.post(tap: .cghidEventTap)
                    // CGEvent.post has no destination acknowledgement or success result.
                    PasteDiagnostics.shared.record(.init(tag: .postCompleted))
                    return true
                }
            )
        }
    }

    private let focusTargets: FocusTargetService
    private let environment: Environment

    init(focusTargets: FocusTargetService = FocusTargetService(), environment: Environment = .system) {
        self.focusTargets = focusTargets
        self.environment = environment
    }

    func insert(
        _ text: String,
        target: FocusTarget?,
        captureFailure: FocusTargetError? = nil
    ) -> TextInsertionResult {
        PasteDiagnostics.shared.record(.init(tag: .insertion, hasTarget: target != nil,
                                              captureFailure: captureFailure?.diagnosticFailure))
        // 核心安全條件（保全使用者輸入）：
        // 無論目標驗證是否通過、權限是否缺失或目標是否已逾時，第一步必須無條件將文字寫入剪貼簿。
        // 語音輸入耗費使用者說話時間，絕不能因焦點失效而遺失；只要剪貼簿已寫入，
        // 即使後續因安全考量拒絕自動發送 ⌘V，使用者也能隨時手動貼上。
        // Preserve the transcript even when permission, expiry, or a focus change blocks insertion.
        guard environment.copyText(text) else {
            PasteDiagnostics.shared.record(.init(tag: .insertionResult, failure: .copyFailed, copySucceeded: false))
            return .copyFailed
        }
        guard let target else {
            PasteDiagnostics.shared.record(.init(tag: .insertionResult,
                                                  failure: captureFailure?.diagnosticFailure ?? .noTarget,
                                                  copySucceeded: true))
            return .copiedOnly(captureFailure.map(TextInsertionCopyReason.init) ?? .noTarget)
        }
        // 焦點目標驗證與安全防護：
        // 語音轉錄耗時數秒，使用者在此期間可能切換了視窗（如切換到終端機或敏感通訊軟體）。
        // 必須嚴格驗證當前焦點與錄音發起時的快照（PID、Window ID、Role）完全一致。
        // 容易誤用之處：切勿為了追求貼上成功率而跳過驗證；若目標改變卻強行貼上，
        // 可能造成敏感文字洩漏至公開視窗，或在終端機中執行非預期的危險指令。
        do {
            try focusTargets.validateTarget(target)
        } catch let error as FocusTargetError {
            PasteDiagnostics.shared.record(.init(tag: .insertionResult, failure: error.diagnosticFailure,
                                                  copySucceeded: true))
            return .copiedOnly(TextInsertionCopyReason(error))
        } catch {
            PasteDiagnostics.shared.record(.init(tag: .insertionResult, failure: .targetChanged, copySucceeded: true))
            return .copiedOnly(.targetChanged)
        }
        let posted = environment.postPasteEvent()
        PasteDiagnostics.shared.record(.init(tag: .insertionResult,
                                              failure: posted ? nil : .eventUnavailable,
                                              copySucceeded: true, postEventReturned: posted))
        guard posted else { return .copiedOnly(.eventUnavailable) }
        return .pasteEventPosted
    }
}
