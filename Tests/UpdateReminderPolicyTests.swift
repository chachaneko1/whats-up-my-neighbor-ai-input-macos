import Foundation

@main
struct UpdateReminderPolicyTests {
    static func main() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("update.json")
        let diagnostics = UpdateDiagnostics(url: output)
        for _ in 0..<140 { diagnostics.record(.notificationQueued, succeeded: true) }
        let entries = try! JSONDecoder().decode([UpdateDiagnostics.Entry].self, from: Data(contentsOf: output))
        precondition(entries.count == 128 && entries.allSatisfy { $0.succeeded == true })
        let attributes = try! FileManager.default.attributesOfItem(atPath: output.path)
        precondition((attributes[.posixPermissions] as! NSNumber).intValue == 0o600)

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
