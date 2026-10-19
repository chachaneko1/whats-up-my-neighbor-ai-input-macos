import AppKit
import ApplicationServices

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
    private var interval: TimeInterval = 0
    private var suspended = Set<String>()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var disposed = false
    private let automaticallyTicks: Bool
    private let presentation: Presentation
    private var injectedWorld: (() -> DesktopPetWorld)?

    init(resources: URL? = Bundle.main.resourceURL?.appendingPathComponent("DesktopPet"),
         automaticallyTicks: Bool = true, world: (() -> DesktopPetWorld)? = nil,
         presentation: Presentation = .system) {
        precondition(Thread.isMainThread)
        self.automaticallyTicks = automaticallyTicks
        self.presentation = presentation
        injectedWorld = world
        artwork = DesktopPetView(resources: resources)
        panel = DesktopPetPanel(contentRect: CGRect(origin: .zero, size: DesktopPetModel.size),
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
        panel.isMovable = false
        panel.contentView = artwork
        panel.title = "小黑貓桌面夥伴"
        if automaticallyTicks {
            if world == nil,
               (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true {
                suspended.insert("lock")
            }
            observeEnvironment()
        }
    }

    var isReleased: Bool { model.released }

    func setReleased(_ value: Bool) {
        guard !disposed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        model.setReleased(value, now: now, world: world(now: now))
        if !value { reader.cancel(); snapshot = .init() }
        refresh(now: now)
        onReleasedChange?(value)
    }

    func refresh(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        precondition(Thread.isMainThread)
        guard !disposed else { return }
        let environment = world(now: now)
        model.tick(now: now, world: environment)
        if model.visible {
            // The login agent uses open -gj. Match the recording HUD's
            // nonactivating presentation instead of leaving a hidden app's
            // animation running without an on-screen window.
            if presentation.isAppHidden() { presentation.unhideWithoutActivation() }
            artwork.update(model, reduceMotion: environment.reduceMotion)
            panel.setFrameOrigin(model.origin)
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible { panel.orderOut(nil) }
        let delay: TimeInterval
        if !model.released || !suspended.isEmpty { delay = 0 }
        else if !model.visible || environment.reduceMotion || environment.idleSeconds < 12 { delay = 1 }
        else if model.pose == .grooming { delay = 1 / 25 }
        else { delay = model.pose == .walking || model.pose == .yawning ? 1 / 12 : 1 / 4 }
        schedule(every: delay)
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        timer?.invalidate(); timer = nil
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
        for (center, token) in observers { center.removeObserver(token) }
    }

    #if DESKTOP_PET_TESTS
    var testPanel: NSPanel { panel }
    var testTimerActive: Bool { timer != nil }
    func testSuspend(_ value: Bool) {
        if value { suspended.insert("test") } else { suspended.remove("test") }
        refresh()
    }
    #endif
}
