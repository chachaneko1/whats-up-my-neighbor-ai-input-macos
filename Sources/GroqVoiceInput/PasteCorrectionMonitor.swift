import AppKit
import ApplicationServices

private func pasteCorrectionObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let monitor = Unmanaged<PasteCorrectionMonitor>
        .fromOpaque(refcon)
        .takeUnretainedValue()
    monitor.handleAccessibilityNotification(
        element: element,
        notification: notification as String
    )
}

final class PasteCorrectionMonitor {
    var onCandidate: ((MacVocabularyCandidate) -> Void)?

    private struct RecentSelection {
        let range: CFRange
        let observedAt: Date
    }

    private struct Session {
        let element: AXUIElement
        let pid: pid_t
        var referenceText: String
        var trackedRange: TrackedPasteRange
        var characterCount: Int
        var currentText: String
        var isEditingBurst: Bool
        var recentSelection: RecentSelection?
    }

    private let monitoringLifetime: TimeInterval = 120
    private let reviewDelay: TimeInterval = 0.85
    private let maximumMonitoredUTF16Count = 100_000
    private var observer: AXObserver?
    private var session: Session?
    private var pendingStartID: UUID?
    private var reviewWorkItem: DispatchWorkItem?
    private var expirationWorkItem: DispatchWorkItem?

    func captureFocusedEditableElement() -> AXUIElement? {
        guard AXIsProcessTrusted(),
              let element = focusedElement(),
              isSafeEditable(element) else {
            return nil
        }
        return element
    }

    func beginMonitoringAfterPaste(
        originalText: String,
        targetElement: AXUIElement,
        verificationDelay: TimeInterval = 0.32
    ) {
        stop()
        guard !originalText.isEmpty,
              originalText.utf16.count <= maximumMonitoredUTF16Count else {
            return
        }

        let startID = UUID()
        pendingStartID = startID
        DispatchQueue.main.asyncAfter(deadline: .now() + verificationDelay) { [weak self] in
            guard let self, self.pendingStartID == startID else { return }
            self.pendingStartID = nil
            self.startVerifiedSession(
                originalText: originalText,
                targetElement: targetElement
            )
        }
    }

    func stop() {
        pendingStartID = nil
        reviewWorkItem?.cancel()
        reviewWorkItem = nil
        expirationWorkItem?.cancel()
        expirationWorkItem = nil

        if let observer, let element = session?.element {
            AXObserverRemoveNotification(
                observer,
                element,
                kAXValueChangedNotification as CFString
            )
            AXObserverRemoveNotification(
                observer,
                element,
                kAXSelectedTextChangedNotification as CFString
            )
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        session = nil
    }

    fileprivate func handleAccessibilityNotification(
        element: AXUIElement,
        notification: String
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleAccessibilityNotification(
                    element: element,
                    notification: notification
                )
            }
            return
        }
        guard let activeSession = session,
              CFEqual(activeSession.element, element) else {
            return
        }

