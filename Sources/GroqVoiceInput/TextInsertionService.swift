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
                    keyDown.flags = .maskCommand
                    keyUp.flags = .maskCommand
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
