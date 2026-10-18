import AppKit

@main
struct PreviewTests {
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
        var world = DesktopPetWorld(areas: [area], cursor: CGPoint(x: 50, y: 600), idleSeconds: 0)
        var model = DesktopPetModel(seed: 42)
        model.setReleased(true, now: 0, world: world)
        let initial = model.origin
        for step in 1...20 {
            world.cursor = CGPoint(x: CGFloat(step * 43), y: CGFloat(step * 29))
            model.tick(now: Double(step) / 4, world: world)
            expect(model.origin == initial && model.pose == .sitting, "moving mouse cannot attract or animate the cat")
            expect(model.visible, "moving mouse cannot hide the clickable cat")
        }
        let grip = CGPoint(x: model.origin.x + 50, y: model.origin.y + 70)
        model.pointerDown(at: grip, now: 6, world: world)
        model.pointerDragged(to: CGPoint(x: grip.x + 2, y: grip.y + 1), now: 6.1, world: world)
        expect(model.isPressed && !model.isDragging && model.origin == initial, "small click jitter is not a drag")
        model.pointerUp(now: 6.2, world: world)
        expect(model.pose == .petted && !model.isPressed, "only mouse-up completes a click")
        model.tick(now: 6.8, world: world)
        expect(model.pose == .petted && model.phase > 0, "click response remains visible despite active mouse")
        model.tick(now: 8, world: world)
        expect(model.pose == .sitting && model.origin == initial, "click response expires without moving the cat")

        model.pointerDown(at: grip, now: 9, world: world)
        model.pointerDragged(to: CGPoint(x: grip.x - 240, y: grip.y + 180), now: 9.1, world: world)
        let dragged = model.origin
        expect(model.pose == .carried && model.isDragging, "crossing drag threshold picks cat up")
        expect(dragged == CGPoint(x: initial.x - 240, y: initial.y + 180), "drag preserves exact grab offset")
        model.tick(now: 9.4, world: world)
        expect(model.origin == dragged && model.pose == .carried, "autonomous movement cannot interrupt a held cat")
        model.pointerUp(now: 9.5, world: world)
        expect(model.pose == .sitting && !model.isDragging && model.origin == dragged, "drop sits at release position without click response")
        model.pointerDragged(to: .zero, now: 9.6, world: world)
        expect(model.origin == dragged, "mouse move after release cannot drag or chase")
        model.pointerUp(now: 9.7, world: world)
        expect(model.pose == .sitting, "duplicate mouse-up is ignored")

        let again = CGPoint(x: model.frame.midX, y: model.frame.midY)
        model.pointerDown(at: again, now: 10, world: world)
        model.pointerDragged(to: CGPoint(x: 9000, y: 9000), now: 10.1, world: world)
        expect(area.contains(model.frame), "drag clamps the whole cat within a display")
        world.hidden = true
        model.tick(now: 10.2, world: world)
        expect(!model.visible && !model.isPressed && !model.isDragging, "lock or suspension cancels an active drag")
        model.pointerUp(now: 10.3, world: world)
        expect(model.pose != .petted, "cancelled drag cannot produce a delayed click")
        world.hidden = false
        model.tick(now: 10.4, world: world)
        model.pointerDown(at: again, now: 11, world: world)
        model.setReleased(false, now: 11.1, world: world)
        expect(!model.visible && !model.isPressed && !model.isDragging, "recall cancels interaction")
        model.pointerUp(now: 11.2, world: world)
        expect(!model.visible, "recall cannot be undone by late release")

        world.areas.append(CGRect(x: -1400, y: -200, width: 1400, height: 900))
        model.setReleased(true, now: 12, world: world)
        model.pointerDown(at: CGPoint(x: model.frame.midX, y: model.frame.midY), now: 12.1, world: world)
        model.pointerDragged(to: CGPoint(x: -500, y: 400), now: 12.2, world: world)
        expect(world.areas[1].contains(model.frame), "drag crosses into a negative-origin monitor")
        model.pointerUp(now: 12.3, world: world)
        world.areas = [area]
        model.tick(now: 12.4, world: world)
        expect(area.contains(model.frame), "display removal recovers a dropped cat")

