import AppKit
import ApplicationServices
import Carbon

/// Only key codes and modifier bits are examined. No characters are read or logged.
struct ClipboardPasteGestureState {
    enum Kind { case down, up, flags }
    enum Decision: Equatable { case pass, begin, swallow, replay, open(Int), move(Int) }
    private enum Phase { case idle, pending, browsing }
    private var phase: Phase = .idle
    var isActive: Bool { phase != .idle }
    mutating func reset() { phase = .idle }

    mutating func handle(kind: Kind, key: Int, command: Bool, otherModifiers: Bool,
                         repeated: Bool = false, canBegin: Bool = true, pickerVisible: Bool = false) -> Decision {
        switch phase {
        case .idle:
            if kind == .down, key == kVK_ANSI_V, command, !otherModifiers, !repeated, canBegin {
                phase = .pending; return .begin
            }
            return .pass
        case .pending:
            if key == kVK_ANSI_V && kind != .flags {
                if kind == .up { phase = .idle; return .replay }
                return .swallow
            }
            if kind == .down, key == kVK_Escape { phase = .browsing; return .swallow }
            if kind == .down, command, !otherModifiers, [kVK_UpArrow, kVK_DownArrow].contains(key) {
                phase = .browsing; return .open(key == kVK_UpArrow ? -1 : 1)
            }
            if kind == .down || (kind == .flags && (!command || otherModifiers)) {
                phase = .idle; return .replay
            }
            return .pass
        case .browsing:
            if key == kVK_ANSI_V && kind != .flags {
                if kind == .up { phase = .idle }
                return .swallow
            }
            if pickerVisible, kind == .down, [kVK_UpArrow, kVK_DownArrow].contains(key) {
                return .move(key == kVK_UpArrow ? -1 : 1)
            }
            return .pass
        }
    }
}

/// A narrowly filtered, main-runloop event tap. Standard paste is delayed only
/// until V release so a history chord never first inserts the current clipboard.
/// Playback goes AFTER this tap, preserving original events/flags and ordering.
final class ClipboardPasteGesture {
    static let title = "按住 ⌘V，再按 ↑／↓"
    var canBegin: () -> Bool = { false }
    var pickerVisible: () -> Bool = { false }
    var onOpen: ((Int) -> Void)?
    var onMove: ((Int) -> Void)?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var state = ClipboardPasteGestureState()
    private var bufferedDown: CGEvent?
    private var originalPID: pid_t?
    var isRunning: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    @discardableResult
    func start() -> Bool {
        guard port == nil else { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask,
                                         callback: { proxy, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            return Unmanaged<ClipboardPasteGesture>.fromOpaque(pointer).takeUnretainedValue()
                .handle(proxy: proxy, type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.port = tap; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else { stop(); return false }
        return true
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil; source = nil; state.reset(); bufferedDown = nil; originalPID = nil
    }
    deinit { stop() }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            state.reset(); bufferedDown = nil; originalPID = nil
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Synthetic dictation/history pastes must pass through immediately.
        if IsSecureEventInputEnabled() {
            state.reset(); bufferedDown = nil; originalPID = nil
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUnixProcessID) == 0 else { return Unmanaged.passUnretained(event) }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if state.isActive, let originalPID, pid != originalPID {
            state.reset(); bufferedDown = nil; self.originalPID = nil
        }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
            state.reset(); bufferedDown = nil; originalPID = nil
            return Unmanaged.passUnretained(event)
        }
        let kind: ClipboardPasteGestureState.Kind
        switch type { case .keyDown: kind = .down; case .keyUp: kind = .up; case .flagsChanged: kind = .flags
        default: return Unmanaged.passUnretained(event) }
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        // Secure Input may hide key releases from a tap. A new physical V
        // press starts fresh; an expired, already released chord never replays
        // an old paste into a later field after secure input has ended.
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let newV = kind == .down && code == kVK_ANSI_V && !repeated
        let staleReleased = bufferedDown.map {
            event.timestamp > $0.timestamp && event.timestamp - $0.timestamp > 5_000_000_000 &&
                !CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_ANSI_V)) &&
                !(kind == .up && code == kVK_ANSI_V)
        } ?? false
        if state.isActive && (newV || staleReleased) {
            state.reset(); bufferedDown = nil; originalPID = nil
        }
        let decision = state.handle(kind: kind, key: code, command: event.flags.contains(.maskCommand),
                                    otherModifiers: !event.flags.intersection([.maskControl, .maskAlternate, .maskShift]).isEmpty,
                                    repeated: repeated,
                                    canBegin: canBegin(), pickerVisible: pickerVisible())
        switch decision {
        case .pass: return Unmanaged.passUnretained(event)
        case .begin:
            guard let copy = event.copy(), pid != nil else {
                state.reset(); return Unmanaged.passUnretained(event)
            }
            bufferedDown = copy; originalPID = pid; return nil
        case .swallow: return nil
        case .replay:
            if let down = bufferedDown, pid == originalPID {
                down.tapPostEvent(proxy)
                if code != kVK_ANSI_V || kind != .up, let up = down.copy() {
                    up.type = .keyUp
                    up.tapPostEvent(proxy)
                }
            }
            bufferedDown = nil; originalPID = nil
            return Unmanaged.passUnretained(event)
        case .open(let direction):
            bufferedDown = nil
            let expectedPID = originalPID
            DispatchQueue.main.async { [weak self] in
                guard let self, self.canBegin(),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else { return }
                self.onOpen?(direction)
            }
            return nil
        case .move(let direction):
            DispatchQueue.main.async { [weak self] in self?.onMove?(direction) }
            return nil
        }
    }
}
