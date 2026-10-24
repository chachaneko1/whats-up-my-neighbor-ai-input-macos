import AppKit
import ApplicationServices
import QuartzCore

@available(macOS 14.0, *)
private final class DesktopPetDisplayPulse: NSObject {
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
    deinit { link?.invalidate() }
}

private final class DesktopPetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns only the optional desktop companion. Recording and greeting keep their
/// existing windows and take priority; this controller never posts input events.
final class DesktopPetController {
    struct Presentation {
        var isAppHidden: () -> Bool
        var unhideWithoutActivation: () -> Void
        static var system: Self {
            Self(isAppHidden: { NSApp.isHidden }, unhideWithoutActivation: { NSApp.unhideWithoutActivation() })
        }
    }
    var onReleasedChange: ((Bool) -> Void)?
    var isBusy: () -> Bool = { NSApp.modalWindow != nil }
    private(set) var model = DesktopPetModel()
    private let panel: DesktopPetPanel
    private let artwork: DesktopPetView
    private let reader = DesktopPetDesktopReader()
    private var snapshot = DesktopPetDesktopReader.Snapshot()
    private var nextRefresh: TimeInterval = 0
    private var timer: Timer?
    private var displayPulse: AnyObject?
    private var globalMouse: Any?
    private var localMouse: Any?
    private var deliveringPointer = false
    private let clock: () -> TimeInterval
    private let pressedButtons: () -> Int
    private var interval: TimeInterval = 0
    private var suspended = Set<String>()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var disposed = false
    private let automaticallyTicks: Bool
    private let presentation: Presentation
    private var injectedWorld: (() -> DesktopPetWorld)?

