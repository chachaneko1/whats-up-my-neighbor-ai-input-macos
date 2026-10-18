import AppKit
import Foundation

/// Offline UI tests and native AppKit PNG evidence. No audio, API, Accessibility
/// permissions, installation, or interaction with the user's applications.
@main
struct CatOverlayTests {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fputs("Usage: CatOverlayTests <neko-base.png> <render-directory>\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let asset = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("cat-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var checks = 0
        var failures = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            if !condition() { failures += 1; fputs("FAIL: \(message)\n", stderr) }
        }
        func configuration(_ json: String) throws -> CatConfiguration {
            let url = temporary.appendingPathComponent("configuration-\(UUID().uuidString).json")
            try Data(json.utf8).write(to: url)
            let result = CatConfiguration.load(from: url)
            expect(result.loadError == nil, "UI fixture configuration is valid: \(json)")
            return result
        }
        func pump(_ seconds: TimeInterval) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.02))) }
        }
        func sameRect(_ a: NSRect, _ b: NSRect) -> Bool {
            abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01 &&
            abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
        }

        let overlay = CatOverlay(configuration: .defaults, bundledImageURL: asset)
        defer { overlay.dispose() }
        expect(overlay.testCanReplaceMouth, "bundled cat supports the localized feline mouth")
        expect(overlay.testPanel.styleMask.contains(.nonactivatingPanel), "panel uses nonactivating style")
        expect(!overlay.testPanel.canBecomeKey, "panel cannot become key")
        expect(!overlay.testPanel.canBecomeMain, "panel cannot become main")
        expect(!overlay.testPanel.isOpaque, "panel is transparent")
        expect(!overlay.testPanel.hidesOnDeactivate, "overlay stays with the focused application")
        expect(overlay.testPanel.collectionBehavior.contains(.fullScreenAuxiliary), "panel supports full-screen spaces")

        let previousKey = app.keyWindow
        let previousMain = app.mainWindow
        let previousFront = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var cancels = 0, finishes = 0
        overlay.onCancel = { cancels += 1 }
        overlay.onFinish = { finishes += 1 }
        overlay.showRecording()
        expect(overlay.testPanel.isVisible, "recording overlay is visible")
        expect(!overlay.testMouthTimerActive && !overlay.testExpiryTimerActive, "recording has no animation or expiry timers")
        expect(app.keyWindow === previousKey && app.mainWindow === previousMain, "showing recording preserves key/main window")
        expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == previousFront, "showing recording does not activate the app")
        let cancelBefore = overlay.testCancelScreenRect
        let finishBefore = overlay.testFinishScreenRect
        overlay.testClickCancel()
        overlay.testClickFinish()
        expect(cancels == 1 && finishes == 1, "both recording eye actions work")
        expect(app.keyWindow === previousKey && app.mainWindow === previousMain, "eye actions preserve key/main window")

        let recording = try overlay.testPNG(greeting: false)
        let recordingLater = try overlay.testPNG(greeting: false, frame: 2)
        expect(recording == recordingLater, "normal recording mouth remains static")
        try recording.write(to: output.appendingPathComponent("recording-static.png"))
        expect(NSBitmapImageRep(data: recording)?.pixelsWide == 680, "native recording fixture is rendered at 2x")
        expect(NSBitmapImageRep(data: recording)?.pixelsHigh == 440, "native recording fixture has expected canvas")
        if let pixels = NSBitmapImageRep(data: recording) {
            var patch = [Int](repeating: 0, count: pixels.samplesPerPixel)
            var neighbor = patch
            pixels.getPixel(&patch, atX: 310, y: 260)
            pixels.getPixel(&neighbor, atX: 298, y: 260)
            expect(zip(patch.prefix(3), neighbor.prefix(3)).allSatisfy { pair in abs(pair.0 - pair.1) <= 3 },
                   "mouth reconstruction blends into neighboring dark pixels without a rectangle")
        }

        overlay.showGreeting()
        expect(overlay.testPanel.isVisible, "greeting overlay is visible")
        expect(overlay.testExpiryTimerActive, "greeting starts expiry timer")
        expect(overlay.testMouthTimerActive == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
               "greeting starts mouth timer unless macOS Reduce Motion is enabled")
        expect(sameRect(cancelBefore, overlay.testCancelScreenRect), "cancel eye stays in the same screen position")
        expect(sameRect(finishBefore, overlay.testFinishScreenRect), "finish eye stays in the same screen position")
        expect(app.keyWindow === previousKey && app.mainWindow === previousMain, "greeting preserves key/main window")
        expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == previousFront, "greeting does not activate the app")
        overlay.testClickCancel()
        overlay.testClickFinish()
        expect(cancels == 1 && finishes == 1, "greeting cannot accidentally invoke recording eye actions")
        // Observe the live timer before encoding 30 large PNGs. On a busy
        // machine those exports can outlast the entire three-second greeting.
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let deadline = Date().addingTimeInterval(1)
            while overlay.testMouthFrame < 1 && Date() < deadline { pump(0.02) }
            expect(overlay.testMouthFrame >= 1, "live run-loop advances the greeting mouth")
        }
        let closed = try overlay.testPNG(greeting: true, frame: 0)
        let open = try overlay.testPNG(greeting: true, frame: 2)
        expect(closed != open, "greeting changes the tiny mouth opening")
        expect(NSBitmapImageRep(data: open)?.pixelsWide == 880, "greeting expands canvas for the reply bubble")
        try closed.write(to: output.appendingPathComponent("greeting-closed.png"))
        try open.write(to: output.appendingPathComponent("greeting-open.png"))
        if let pixels = NSBitmapImageRep(data: open) {
            var sample = [Int](repeating: 0, count: pixels.samplesPerPixel)
            var pinkPixels = 0
            for y in 420..<455 {
                for x in 320..<360 {
                    pixels.getPixel(&sample, atX: x, y: y)
                    if sample.count >= 3 && sample[0] > sample[1] + 20 && sample[2] > sample[1] { pinkPixels += 1 }
                }
            }
            expect(pinkPixels >= 20, "open mouth has a tiny visible pink tongue")
        }
        for frame in 0..<30 {
            let data = try overlay.testPNG(greeting: true, frame: frame)
            try data.write(to: output.appendingPathComponent(String(format: "greeting-frame-%02d.png", frame)))
        }
        overlay.showRecording()
        expect(!overlay.testMouthTimerActive && !overlay.testExpiryTimerActive, "starting recording cancels both greeting timers")
        expect(overlay.testMouthFrame == 0, "starting recording restores neutral omega")
        expect(sameRect(cancelBefore, overlay.testCancelScreenRect), "recording restores original cancel target")
        expect(sameRect(finishBefore, overlay.testFinishScreenRect), "recording restores original finish target")
        overlay.showGreeting()
        overlay.hide()
        expect(!overlay.testPanel.isVisible, "hide removes panel")
        expect(!overlay.testMouthTimerActive && !overlay.testExpiryTimerActive, "hide stops both timers")
        expect(overlay.testMouthFrame == 0, "hide resets mouth")
        overlay.showGreeting()
        overlay.testPanel.orderOut(nil)
        expect(!overlay.testMouthTimerActive && !overlay.testExpiryTimerActive, "external panel orderOut also stops both timers")

        let short = CatOverlay(configuration: try configuration("{\"displaySeconds\":1}"), bundledImageURL: asset)
        var expired = 0
        short.onGreetingFinished = { expired += 1 }
        short.showGreeting()
        pump(1.2)
        expect(expired == 1 && !short.testPanel.isVisible, "greeting expires and dismisses exactly once")
        expect(!short.testMouthTimerActive && !short.testExpiryTimerActive, "expiry clears both timers")
        expect(short.testMouthFrame == 0, "expiry restores neutral mouth state")
        short.showRecording()
        pump(0.15)
        expect(short.testPanel.isVisible && expired == 1, "expired timers cannot hide a later recording")
        short.dispose()

        let still = CatOverlay(configuration: try configuration("{\"animateMouth\":false}"), bundledImageURL: asset)
        still.showGreeting()
        expect(!still.testMouthTimerActive && still.testExpiryTimerActive, "animateMouth=false disables only mouth motion")
        let stillZero = try still.testPNG(greeting: true, frame: 0)
        let stillTwo = try still.testPNG(greeting: true, frame: 2)
        expect(stillZero == stillTwo, "opted-out greeting is static")
        try stillZero.write(to: output.appendingPathComponent("greeting-reduced-motion.png"))
        still.dispose()

        try FileManager.default.copyItem(at: asset, to: temporary.appendingPathComponent("custom.png"))
        let customConfig = try configuration("{\"image\":\"custom.png\"}")
        let custom = CatOverlay(configuration: customConfig, bundledImageURL: asset)
        expect(!custom.testCanReplaceMouth, "custom PNG never receives a generic mouth")
        custom.showGreeting()
        expect(!custom.testMouthTimerActive, "custom PNG never starts mouth animation")
        let customZero = try custom.testPNG(greeting: true, frame: 0)
        let customTwo = try custom.testPNG(greeting: true, frame: 2)
        expect(customZero == customTwo, "custom PNG remains unchanged during greeting")
        try customZero.write(to: output.appendingPathComponent("greeting-custom-unchanged.png"))
        // A post-validation file replacement cannot change the immutable snapshot.
        try Data("not a PNG".utf8).write(to: temporary.appendingPathComponent("custom.png"))
        let snapshot = CatOverlay(configuration: customConfig, bundledImageURL: asset)
        let snapshotPNG = try snapshot.testPNG(greeting: true)
        expect(snapshotPNG == customZero, "custom image renders the validated immutable snapshot")
        snapshot.dispose()
        custom.dispose()

        let missing = CatOverlay(configuration: try configuration("{\"image\":\"missing.png\"}"), bundledImageURL: asset)
        expect(!missing.testCanReplaceMouth, "missing custom file also disables the generic mouth")
        missing.showGreeting()
        expect(!missing.testMouthTimerActive, "custom fallback never starts mouth animation")
        missing.dispose()

        let left = CatOverlay(configuration: try configuration("{\"bubblePosition\":\"upperLeft\",\"tiltDegrees\":10}"), bundledImageURL: asset)
        left.showRecording()
        let leftCancel = left.testCancelScreenRect
        let leftFinish = left.testFinishScreenRect
        left.showGreeting()
        expect(sameRect(leftCancel, left.testCancelScreenRect), "upper-left greeting preserves cancel target")
        expect(sameRect(leftFinish, left.testFinishScreenRect), "upper-left greeting preserves finish target")
        try left.testPNG(greeting: true, frame: 2).write(to: output.appendingPathComponent("greeting-upper-left.png"))
        left.dispose()

        let longReply = CatOverlay(configuration: try configuration("{\"reply\":\"你好，小黑貓在這裡陪你說話！Have a wonderful day, neighbor!\",\"fontSize\":28}"), bundledImageURL: asset)
        try longReply.testPNG(greeting: true, frame: 2).write(to: output.appendingPathComponent("greeting-long-reply.png"))
        longReply.dispose()

        overlay.showGreeting()
        overlay.dispose()
        expect(!overlay.testPanel.isVisible && !overlay.testMouthTimerActive && !overlay.testExpiryTimerActive,
               "dispose removes panel and invalidates both timers")
        overlay.showGreeting()
        overlay.showRecording()
        expect(!overlay.testPanel.isVisible && !overlay.testExpiryTimerActive, "disposed overlay cannot restart")
        overlay.dispose()

        let summary = "Native AppKit UI checks: \(checks - failures)/\(checks) passed.\n" +
            "PNG fixtures are the actual CatArtworkView drawing path at 2x, not a screenshot of the user's desktop.\n" +
            "No microphone, transcription API, installation, or user-machine access was used.\n" +
            "greeting-frame-00...29: 100 ms/frame, the configured 3-second greeting cycle.\n"
        try Data(summary.utf8).write(to: output.appendingPathComponent("VALIDATION.txt"))
        print(summary)
        if failures > 0 { exit(1) }
    }
}
