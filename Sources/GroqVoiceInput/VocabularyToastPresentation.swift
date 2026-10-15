import Foundation
import CoreGraphics

/// Preview has no persistence actions, so sharing the display lifecycle cannot
/// accidentally propose, confirm, reject, or remove a dictionary record.
enum VocabularyToastPurpose {
    struct LearningActions {
        var complete: (Bool) -> Bool
        var cancel: () -> Void
        var reject: () -> Void
    }

    case learning(LearningActions)
    case preview

    var isPreview: Bool {
        if case .preview = self { return true }
        return false
    }

    func acceptsForeground(expected: Int32?, current: Int32?, ownPID: Int32) -> Bool {
        expected != nil && expected == current && (isPreview || current != ownPID)
    }

    func complete(isContextValid: Bool) -> Bool {
        guard case .learning(let actions) = self else { return false }
        return actions.complete(isContextValid)
    }

    func cancel() {
        if case .learning(let actions) = self { actions.cancel() }
    }

    func reject() {
        if case .learning(let actions) = self { actions.reject() }
    }
}

struct VocabularyToastVisibility: Equatable {
    var panelVisible: Bool
    var panelOnActiveSpace: Bool
    var panelOcclusionVisible: Bool
    var panelIntersectsScreen: Bool
    var appHidden: Bool
    var focusUnchanged: Bool
    var panelIsKey: Bool
    var panelIsMain: Bool

    var isReady: Bool {
        panelVisible && panelOnActiveSpace && panelOcclusionVisible && panelIntersectsScreen
            && !appHidden && focusUnchanged && !panelIsKey && !panelIsMain
    }

    static let unavailable = Self(panelVisible: false, panelOnActiveSpace: false,
                                  panelOcclusionVisible: false, panelIntersectsScreen: false,
                                  appHidden: true, focusUnchanged: false, panelIsKey: false, panelIsMain: false)
}

enum VocabularyToastPlacement {
    static func transitionDuration(reduceMotion: Bool) -> TimeInterval { reduceMotion ? 0.12 : 0.18 }
    static func screenIndex(targetFrame: CGRect?, screenFrames: [CGRect], fallbackIndex: Int?) -> Int? {
        if let targetFrame, !targetFrame.isEmpty, !targetFrame.isNull, !targetFrame.isInfinite {
            let intersections = screenFrames.enumerated().map { index, frame in
                let overlap = frame.intersection(targetFrame)
                return (index, overlap.isNull ? 0 : overlap.width * overlap.height)
            }
            if let best = intersections.max(by: { $0.1 < $1.1 }), best.1 > 0 { return best.0 }
        }
        if let fallbackIndex, screenFrames.indices.contains(fallbackIndex) { return fallbackIndex }
        return screenFrames.indices.first
    }

    static func frame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        CGRect(x: visibleFrame.midX - size.width / 2,
               y: visibleFrame.maxY - size.height - 12, width: size.width, height: size.height)
    }
}

/// Owns only timing and generation checks. It cannot display a window or mutate
/// vocabulary; those actions are injected by the controller and tests.
final class VocabularyToastPresentation {
    struct Environment {
        var now: () -> TimeInterval
        var schedule: (TimeInterval, @escaping () -> Void) -> Void

        static var system: Self {
            Self(now: { ProcessInfo.processInfo.systemUptime }, schedule: { delay, action in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
            })
        }
    }

    enum Outcome {
        case completed(contextValid: Bool, visibility: VocabularyToastVisibility)
        case presentationUnavailable(VocabularyToastVisibility)
    }

    private let environment: Environment
    private let optOutDuration: TimeInterval
    private let revealLimit: TimeInterval = 0.3
    private let visibilityPollInterval: TimeInterval = 0.05
    private var activeID: UUID?
    private struct Countdown {
        var remaining: TimeInterval
        var lastUpdatedAt: TimeInterval
        var paused: Bool
    }
    private var countdown: Countdown?
    private var hovered = false
    private var progress: ((TimeInterval, TimeInterval, Bool) -> Void)?

    init(environment: Environment = .system, optOutDuration: TimeInterval = 6) {
        self.environment = environment
        self.optOutDuration = optOutDuration
    }

    func cancel() {
        activeID = nil
        countdown = nil
        progress = nil
        hovered = false
    }

    func setHovered(_ value: Bool) {
        guard activeID != nil, hovered != value else { return }
        hovered = value
        advanceCountdown()
        guard var current = countdown else { return }
        current.paused = value
        // Give the user at least one second to return to the rejection button
        // when leaving near the deadline; never shorten remaining reading time.
        if !value { current.remaining = max(current.remaining, min(1, optOutDuration)) }
        countdown = current
        progress?(current.remaining, optOutDuration, current.paused)
    }

    func start(
        reveal: @escaping () -> Void,
        visibility: @escaping () -> VocabularyToastVisibility,
        isContextValid: @escaping () -> Bool,
        onAttempt: @escaping (VocabularyToastVisibility) -> Void,
        onVisible: @escaping (VocabularyToastVisibility) -> Void,
        transitionDuration: TimeInterval = 0,
        onCountdownStarted: @escaping () -> Void = {},
        initiallyHovered: Bool = false,
        onProgress: @escaping (TimeInterval, TimeInterval, Bool) -> Void = { _, _, _ in },
        onFinish: @escaping (Outcome) -> Void
    ) {
        let id = UUID()
        activeID = id
        countdown = nil
        hovered = initiallyHovered
        progress = onProgress
        let startedAt = environment.now()
        reveal()
        // Ordering a window is not proof it reached the display. Inspect only
        // after AppKit has had another main-runloop opportunity to present it.
        environment.schedule(0) { [weak self] in
            self?.attempt(id: id, startedAt: startedAt, reveal: reveal, visibility: visibility,
                          isContextValid: isContextValid, onAttempt: onAttempt,
                          onVisible: onVisible, transitionDuration: transitionDuration,
                          onCountdownStarted: onCountdownStarted, onFinish: onFinish)
        }
    }