        if notification == kAXSelectedTextChangedNotification as String {
            recordSelectionChange()
        } else if notification == kAXValueChangedNotification as String {
            recordValueChange()
        }
    }

    private func startVerifiedSession(
        originalText: String,
        targetElement: AXUIElement
    ) {
        guard AXIsProcessTrusted(),
              isSafeEditable(targetElement),
              let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let focused = focusedElement(),
              CFEqual(focused, targetElement) else {
            return
        }

        var targetPID: pid_t = 0
        guard AXUIElementGetPid(targetElement, &targetPID) == .success,
              targetPID == frontmostPID,
              let selection = selectedTextRange(of: targetElement),
              selection.length == 0 else {
            return
        }

        let originalLength = originalText.utf16.count
        let startLocation = selection.location - originalLength
        guard startLocation >= 0,
              let characterCount = numberOfCharacters(in: targetElement),
              characterCount >= selection.location else {
            return
        }

        let range = TrackedPasteRange(
            location: startLocation,
            length: originalLength
        )
        guard string(
            in: targetElement,
            range: CFRange(location: range.location, length: range.length)
        ) == originalText else {
            return
        }

        var newObserver: AXObserver?
        guard AXObserverCreate(
            targetPID,
            pasteCorrectionObserverCallback,
            &newObserver
        ) == .success,
        let newObserver else {
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(
            newObserver,
            targetElement,
            kAXValueChangedNotification as CFString,
            refcon
        ) == .success else {
            return
        }
        _ = AXObserverAddNotification(
            newObserver,
            targetElement,
            kAXSelectedTextChangedNotification as CFString,
            refcon
        )

        observer = newObserver
        session = Session(
            element: targetElement,
            pid: targetPID,
            referenceText: originalText,
            trackedRange: range,
            characterCount: characterCount,
            currentText: originalText,
            isEditingBurst: false,
            recentSelection: nil
        )
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )

        let expiration = DispatchWorkItem { [weak self] in
            self?.stop()
        }
        expirationWorkItem = expiration
        DispatchQueue.main.asyncAfter(
            deadline: .now() + monitoringLifetime,
            execute: expiration
        )
    }

    private func recordSelectionChange() {
        guard var session,
              let selection = selectedTextRange(of: session.element) else {
            return
        }
        if selection.length > 0,
           rangesIntersect(
            selection,
            CFRange(
                location: session.trackedRange.location,
                length: session.trackedRange.length
            )
           ) {
            session.recentSelection = RecentSelection(
                range: selection,
                observedAt: Date()
            )
        }
        self.session = session
    }

    private func recordValueChange() {
        guard var session,
              let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              frontmostPID == session.pid,
              let focused = focusedElement(),
              CFEqual(focused, session.element),
              let selection = selectedTextRange(of: session.element),
              let currentCharacterCount = numberOfCharacters(in: session.element) else {
            stop()
            return
        }

        let selectionIsRecent = session.recentSelection.map {
            Date().timeIntervalSince($0.observedAt) <= 3
                && rangesIntersect(
                    $0.range,
                    CFRange(
                        location: session.trackedRange.location,
                        length: session.trackedRange.length
                    )
                )
        } ?? false

        let decision = TrackedPasteEditPolicy.evaluate(
            range: session.trackedRange,
            previousCharacterCount: session.characterCount,
            currentCharacterCount: currentCharacterCount,
            caretLocation: selection.location + selection.length,
            selectedCorrectionIntersectsRange: selectionIsRecent,
            isEditingBurst: session.isEditingBurst
        )
        session.characterCount = currentCharacterCount

        switch decision {
        case .ignore:
            self.session = session
            return
        case .shift(let newLocation):
            session.trackedRange.location = newLocation
            session.recentSelection = nil
            self.session = session
            return
        case .observe(let newLength):
            guard newLength > 0,
                  newLength <= maximumMonitoredUTF16Count,
                  session.trackedRange.location + newLength <= currentCharacterCount else {
                stop()
                return
            }
            session.trackedRange.length = newLength
        }

        guard let currentText = string(
            in: session.element,
            range: CFRange(
                location: session.trackedRange.location,
                length: session.trackedRange.length
            )
        ) else {
            stop()
            return
        }

        session.currentText = currentText
        session.isEditingBurst = true
        session.recentSelection = nil
        self.session = session
        scheduleReview()
    }

    private func scheduleReview() {
        reviewWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reviewCurrentCorrection()
        }
        reviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + reviewDelay,
            execute: workItem
        )
    }

    private func reviewCurrentCorrection() {
        reviewWorkItem = nil
        guard var session else { return }
        guard let candidate = MacVocabularyCorrectionExtractor.candidate(
            original: session.referenceText,
            edited: session.currentText
        ) else {
            session.referenceText = session.currentText
            session.isEditingBurst = false
            session.recentSelection = nil
            self.session = session
            return
        }

        stop()
        onCandidate?(candidate)
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func isSafeEditable(_ element: AXUIElement) -> Bool {
        guard stringAttribute(kAXSubroleAttribute, from: element) != "AXSecureTextField" else {
            return false
        }

        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        ) == .success,
        settable.boolValue else {
            return false
        }

        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        return ["AXTextField", "AXTextArea", "AXComboBox"].contains(role)
            || role.localizedCaseInsensitiveContains("text")
    }

    private func selectedTextRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func numberOfCharacters(in element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXNumberOfCharactersAttribute as CFString,
            &value
        ) == .success,
        let number = value as? NSNumber else {
            return nil
        }
        return number.intValue
    }

    private func string(in element: AXUIElement, range: CFRange) -> String? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private func rangesIntersect(_ lhs: CFRange, _ rhs: CFRange) -> Bool {
        lhs.location < rhs.location + rhs.length
            && rhs.location < lhs.location + lhs.length
    }
}
