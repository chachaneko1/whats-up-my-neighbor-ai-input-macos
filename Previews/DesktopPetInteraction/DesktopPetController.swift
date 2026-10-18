import AppKit
import ApplicationServices
import QuartzCore

@available(macOS 14.0, *)
private final class PreviewDisplayPulse: NSObject {
    weak var owner: DesktopPetController?
    private var link: CADisplayLink?
    init(owner: DesktopPetController, view: NSView) {
        self.owner = owner
        super.init()
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        self.link = link
        link.add(to: .main, forMode: .common)
    }
    @objc private func tick(_ link: CADisplayLink) { owner?.refresh() }
    func stop() { link?.invalidate(); link = nil }
}


private final class PreviewPetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Standalone preview. No preferences, file metadata, dictation, network,
/// clipboard, synthetic input, or installed-app lifecycle is used here.
final class DesktopPetController {
    private(set) var model = DesktopPetModel(seed: 42)
    let panel: NSPanel
    let artwork: DesktopPetView
    var onStateChange: ((String) -> Void)?
    private var timer: Timer?
    private var displayPulse: AnyObject?
    var usesDisplaySynchronization: Bool { displayPulse != nil }
    private var lastStateDescription: String?
    private var interval: TimeInterval = 0
    private var globalMouse: Any?
    private var localMouse: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var suspended = Set<String>()
    private var disposed = false
    private let automatic: Bool
    private let injectedWorld: (() -> DesktopPetWorld)?
    private let clock: () -> TimeInterval
    private let pressedButtons: () -> Int
    private var deliveringPointer = false

    init(resources: URL, automatic: Bool = true, world: (() -> DesktopPetWorld)? = nil,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         pressedButtons: @escaping () -> Int = { NSEvent.pressedMouseButtons }) {
        self.automatic = automatic
        injectedWorld = world
        self.clock = clock
        self.pressedButtons = pressedButtons
        artwork = DesktopPetView(resources: resources)
        panel = PreviewPetPanel(contentRect: CGRect(origin: .zero, size: DesktopPetView.panelSize),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.contentView = artwork
        panel.title = "小黑貓互動預覽"
        artwork.onPointerDown = { [weak self] point in self?.pointerDown(at: point) }
        artwork.onPointerDragged = { [weak self] point in self?.pointerDragged(to: point) }
        artwork.onPointerUp = { [weak self] in self?.pointerUp() }
        artwork.onAccessibilityPress = { [weak self] in self?.pet() }
        if automatic { observeEnvironment() }
    }

    func setReleased(_ released: Bool) {
        model.setReleased(released, now: clock(), world: world())
        refresh()
    }

    func pointerDown(at point: CGPoint) {
        deliveringPointer = true
        defer { deliveringPointer = false }
        model.pointerDown(at: point, now: clock(), world: world())
        refresh()
    }

    func pointerDragged(to point: CGPoint) {
        deliveringPointer = true
        defer { deliveringPointer = false }
        model.pointerDragged(to: point, now: clock(), world: world())
        refresh()
    }

    func pointerUp() {
        model.pointerUp(now: clock(), world: world())
        refresh()
    }

    func pet() {
        pointerDown(at: CGPoint(x: model.frame.midX, y: model.frame.midY))
        pointerUp()
    }

    func demonstrate(_ pose: DesktopPetPose) {
        model.demonstrate(pose, now: clock(), world: world())
        refresh()
    }

    func refresh() {
        guard !disposed else { return }
        let environment = world()
        if !deliveringPointer, model.isPressed, pressedButtons() & 1 == 0 {
            model.pointerUp(now: clock(), world: environment)
        }
        model.tick(now: clock(), world: environment)
        if model.visible {
            artwork.update(model, reduceMotion: environment.reduceMotion)
            panel.setFrameOrigin(CGPoint(x: model.origin.x + DesktopPetView.panelOffset.x,
                                         y: model.origin.y + DesktopPetView.panelOffset.y))
            if !panel.isVisible { panel.orderFrontRegardless() }
            updateHitRegion(at: environment.cursor)
        } else {
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
        }
        if lastStateDescription != model.pose.description {
            lastStateDescription = model.pose.description
            onStateChange?(model.pose.description)
        }
        guard automatic else { return }
        if #available(macOS 14.0, *) {
            let animating = model.released && suspended.isEmpty && !environment.reduceMotion &&
                (model.isDragging || model.isSettling) &&
                !(model.isDragging && model.lift.spriteFrame == 8 && abs(model.carryLean) < 0.05)
            if animating {
                timer?.invalidate(); timer = nil; interval = 0
                if displayPulse == nil { displayPulse = PreviewDisplayPulse(owner: self, view: artwork) }
                return
            }
            (displayPulse as? PreviewDisplayPulse)?.stop(); displayPulse = nil
        }
        let delay: TimeInterval
        if !model.released || !suspended.isEmpty { delay = 0 }
        else if !environment.reduceMotion && (model.isDragging || model.isSettling) {
            let heldStill = model.isDragging && model.lift.spriteFrame == 8 && abs(model.carryLean) < 0.05
            delay = heldStill ? 1 / 30 : 1 / 60
        }
        else if model.isPressed || [.walking, .grooming, .yawning].contains(model.pose) { delay = 1 / 12 }
        else if [.petted, .carried].contains(model.pose) || environment.idleSeconds >= 12 { delay = 1 / 4 }
        else { delay = 1 }
        if timer != nil, interval == delay { return }
        timer?.invalidate(); timer = nil; interval = delay
        if delay > 0 {
            let next = Timer(timeInterval: delay, repeats: true) { [weak self] _ in self?.refresh() }
            next.tolerance = delay * 0.15
            timer = next
            RunLoop.main.add(next, forMode: .common)
        }
    }