    private func attempt(
        id: UUID, startedAt: TimeInterval,
        reveal: @escaping () -> Void, visibility: @escaping () -> VocabularyToastVisibility,
        isContextValid: @escaping () -> Bool, onAttempt: @escaping (VocabularyToastVisibility) -> Void,
        onVisible: @escaping (VocabularyToastVisibility) -> Void, transitionDuration: TimeInterval,
        onCountdownStarted: @escaping () -> Void, onFinish: @escaping (Outcome) -> Void
    ) {
        guard activeID == id else { return }
        let snapshot = visibility()
        guard activeID == id else { return }
        onAttempt(snapshot)
        guard activeID == id else { return }
        if snapshot.isReady {
            onVisible(snapshot)
            guard activeID == id else { return }
            environment.schedule(transitionDuration) { [weak self] in
                guard let self, self.activeID == id else { return }
                let afterTransition = visibility()
                guard self.activeID == id else { return }
                guard afterTransition.isReady else {
                    self.cancel()
                    onFinish(.presentationUnavailable(afterTransition))
                    return
                }
                self.countdown = Countdown(remaining: self.optOutDuration,
                                           lastUpdatedAt: self.environment.now(), paused: self.hovered)
                onCountdownStarted()
                guard self.activeID == id else { return }
                self.publishProgress()
                guard self.activeID == id else { return }
                self.scheduleCountdownCheck(id: id,
                                            visibility: visibility, isContextValid: isContextValid,
                                            onFinish: onFinish)
            }
            return
        }
        let elapsed = environment.now() - startedAt
        guard elapsed < revealLimit, snapshot.focusUnchanged, !snapshot.panelIsKey, !snapshot.panelIsMain else {
            cancel()
            onFinish(.presentationUnavailable(snapshot))
            return
        }
        reveal()
        environment.schedule(min(0.05, revealLimit - elapsed)) { [weak self] in
            self?.attempt(id: id, startedAt: startedAt, reveal: reveal, visibility: visibility,
                          isContextValid: isContextValid, onAttempt: onAttempt,
                          onVisible: onVisible, transitionDuration: transitionDuration,
                          onCountdownStarted: onCountdownStarted, onFinish: onFinish)
        }
    }

    private func scheduleCountdownCheck(
        id: UUID,
        visibility: @escaping () -> VocabularyToastVisibility,
        isContextValid: @escaping () -> Bool, onFinish: @escaping (Outcome) -> Void
    ) {
        guard let countdown else { return }
        let delay = countdown.paused ? visibilityPollInterval : min(visibilityPollInterval, max(0, countdown.remaining))
        environment.schedule(delay) { [weak self] in
            guard let self, self.activeID == id else { return }
            let snapshot = visibility()
            guard self.activeID == id else { return }
            // Losing the opt-out UI cancels this notice permanently, even when
            // it becomes visible again before its original deadline.
            guard snapshot.isReady else {
                self.cancel()
                onFinish(.presentationUnavailable(snapshot))
                return
            }
            // Visibility includes foreground focus. The existing correction
            // monitor cancels same-app edits/target changes at its own cadence;
            // do not add high-frequency AX range reads while the pointer rests.
            self.advanceCountdown()
            self.publishProgress()
            // Progress callbacks can report a newly hovered bubble, cancel, or
            // replace the notice. Re-read state before allowing completion.
            guard self.activeID == id, let current = self.countdown else { return }
            if !current.paused, current.remaining <= 0 {
                let stillValid = isContextValid()
                // The final context check can synchronously cancel or replace
                // this notice, so its generation must be checked once more.
                guard self.activeID == id else { return }
                // AX validation may block event delivery briefly. Publishing
                // once more lets the view refresh its own window's pointer
                // position before deciding whether expiry may proceed.
                self.publishProgress()
                guard self.activeID == id else { return }
                if stillValid, let latest = self.countdown, latest.paused || latest.remaining > 0 {
                    self.scheduleCountdownCheck(id: id, visibility: visibility,
                                                isContextValid: isContextValid, onFinish: onFinish)
                    return
                }
                self.cancel()
                onFinish(.completed(contextValid: stillValid, visibility: snapshot))
            } else {
                self.scheduleCountdownCheck(id: id, visibility: visibility,
                                            isContextValid: isContextValid, onFinish: onFinish)
            }
        }
    }

    private func advanceCountdown() {
        guard var current = countdown else { return }
        let now = environment.now()
        if !current.paused {
            current.remaining = max(0, current.remaining - max(0, now - current.lastUpdatedAt))
            if current.remaining < 0.000_001 { current.remaining = 0 }
        }
        current.lastUpdatedAt = now
        countdown = current
    }

    private func publishProgress() {
        guard let current = countdown else { return }
        progress?(current.remaining, optOutDuration, current.paused)
    }
}
