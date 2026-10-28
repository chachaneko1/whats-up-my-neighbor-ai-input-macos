import AppKit

@main
struct VPSCatWindowLifecycleTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let area = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let pet = DesktopPetController(resources: resources, automaticallyTicks: false,
            world: { DesktopPetWorld(areas: [area], cursor: .zero, idleSeconds: 0) }, pressedButtons: { 1 })
        pet.setReleased(true)
        let connection = VPSDesktopConnection()
        let controller = VPSDesktopWindowController(pet: pet, connection: connection)
        // Synthetic connection events exercise the real controller without opening SSH/VNC.
        connection.handle("connected")
        controller.present()
        let window = NSApp.windows.first { $0.title == "VPS 遠端桌面" }!
        let home = pet.model.origin
        var phase = "collapse"
        func park() {
            precondition(pet.parkInVPS())
            precondition(pet.remoteHosted && !pet.testPanel.isVisible)
        }
        func homeAgain() {
            precondition(!pet.remoteHosted && pet.testPanel.isVisible, "Failed recovery: \(phase), hosted=\(pet.remoteHosted), visible=\(pet.testPanel.isVisible), model=\(pet.model.visible)")
            precondition(pet.model.origin == home && !pet.model.isPressed)
        }
        // The original side-entry component must be reached through actual pet callbacks.
        pet.pointerDown(at: CGPoint(x: pet.model.frame.midX, y: pet.model.frame.midY))
        let edge = CGPoint(x: window.frame.minX - 5, y: window.frame.midY)
        pet.pointerDragged(to: edge)
        let hint = NSApp.windows.first { $0.title == "貓咪拖放提示" }!
        precondition(hint.isVisible && hint.ignoresMouseEvents && !hint.canBecomeKey && !hint.canBecomeMain)
        if let content = hint.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let output = resources.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("build/cat-render/vps-original-drop-hint.png")
            try bitmap.representation(using: .png, properties: [:])?.write(to: output)
        }
        pet.pointerUp(at: edge)
        precondition(pet.remoteHosted && !hint.isVisible, "The original visible entry zone must accept the drop")
        pet.returnFromVPS()
        homeAgain()
        park()
        controller.toggleCollapsed()
        homeAgain()
        controller.toggleCollapsed()
        park()
        phase = "disconnect"
        connection.handle("disconnected")
        homeAgain()
        connection.handle("connected")
        park()
        phase = "close"
        window.close()
        homeAgain()
        precondition(connection.connected, "Closing the window keeps the VNC connection")
        controller.present()
        park()
        phase = "minimize"
        // Command-line AppKit runners do not enter the Dock animation loop.
        // Exercise the delegate notification before the window becomes unavailable.
        controller.windowWillMiniaturize(Notification(name: NSWindow.willMiniaturizeNotification, object: window))
        homeAgain()
        window.deminiaturize(nil)
        park()
        // Explicitly recalling the pet must survive a later disconnect/reconnect.
        pet.setReleased(false)
        precondition(!pet.remoteHosted && !pet.model.released && !pet.testPanel.isVisible)
        connection.handle("disconnected")
        connection.handle("connected")
        precondition(!pet.model.released && !pet.testPanel.isVisible,
                     "Connection changes must not resurrect a pet the user recalled")
        pet.setReleased(true)
        for cancelByRecall in [true, false] {
            pet.pointerDown(at: CGPoint(x: pet.model.frame.midX, y: pet.model.frame.midY))
            pet.pointerDragged(to: edge)
            precondition(hint.isVisible)
            if cancelByRecall { pet.setReleased(false) }
            else { pet.testSuspend(true) }
            precondition(!hint.isVisible, "Cancelled drags must dismiss the original hint")
            pet.testSuspend(false)
            pet.setReleased(false)
            pet.setReleased(true)
        }
        park()
        phase = "shutdown"
        controller.shutdown()
        homeAgain()
        precondition(!connection.connected)
        controller.shutdown()
        pet.dispose()
        window.close()
        print("VPS cat window lifecycle passed: collapse, disconnect, close/reopen, minimize notification, idempotent shutdown; no network connection")
    }
}