        world = DesktopPetWorld(areas: [area], cursor: CGPoint(x: 20, y: 600), idleSeconds: 30)
        model = DesktopPetModel(seed: 42)
        model.setReleased(true, now: 0, world: world)
        var poses = Set<DesktopPetPose>()
        for step in 0...3000 {
            model.tick(now: Double(step) / 4, world: world)
            poses.insert(model.pose)
            expect(area.contains(model.frame), "idle animation stays within bounds")
        }
        expect(poses.contains(.grooming) && poses.contains(.walking) && poses.contains(.sleeping), "idle reaches washing, walking and sleep")
        expect(!poses.contains(.petted) && !poses.contains(.carried), "idle cannot pretend the user interacted")

        // Cursor-independent seeded destinations while idle: no pursuit, even
        // when the user moves the pointer around the cat's own frame.
        var other = DesktopPetModel(seed: 42)
        model = DesktopPetModel(seed: 42)
        model.setReleased(true, now: 0, world: world)
        other.setReleased(true, now: 0, world: world)
        for step in 1...200 {
            let now = Double(step) / 4
            model.tick(now: now, world: world)
            var shifted = world
            shifted.cursor = CGPoint(x: CGFloat(step % 10) * 90, y: CGFloat(step % 7) * 90)
            other.tick(now: now, world: shifted)
            expect(model.origin == other.origin && model.pose == other.pose, "idle movement is independent of pointer position")
        }
        world.reduceMotion = true
        world.idleSeconds = 90
        model.tick(now: 51, world: world)
        expect(model.phase == 0 && !model.isTravelling, "reduce-motion disables autonomous movement")

