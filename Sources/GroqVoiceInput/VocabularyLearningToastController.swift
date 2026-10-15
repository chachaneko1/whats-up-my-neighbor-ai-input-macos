import AppKit

/// Displays an opt-out without activating this app or moving the typing caret.
final class VocabularyLearningToastController {
    private let automaticLearning: VocabularyAutomaticLearning
    private let panel: NekoFloatingPanel
    private let bubble = VocabularyLearningBubbleView()
    private let presentation = VocabularyToastPresentation(optOutDuration: VocabularyAutomaticLearning.optOutDuration)
    private var presentationID: UUID?
    private var onResolved: (() -> Void)?
    private var expectedForegroundPID: pid_t?
    private var targetScreenNumber: NSNumber?
    private var purpose: VocabularyToastPurpose?

    var isPresentingLearningPrompt: Bool { presentationID != nil && purpose?.isPreview == false }

    init(store: VocabularyLearningStore) {
        automaticLearning = VocabularyAutomaticLearning(store: store)
        let size = VocabularyLearningBubbleView.preferredSize
        panel = NekoFloatingPanel(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "What's up my neighbor"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        panel.contentView = bubble
        bubble.onReject = { [weak self] in self?.rejectPending() }
        bubble.onHoverChanged = { [weak self] hovered in self?.presentation.setHovered(hovered) }
    }

    func show(
        _ candidate: MacVocabularyCandidate,
        targetFrame: NSRect? = nil,
        isStillValid: @escaping () -> Bool,
        onResolved: @escaping () -> Void
    ) {
        cancelPendingCorrection()
        guard let pending = automaticLearning.propose(candidate) else {
            PasteDiagnostics.shared.record(.init(tag: .learningToast, accepted: false,
                learningStage: .toast, learningReason: .candidateUnavailable))
            onResolved()
            return
        }
        let purpose = VocabularyToastPurpose.learning(.init(
            complete: { [weak self] valid in self?.automaticLearning.complete(isContextValid: valid) ?? false },
            cancel: { [weak self] in self?.automaticLearning.cancel() },
            reject: { [weak self] in self?.automaticLearning.reject() }
        ))
        present(term: pending.term, purpose: purpose, targetFrame: targetFrame,
                isStillValid: isStillValid, onResolved: onResolved)
    }

    /// Exercises the same panel and countdown without touching the dictionary.
    func showPreview() {
        // A preview must not interrupt a real correction and delete its pending record.
        guard purpose?.isPreview != false else { return }
        cancelPendingCorrection()
        present(term: "示範詞", purpose: .preview, targetFrame: nil,
                isStillValid: { true }, onResolved: {})
    }

    private func present(
        term: String, purpose: VocabularyToastPurpose, targetFrame: NSRect?,
        isStillValid: @escaping () -> Bool, onResolved: @escaping () -> Void
    ) {
        self.purpose = purpose
        self.onResolved = onResolved
        let id = UUID()
        presentationID = id
        bubble.setTerm(term, isPreview: purpose.isPreview)
        panel.setContentSize(bubble.frame.size)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let transitionDuration = VocabularyToastPlacement.transitionDuration(reduceMotion: reduceMotion)
        expectedForegroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let screens = NSScreen.screens
        let fallback = NSScreen.main.flatMap { main in screens.firstIndex(of: main) }
        if let index = VocabularyToastPlacement.screenIndex(targetFrame: targetFrame,
                                                            screenFrames: screens.map(\.frame), fallbackIndex: fallback) {
            let screen = screens[index]
            targetScreenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            panel.setFrame(VocabularyToastPlacement.frame(size: panel.frame.size, in: screen.visibleFrame), display: false)
        }
        let finalFrame = panel.frame
        if !reduceMotion { panel.setFrameOrigin(NSPoint(x: finalFrame.minX, y: finalFrame.minY - 8)) }
        panel.alphaValue = 0.2
        presentation.start(reveal: { [weak self] in
            guard let self, self.presentationID == id else { return }
            if NSApp.isHidden { NSApp.unhideWithoutActivation() }
            self.panel.orderFrontRegardless()
        }, visibility: { [weak self] in
            self?.visibility() ?? .unavailable
        }, isContextValid: isStillValid, onAttempt: { [weak self] snapshot in
            self?.recordVisibility(snapshot, stage: .presenting, accepted: snapshot.isReady)
        }, onVisible: { [weak self] snapshot in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = transitionDuration
                self.panel.animator().alphaValue = 1
                if !reduceMotion { self.panel.animator().setFrame(finalFrame, display: true) }
            }
        }, transitionDuration: transitionDuration, onCountdownStarted: { [weak self] in
            guard let self, self.presentationID == id else { return }
            self.bubble.refreshPointerLocation()
            self.presentation.setHovered(self.bubble.isPointerInside)
            self.recordVisibility(self.visibility(), stage: .toast, accepted: true)
        }, initiallyHovered: bubble.isPointerInside, onProgress: { [weak self] remaining, total, paused in
            guard let self, self.presentationID == id else { return }
            self.bubble.setCountdown(remaining: remaining, total: total, paused: paused)
        }, onFinish: { [weak self] outcome in
            guard let self, self.presentationID == id else { return }
            switch outcome {
            case .completed(let valid, let snapshot):
                let added = purpose.complete(isContextValid: valid)
                self.recordVisibility(snapshot, stage: .completed, contextValid: valid, added: added)
            case .presentationUnavailable(let snapshot):
                purpose.cancel()
                self.recordVisibility(snapshot, stage: .completed, accepted: false,
                                      reason: .presentationUnavailable, added: false)
            }
            self.dismissAndResolve()
        })
    }

