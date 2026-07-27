import Foundation

enum RemoteTargetValidationFailure: Equatable {
    case expired
    case changed
}

enum RemoteTargetValidationPolicy {
    static func evaluate(
        expectedPID: pid_t,
        currentPID: pid_t?,
        expectedBundleIdentifier: String,
        currentBundleIdentifier: String?,
        expectedWindowTitle: String,
        currentWindowTitle: String?,
        elementMatches: Bool,
        isEditable: Bool,
        expiresAt: Date,
        now: Date = Date()
    ) -> RemoteTargetValidationFailure? {
        guard expiresAt > now else { return .expired }
        guard currentPID == expectedPID,
              currentBundleIdentifier == expectedBundleIdentifier,
              currentWindowTitle == expectedWindowTitle,
              elementMatches,
              isEditable else { return .changed }
        return nil
    }
}
