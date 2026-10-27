import AppKit
import Carbon
@main
struct ClipboardPasteGestureTests {
    static func main() {
        var checks = 0
        func expect(_ result: ClipboardPasteGestureState.Decision, _ expected: ClipboardPasteGestureState.Decision) {
            checks += 1; precondition(result == expected, "\(result) != \(expected)")
        }
        for direction in [kVK_UpArrow, kVK_DownArrow] {
            var s = ClipboardPasteGestureState()
            expect(s.handle(kind: .down, key: direction, command: true, otherModifiers: false), .pass)
            expect(s.handle(kind: .down, key: kVK_ANSI_V, command: true, otherModifiers: false), .begin)
            for _ in 0..<40 { expect(s.handle(kind: .down, key: kVK_ANSI_V, command: true, otherModifiers: false, repeated: true), .swallow) }
            expect(s.handle(kind: .down, key: direction, command: true, otherModifiers: false), .open(direction == kVK_UpArrow ? -1 : 1))
            expect(s.handle(kind: .down, key: direction, command: true, otherModifiers: false, repeated: true), .swallow)
            expect(s.handle(kind: .down, key: direction, command: true, otherModifiers: false, pickerVisible: true), .move(direction == kVK_UpArrow ? -1 : 1))
            expect(s.handle(kind: .flags, key: kVK_Command, command: false, otherModifiers: false), .pass)
            expect(s.handle(kind: .down, key: direction, command: false, otherModifiers: false, pickerVisible: true), .move(direction == kVK_UpArrow ? -1 : 1))
            expect(s.handle(kind: .up, key: kVK_ANSI_V, command: true, otherModifiers: false), .swallow)
            expect(s.handle(kind: .up, key: kVK_Command, command: false, otherModifiers: false), .pass)
        }
        for cancel in [kVK_ANSI_C, kVK_Tab, kVK_Return] {
            var s = ClipboardPasteGestureState()
            expect(s.handle(kind: .down, key: kVK_ANSI_V, command: true, otherModifiers: false), .begin)
            expect(s.handle(kind: .down, key: cancel, command: true, otherModifiers: false), .replay)
            precondition(!s.isActive)
        }
        var normal = ClipboardPasteGestureState()
        expect(normal.handle(kind: .down, key: kVK_ANSI_V, command: true, otherModifiers: false), .begin)
        expect(normal.handle(kind: .up, key: kVK_ANSI_V, command: true, otherModifiers: false), .replay)
        expect(normal.handle(kind: .down, key: kVK_UpArrow, command: true, otherModifiers: false), .pass)
        for key in [kVK_ANSI_V, kVK_UpArrow, kVK_DownArrow] {
            var s = ClipboardPasteGestureState()
            expect(s.handle(kind: .down, key: key, command: true, otherModifiers: true), .pass)
            expect(s.handle(kind: .down, key: key, command: false, otherModifiers: false), .pass)
            expect(s.handle(kind: .down, key: key, command: true, otherModifiers: false, canBegin: false), .pass)
        }
        var release = ClipboardPasteGestureState()
        expect(release.handle(kind: .down, key: kVK_ANSI_V, command: true, otherModifiers: false), .begin)
        expect(release.handle(kind: .flags, key: kVK_Command, command: false, otherModifiers: false), .replay)
        expect(release.handle(kind: .up, key: kVK_ANSI_V, command: false, otherModifiers: false), .pass)
        precondition(!release.isActive, "Releasing V after Command cannot replay a second paste")
        var modified = ClipboardPasteGestureState()
        expect(modified.handle(kind: .down, key: kVK_ANSI_V, command: true, otherModifiers: false), .begin)
        expect(modified.handle(kind: .flags, key: kVK_Shift, command: true, otherModifiers: true), .replay)
        expect(modified.handle(kind: .up, key: kVK_ANSI_V, command: true, otherModifiers: true), .pass)
        var escape = ClipboardPasteGestureState()
        expect(escape.handle(kind: .down, key: kVK_ANSI_V, command: true, otherModifiers: false), .begin)
        expect(escape.handle(kind: .down, key: kVK_Escape, command: true, otherModifiers: false), .swallow)
        expect(escape.handle(kind: .down, key: kVK_DownArrow, command: true, otherModifiers: false), .pass)
        expect(escape.handle(kind: .down, key: kVK_ANSI_V, command: true, otherModifiers: false, repeated: true), .swallow)
        expect(escape.handle(kind: .up, key: kVK_ANSI_V, command: false, otherModifiers: false), .swallow)
        escape.reset(); precondition(!escape.isActive)
        var browsing = ClipboardPasteGestureState()
        expect(browsing.handle(kind: .down, key: kVK_ANSI_V, command: true, otherModifiers: false), .begin)
        expect(browsing.handle(kind: .down, key: kVK_DownArrow, command: true, otherModifiers: false), .open(1))
        expect(browsing.handle(kind: .down, key: kVK_Escape, command: true, otherModifiers: false), .pass)
        expect(browsing.handle(kind: .up, key: kVK_ANSI_V, command: false, otherModifiers: false), .swallow)
        expect(browsing.handle(kind: .flags, key: kVK_Command, command: false, otherModifiers: false), .pass)
        var cancelled = ClipboardPasteGestureState()
        expect(cancelled.handle(kind: .down, key: kVK_ANSI_V, command: true, otherModifiers: false), .begin)
        cancelled.reset()
        expect(cancelled.handle(kind: .up, key: kVK_ANSI_V, command: true, otherModifiers: false), .pass)
        print("Clipboard paste gesture: \(checks) key-state checks passed; no global keyboard or clipboard accessed.")
    }
}