    /// Continued typing or a changed target discards the unfinished candidate.
    func cancelPendingCorrection() {
        presentation.cancel()
        presentationID = nil
        onResolved = nil
        expectedForegroundPID = nil
        targetScreenNumber = nil
        purpose?.cancel()
        purpose = nil
        panel.orderOut(nil)
    }

    @objc private func rejectPending() {
        purpose?.reject()
        dismissAndResolve()
    }

    private func dismissAndResolve() {
        presentation.cancel()
        presentationID = nil
        expectedForegroundPID = nil
        targetScreenNumber = nil
        purpose = nil
        panel.orderOut(nil)
        let resolved = onResolved
        onResolved = nil
        resolved?()
    }

    private func visibility() -> VocabularyToastVisibility {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == targetScreenNumber
        }
        let intersects = screen.map { !$0.visibleFrame.intersection(panel.frame).isEmpty } ?? false
        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return VocabularyToastVisibility(
            panelVisible: panel.isVisible,
            panelOnActiveSpace: panel.isOnActiveSpace,
            panelOcclusionVisible: panel.occlusionState.contains(.visible),
            panelIntersectsScreen: intersects,
            appHidden: NSApp.isHidden,
            focusUnchanged: purpose?.acceptsForeground(expected: expectedForegroundPID, current: currentPID,
                ownPID: ProcessInfo.processInfo.processIdentifier) ?? false,
            panelIsKey: panel.isKeyWindow,
            panelIsMain: panel.isMainWindow
        )
    }

    private func recordVisibility(_ value: VocabularyToastVisibility, stage: PasteDiagnostics.LearningStage,
                                  accepted: Bool? = nil, reason: PasteDiagnostics.LearningReason? = nil,
                                  contextValid: Bool? = nil, added: Bool? = nil) {
        PasteDiagnostics.shared.record(.init(tag: .learningToast, accepted: accepted,
            learningStage: stage, learningReason: reason, contextValid: contextValid, added: added,
            panelVisible: value.panelVisible, panelOnActiveSpace: value.panelOnActiveSpace,
            panelOcclusionVisible: value.panelOcclusionVisible, panelIntersectsScreen: value.panelIntersectsScreen,
            appHidden: value.appHidden, focusUnchanged: value.focusUnchanged, isPreview: purpose?.isPreview ?? false))
    }
}
