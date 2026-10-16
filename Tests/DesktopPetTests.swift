import AppKit

@main
struct DesktopPetTests {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        let area = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let folder = DesktopPetPerch(id: "fixture-folder", frame: CGRect(x: 430, y: 180, width: 70, height: 70))
        var world = DesktopPetWorld(areas: [area], perches: [folder], cursor: CGPoint(x: 30, y: 600), idleSeconds: 30)
        var model = DesktopPetModel(seed: 42)
        model.tick(now: 0, world: world)
        expect(!model.visible && !model.released, "off by default")
        model.setReleased(true, now: 0, world: world)
        var poses = Set<DesktopPetPose>()
        var perched = false, moving = false
        for step in 0...4000 {
            model.tick(now: Double(step) / 4, world: world)
            expect(area.insetBy(dx: -0.01, dy: -0.01).contains(model.frame), "entire pet stays on its display")
            poses.insert(model.pose)
            moving = moving || model.isTravelling
            if model.perchID == folder.id {
                perched = true
                expect(abs(model.frame.minY + DesktopPetModel.feetInset - folder.frame.maxY) < 0.01,
                       "feet contact the actual folder's top edge")
            }
        }
        expect(poses == Set(DesktopPetPose.allCases), "idle cycle reaches all seven poses")
        expect(perched && moving, "walks to a folder as well as the screen edge")

        // Removed/moved/occluded folder IDs must never strand the pet in mid-air.
        model = DesktopPetModel(seed: 42)
        model.setReleased(true, now: 0, world: world)
        var now: Double = 0
        while model.perchID == nil && now < 20 { now += 0.25; model.tick(now: now, world: world) }
        expect(model.perchID != nil, "fixture reaches perch")
        world.perches = []
        now += 0.25; model.tick(now: now, world: world)
        expect(model.perchID == nil && model.origin.y == area.minY, "lost perch returns to edge")
        world.idleSeconds = 0
        model.tick(now: now + 0.25, world: world)
        let quiet = model.origin
        for step in 1...20 { model.tick(now: now + Double(step), world: world) }
        expect(model.pose == .sitting && model.origin == quiet && !model.isTravelling, "active typing keeps it still")
        world.cursor = CGPoint(x: model.frame.midX, y: model.frame.midY)
        model.tick(now: now + 21, world: world)
        expect(!model.visible, "uncovers icons close to the active pointer")
        world.cursor = CGPoint(x: 10, y: 650)
        world.idleSeconds = 90; world.reduceMotion = true
        for step in 22...50 { model.tick(now: now + Double(step), world: world) }
        expect(model.visible && model.pose == .sleeping && model.origin == quiet && model.phase == 0,
               "Reduce Motion disables walking and breathing")
        world.hidden = true
        model.tick(now: now + 51, world: world)
        expect(!model.visible, "busy/full-screen/locked world hides pet")
        world.hidden = false; world.reduceMotion = false
        model.tick(now: now + 5000, world: world)
        expect(model.visible && !model.isTravelling && model.pose == .sitting, "wake skips elapsed animations")
        model.setReleased(false, now: now + 5001, world: world)
        model.tick(now: now + 6000, world: world)
        expect(!model.visible && !model.isTravelling, "recall stays recalled")
        world.areas = [CGRect(x: -1440, y: -300, width: 1440, height: 900)]
        world.cursor = CGPoint(x: -200, y: 400)
        model.setReleased(true, now: 0, world: world)
        for step in 1...400 { model.tick(now: Double(step) / 4, world: world) }
        expect(world.areas[0].contains(model.frame), "negative-origin monitor supported")
        world.areas = [CGRect(x: 0, y: 0, width: 800, height: 600)]
        model.tick(now: 101, world: world)
        expect(world.areas[0].contains(model.frame), "display removal clamps to remaining screen")
        world.areas = [.zero]
        model.tick(now: 102, world: world)
        expect(!model.visible, "invalid display hides safely")
        expect(DesktopPetModel.appKitFrame(topLeft: CGRect(x: -100, y: 10, width: 60, height: 70), primaryScreenTop: 900)
               == CGRect(x: -100, y: 820, width: 60, height: 70), "AX top-left conversion")

        // Native window fixture: no API, recording, keyboard or user's files.
        world = DesktopPetWorld(areas: [area], cursor: CGPoint(x: 10, y: 600), idleSeconds: 0)
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let key = NSApp.keyWindow, main = NSApp.mainWindow
        let controller = DesktopPetController(resources: resources, world: { world })
        var busy = false
        controller.isBusy = { busy }
        controller.setReleased(true)
        expect(controller.testPanel.isVisible && controller.testTimerActive, "released native window runs")
        expect(controller.testPanel.ignoresMouseEvents, "clicks pass through")
        expect(!controller.testPanel.canBecomeKey && !controller.testPanel.canBecomeMain, "cannot take keyboard focus")
        expect(controller.testPanel.styleMask.contains(.nonactivatingPanel), "nonactivating panel")
        expect(NSApp.keyWindow === key && NSApp.mainWindow === main &&
               NSWorkspace.shared.frontmostApplication?.processIdentifier == front, "presentation preserves typing target")
        busy = true; controller.refresh()
        expect(!controller.testPanel.isVisible, "recording/modal/selection takes priority")
        busy = false; controller.refresh()
        expect(controller.testPanel.isVisible, "idle restores released pet")
        controller.testSuspend(true)
        expect(!controller.testPanel.isVisible && !controller.testTimerActive, "sleep/lock stops animation timer")
        controller.testSuspend(false)
        expect(controller.testPanel.isVisible, "wake restores a released pet")
        controller.setReleased(false)
        controller.testSuspend(true); controller.testSuspend(false)
        expect(!controller.testPanel.isVisible && !controller.testTimerActive, "recall has no timer, including after wake")
        controller.dispose()
        controller.setReleased(true)
        expect(!controller.testPanel.isVisible && !controller.testTimerActive, "disposed window cannot restart")

        let view = DesktopPetView(resources: resources)
        expect(view.loadedAssets.contains("sit") && view.loadedAssets.contains("walk") && view.loadedAssets.contains("reply"), "original artwork bundled")
        for pose in DesktopPetPose.allCases {
            let data = view.renderPNG(pose: pose, phase: pose == .yawning ? 1.6 : 0.55)
            expect(data.count > 1500, "native pose renders nonempty")
            try data.write(to: output.appendingPathComponent(pose.rawValue + ".png"))
        }
        let sheet = NSImage(size: CGSize(width: 896, height: 210), flipped: true) { _ in
            NSColor(srgbRed: 0.90, green: 0.91, blue: 0.89, alpha: 1).setFill()
            CGRect(x: 0, y: 0, width: 896, height: 210).fill()
            for (index, pose) in DesktopPetPose.allCases.enumerated() {
                let data = view.renderPNG(pose: pose, phase: pose == .yawning ? 1.6 : 0.55)
                NSImage(data: data)!.draw(in: CGRect(x: index * 128, y: 20, width: 128, height: 128),
                                          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                (pose.description as NSString).draw(at: CGPoint(x: index * 128 + 20, y: 166), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)])
            }
            return true
        }
        let bitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("poses.png"))
        print("Desktop pet: \(checks) checks passed; native pose renders saved.")
    }
}