    /// Only the drawn cat receives clicks. This monitor never starts a reaction,
    /// moves a window, consumes an event, or posts input to another application.
    func updateHitRegion(at point: CGPoint) {
        guard model.visible else { panel.ignoresMouseEvents = true; return }
        if model.isPressed { panel.ignoresMouseEvents = false; return }
        let local = CGPoint(x: point.x - panel.frame.minX,
                            y: panel.frame.maxY - point.y)
        panel.ignoresMouseEvents = !artwork.containsCat(local)
    }

    func suspend(_ value: Bool, reason: String = "test") {
        if value { suspended.insert(reason) } else { suspended.remove(reason) }
        refresh()
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        if #available(macOS 14.0, *) { (displayPulse as? PreviewDisplayPulse)?.stop() }
        displayPulse = nil
        timer?.invalidate(); timer = nil
        if let globalMouse { NSEvent.removeMonitor(globalMouse) }
        if let localMouse { NSEvent.removeMonitor(localMouse) }
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        model.cancelPointer(now: clock())
        panel.orderOut(nil)
        panel.close()
    }

    private func world() -> DesktopPetWorld {
        var result = injectedWorld?() ?? DesktopPetWorld(
            areas: NSScreen.screens.map(\.visibleFrame), cursor: NSEvent.mouseLocation,
            idleSeconds: CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                eventType: CGEventType(rawValue: UInt32.max)!),
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        result.hidden = result.hidden || !suspended.isEmpty
        return result
    }

    private func observeEnvironment() {
        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.updateHitRegion(at: NSEvent.mouseLocation)
        }
        localMouse = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updateHitRegion(at: NSEvent.mouseLocation)
            return event
        }
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ value: Bool, _ reason: String) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspend(value, reason: reason)
            }
            observers.append((center, token))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for (pause, resume, reason) in [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "system"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "display"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session")
        ] { observe(workspace, pause, true, reason); observe(workspace, resume, false, reason) }
        observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsLocked"), true, "lock")
        observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsUnlocked"), false, "lock")
        if (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true {
            suspended.insert("lock")
        }
    }
}