        var testTime: Double = 0
        world = DesktopPetWorld(areas: [area], cursor: CGPoint(x: 10, y: 600), idleSeconds: 0)
        var buttons = 1
        let controller = DesktopPetController(resources: resources, automatic: false, world: { world },
                                             clock: { testTime }, pressedButtons: { buttons })
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let key = NSApp.keyWindow, main = NSApp.mainWindow
        controller.setReleased(true)
        expect(!controller.panel.canBecomeKey && !controller.panel.canBecomeMain, "pet panel cannot take keyboard focus")
        expect(controller.panel.styleMask.contains(.nonactivatingPanel), "pet panel is nonactivating")
        let frame = controller.model.frame
        controller.updateHitRegion(at: CGPoint(x: frame.minX + 1, y: frame.minY + 1))
        expect(controller.panel.ignoresMouseEvents, "transparent padding passes mouse events through")
        controller.updateHitRegion(at: CGPoint(x: frame.minX + 64, y: frame.minY + 65))
        expect(!controller.panel.ignoresMouseEvents, "cat body accepts an intentional click")
        controller.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY))
        testTime = 0.1
        controller.pointerUp()
        expect(controller.model.pose == .petted, "controller forwards completed click")
        expect(NSApp.keyWindow === key && NSApp.mainWindow === main &&
               NSWorkspace.shared.frontmostApplication?.processIdentifier == front, "click callback preserves foreground and typing target")
        controller.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY))
        controller.pointerDragged(to: CGPoint(x: frame.midX - 100, y: frame.midY + 100))
        expect(controller.model.isDragging, "native controller forwards dragging")
        buttons = 0
        testTime = 0.2
        controller.refresh()
        expect(!controller.model.isDragging && controller.model.pose == .sitting, "lost mouse-up recovers on next tick without click")
        let finalOrigin = controller.model.origin
        controller.pointerDragged(to: .zero)
        expect(controller.model.origin == finalOrigin, "late drag after recovered release is ignored")
        controller.demonstrate(.walking)
        expect(controller.model.pose == .walking, "walk preview starts with a walking pose, not a sliding sitting pose")
        controller.suspend(true)
        expect(!controller.panel.isVisible && controller.panel.ignoresMouseEvents, "suspended panel is invisible and cannot block clicks")
        controller.suspend(false)
        controller.setReleased(false)
        expect(!controller.panel.isVisible, "recalled preview panel stays hidden")
        controller.dispose()

        let view = DesktopPetView(resources: resources)
        expect(!view.containsCat(CGPoint(x: 1, y: 1)), "alpha mask rejects transparent padding")
        expect(view.containsCat(CGPoint(x: 64, y: 63)), "alpha mask accepts central body")
        expect(view.renderPNG(pose: .carried, phase: 0) == view.renderPNG(pose: .sitting, phase: 0),
               "pickup starts from the original sitting image without a double silhouette")

        world = DesktopPetWorld(areas: [area], idleSeconds: 0)
        model = DesktopPetModel(seed: 42)
        model.setReleased(true, now: 0, world: world)
        let pickup = CGPoint(x: model.frame.midX, y: model.frame.midY)
        model.pointerDown(at: pickup, now: 0, world: world)
        model.pointerDragged(to: CGPoint(x: pickup.x - 40, y: pickup.y + 10), now: 0.1, world: world)
        expect(model.carryLean < 0 && model.carryLean >= -5, "left drag creates bounded side-body inertia")
        let tilt = abs(model.carryLean)
        for i in 1...10 { model.tick(now: 0.1 + Double(i) / 24, world: world) }
        expect(abs(model.carryLean) < tilt * 0.1, "held still settles quickly instead of swaying forever")
        model.pointerUp(now: 0.6, world: world)
        expect(model.isSettling && model.carryLean == 0, "drop starts a bounded settle and clears carried tilt")
        world.hidden = true
        model.tick(now: 0.7, world: world)
        expect(!model.isSettling, "suspension cancels landing feedback")
        world.hidden = false; world.reduceMotion = true
        model.setReleased(true, now: 1, world: world)
        model.pointerDown(at: pickup, now: 1, world: world)
        model.pointerDragged(to: CGPoint(x: pickup.x - 40, y: pickup.y + 10), now: 1.1, world: world)
        expect(model.isDragging && model.carryLean == 0 && model.phase == 0, "reduce motion keeps explicit dragging without secondary movement")
        view.reduceMotion = true
        expect(view.renderPNG(pose: .carried, phase: 0) == view.renderPNG(pose: .carried, phase: 1),
               "reduce motion has one static carried image with no arrival or sway")
        model.pointerUp(now: 1.2, world: world)
        expect(!model.isSettling, "reduce motion disables drop compression")
        view.reduceMotion = false

        for pose in DesktopPetPose.allCases {
            for frame in 0..<24 {
                let phase = Double(frame) / 12
                let image = view.renderPNG(pose: pose, phase: phase, walkDistance: CGFloat(frame) * 3.5)
                expect(image.count > 1400, "each pose renders nonempty")
                try image.write(to: output.appendingPathComponent("\(pose.rawValue)-\(String(format: "%02d", frame)).png"))
            }
        }

        // Export one complete gesture through the same model used by the App.
        // All positions are synthetic fixture coordinates, never user input.
        world = DesktopPetWorld(areas: [area], idleSeconds: 0)
        model = DesktopPetModel(seed: 42)
        model.setReleased(true, now: 0, world: world)
        let start = model.origin
        let startGrip = CGPoint(x: model.frame.midX, y: model.frame.midY)
        var frames: [[String: Any]] = []
        for i in 0..<96 {
            let now = Double(i) / 24
            if i == 8 { model.pointerDown(at: startGrip, now: now, world: world) }
            if (9...60).contains(i) {
                let p = Double(i - 9) / 51
                model.pointerDragged(to: CGPoint(x: startGrip.x - 180 * sin(p * .pi / 2),
                                                  y: startGrip.y + 100 * sin(p * .pi * 0.7)), now: now, world: world)
            }
            if i == 72 { model.pointerUp(now: now, world: world) }
            model.tick(now: now, world: world)
            expect(abs(model.carryLean) <= 5 && area.contains(model.frame), "scripted gesture stays bounded")
            view.update(model, reduceMotion: false)
            let image = view.renderPNG(pose: model.pose, phase: model.phase, carryLean: model.carryLean,
                                       isSettling: model.isSettling)
            let file = String(format: "pickup-r2-%03d.png", i)
            try image.write(to: output.appendingPathComponent(file))
            frames.append(["file": file, "pose": model.pose.rawValue,
                           "x": model.origin.x - start.x, "y": model.origin.y - start.y,
                           "phase": model.phase, "lean": model.carryLean, "settling": model.isSettling])
        }
        let data = try JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("pickup-r2-gesture.json"))
        print("Interaction preview: \(checks) checks passed; ten native poses rendered.")
    }
}
