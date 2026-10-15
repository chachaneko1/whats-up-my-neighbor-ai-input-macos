import Foundation

@main
struct UpdateReminderPolicyTests {
    static func main() {
        var policy = UpdateReminderPolicy()
        precondition(policy.nextAction(isBusy: false, notificationsAllowed: true) == .none)
        policy.receive(version: "1.2.0")
        // Recording, finalization, upload, retry and modal UI share this gate.
        for _ in 0..<5 {
            precondition(policy.nextAction(isBusy: true, notificationsAllowed: true) == .none)
        }
        precondition(policy.nextAction(isBusy: false, notificationsAllowed: true) == .notify)
        precondition(policy.nextAction(isBusy: false, notificationsAllowed: true) == .none)
        policy.receive(version: "1.2.0")
        precondition(policy.nextAction(isBusy: false, notificationsAllowed: true) == .none)
        policy.requestPresentation()
        precondition(policy.nextAction(isBusy: true, notificationsAllowed: true) == .none)
        precondition(policy.nextAction(isBusy: false, notificationsAllowed: true) == .showUpdate)
        precondition(policy.nextAction(isBusy: false, notificationsAllowed: true) == .none)
        policy.receive(version: "1.3.0")
        precondition(policy.nextAction(isBusy: false, notificationsAllowed: false) == .showUpdate)
        precondition(policy.nextAction(isBusy: false, notificationsAllowed: false) == .none)
        policy.clear()
        precondition(policy.version == nil)
        precondition(policy.nextAction(isBusy: false, notificationsAllowed: true) == .none)
        policy.requestPresentation()
        precondition(policy.nextAction(isBusy: true, notificationsAllowed: false) == .none)
        precondition(policy.nextAction(isBusy: false, notificationsAllowed: false) == .showUpdate)
        policy.clear()
        policy.requestPresentation()
        policy.receive(version: "2.0.0")
        precondition(policy.nextAction(isBusy: false, notificationsAllowed: true) == .showUpdate)
        print("Update reminder policy passed: idle deferral, notification denial, deduplication, manual choice and session cleanup")
    }
}
