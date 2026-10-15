import Foundation

/// Pure reminder policy: learning about a release never authorizes installation.
struct UpdateReminderPolicy {
    enum Action: Equatable { case none, notify, showUpdate }
    private(set) var version: String?
    private var reminded = false
    private var presentationRequested = false

    mutating func receive(version: String) {
        guard self.version != version else { return }
        self.version = version
        reminded = false
    }

    mutating func requestPresentation() { presentationRequested = true }

    mutating func nextAction(isBusy: Bool, notificationsAllowed: Bool) -> Action {
        guard !isBusy else { return .none }
        if presentationRequested {
            presentationRequested = false
            reminded = true
            return .showUpdate
        }
        guard version != nil, !reminded else { return .none }
        reminded = true
        return notificationsAllowed ? .notify : .showUpdate
    }

    mutating func clear() { self = UpdateReminderPolicy() }
}