    init(resources: URL? = Bundle.main.resourceURL?.appendingPathComponent("DesktopPet"),
         appearance: CatAppearance = .original,
         automaticallyTicks: Bool = true, world: (() -> DesktopPetWorld)? = nil,
         presentation: Presentation = .system,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         pressedButtons: @escaping () -> Int = { NSEvent.pressedMouseButtons }) {
        precondition(Thread.isMainThread)
        self.automaticallyTicks = automaticallyTicks
        self.presentation = presentation
        self.clock = clock
        self.pressedButtons = pressedButtons
        injectedWorld = world
        artwork = DesktopPetView(resources: resources, appearance: appearance)
        panel = DesktopPetPanel(contentRect: CGRect(origin: .zero, size: DesktopPetView.panelSize),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.contentView = artwork
        panel.title = "小黑貓桌面夥伴"
        artwork.onPointerDown = { [weak self] point in self?.pointerDown(at: point) }
        artwork.onPointerDragged = { [weak self] point in self?.pointerDragged(to: point) }
        artwork.onPointerUp = { [weak self] in self?.pointerUp() }
        artwork.onAccessibilityPress = { [weak self] in self?.pet() }
        if automaticallyTicks {
            if world == nil,
               (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true {
                suspended.insert("lock")
            }
            observeEnvironment()
        }
    }

    var isReleased: Bool { model.released }

    /// An explicit coat choice also brings a recalled pet onto the desktop.
    func show(appearance: CatAppearance) {
        guard !disposed else { return }
        artwork.setAppearance(appearance)
        if model.released { refresh() }
        else { setReleased(true) }
    }

    func setReleased(_ value: Bool) {
        guard !disposed else { return }
        let now = clock()
        model.setReleased(value, now: now, world: world(now: now))
        if !value { reader.cancel(); snapshot = .init() }
        refresh(now: now)
        onReleasedChange?(value)
    }

    func pointerDown(at point: CGPoint) {
        guard !disposed else { return }
        deliveringPointer = true
        defer { deliveringPointer = false }
        let now = clock()
        model.pointerDown(at: point, now: now, world: world(now: now))
        refresh(now: now)
    }

    func pointerDragged(to point: CGPoint) {
        guard !disposed else { return }
        deliveringPointer = true
        defer { deliveringPointer = false }
        let now = clock()
        model.pointerDragged(to: point, now: now, world: world(now: now))
        refresh(now: now)
    }

    func pointerUp() {
        guard !disposed else { return }
        let now = clock()
        model.pointerUp(now: now, world: world(now: now))
        refresh(now: now)
    }

    func pet() {
        pointerDown(at: CGPoint(x: model.frame.midX, y: model.frame.midY))
        pointerUp()
    }

    func refresh(now suppliedNow: TimeInterval? = nil) {
        precondition(Thread.isMainThread)
        guard !disposed else { return }
        let now = suppliedNow ?? clock()
        let environment = world(now: now)
        if !deliveringPointer, model.isPressed, pressedButtons() & 1 == 0 {
            model.pointerUp(now: now, world: environment)
        }
        model.tick(now: now, world: environment)
        if model.visible {
            // The login agent uses open -gj. Match the recording HUD's
            // nonactivating presentation instead of leaving a hidden app's
            // animation running without an on-screen window.
            if presentation.isAppHidden() { presentation.unhideWithoutActivation() }
            artwork.update(model, reduceMotion: environment.reduceMotion)
            panel.setFrameOrigin(CGPoint(x: model.origin.x + DesktopPetView.panelOffset.x,
                                         y: model.origin.y + DesktopPetView.panelOffset.y))
            if !panel.isVisible { panel.orderFrontRegardless() }
            updateHitRegion(at: environment.cursor)
        } else {
            panel.ignoresMouseEvents = true
            if panel.isVisible { panel.orderOut(nil) }
        }
        if #available(macOS 14.0, *), automaticallyTicks {
            let animating = model.visible && suspended.isEmpty && !environment.reduceMotion &&
                (model.isDragging || model.isSettling) &&
                !(model.isDragging && model.lift.spriteFrame == DesktopPetLift.carryFrame)
            if animating {
                timer?.invalidate(); timer = nil; interval = 0
                if displayPulse == nil { displayPulse = DesktopPetDisplayPulse(owner: self, view: artwork) }
                return
            }
            (displayPulse as? DesktopPetDisplayPulse)?.stop(); displayPulse = nil
        }
        let delay: TimeInterval
        if !model.released || !suspended.isEmpty { delay = 0 }
        else if !model.visible { delay = 1 }
        else if !environment.reduceMotion && (model.isDragging || model.isSettling) {
            delay = model.isDragging && model.lift.spriteFrame == DesktopPetLift.carryFrame ? 1 / 30 : 1 / 60
        }
        else if model.isPressed { delay = 1 / 30 }
        else if model.pose == .petted { delay = 1 / 12 }
        else if environment.reduceMotion || environment.idleSeconds < 12 { delay = 1 }
        else if model.pose == .grooming { delay = 1 / 25 }
        else { delay = model.pose == .walking || model.pose == .yawning ? 1 / 12 : 1 / 4 }
        schedule(every: delay)
    }

    /// Observe pointer position only to let transparent padding pass through.
    /// Hover never moves the cat, changes its pose, or consumes a desktop event.
    func updateHitRegion(at point: CGPoint) {
        guard model.visible, !disposed, suspended.isEmpty, !isBusy() else {
            panel.ignoresMouseEvents = true; return
        }
        if model.isPressed { panel.ignoresMouseEvents = false; return }
        let local = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
        panel.ignoresMouseEvents = !artwork.containsCat(local)
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        if #available(macOS 14.0, *) { (displayPulse as? DesktopPetDisplayPulse)?.stop() }
        displayPulse = nil
        timer?.invalidate(); timer = nil
        if let globalMouse { NSEvent.removeMonitor(globalMouse) }
        if let localMouse { NSEvent.removeMonitor(localMouse) }
        globalMouse = nil; localMouse = nil
        model.cancelPointer(now: clock())
        reader.cancel()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        panel.orderOut(nil)
        panel.close()
        onReleasedChange = nil
        isBusy = { true }
    }

    private func world(now: TimeInterval) -> DesktopPetWorld {
        if var result = injectedWorld?() {
            result.hidden = result.hidden || !suspended.isEmpty || isBusy()
            return result
        }
        let screens = NSScreen.screens
        if model.released, suspended.isEmpty, now >= nextRefresh {
            nextRefresh = now + 2
            reader.refresh(screens: screens.map(\.frame), primaryTop: screens.first?.frame.maxY ?? 0) { [weak self] value in
                guard let self, self.model.released, !self.disposed else { return }
                self.snapshot = value
            }
        }
        return DesktopPetWorld(areas: screens.map(\.visibleFrame), perches: snapshot.perches,
                               cursor: NSEvent.mouseLocation,
                               idleSeconds: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!),
                               hidden: !suspended.isEmpty || snapshot.fullScreen || isBusy(),
                               reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func schedule(every delay: TimeInterval) {
        guard automaticallyTicks else { return }
        if delay == interval, timer != nil { return }
        timer?.invalidate(); timer = nil; interval = delay
        guard delay > 0 else { return }
        let timer = Timer(timeInterval: delay, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = delay * 0.15
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func observeEnvironment() {
        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.updateHitRegion(at: NSEvent.mouseLocation)
        }
        localMouse = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updateHitRegion(at: NSEvent.mouseLocation)
            return event
        }
        let workspace = NSWorkspace.shared.notificationCenter
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping () -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in handler() }
            observers.append((center, token))
        }
        for (pause, resume, reason) in [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "system"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "display"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session")
        ] {
            observe(workspace, pause) { [weak self] in self?.suspended.insert(reason); self?.refresh() }
            observe(workspace, resume) { [weak self] in self?.suspended.remove(reason); self?.nextRefresh = 0; self?.refresh() }
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.snapshot = .init(); self?.nextRefresh = 0; self?.refresh()
        }
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] in self?.refresh() }
        // Lock notifications complement workspace session switching: both stop
        // the timer, and neither changes the system's sleep/energy settings.
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.suspended.insert("lock"); self?.refresh()
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.suspended.remove("lock"); self?.nextRefresh = 0; self?.refresh()
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.snapshot = .init(); self?.nextRefresh = 0; self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
        if let globalMouse { NSEvent.removeMonitor(globalMouse) }
        if let localMouse { NSEvent.removeMonitor(localMouse) }
        for (center, token) in observers { center.removeObserver(token) }
    }

    #if DESKTOP_PET_TESTS
    var testPanel: NSPanel { panel }
    var testTimerActive: Bool { timer != nil }
    var usesDisplaySynchronization: Bool { displayPulse != nil }
    var testArtwork: DesktopPetView { artwork }
    func testSuspend(_ value: Bool) {
        if value { suspended.insert("test") } else { suspended.remove("test") }
        refresh()
    }
    #endif
}
