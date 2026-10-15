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
    /// Reads are injectable so editor timing and missing AX capabilities can be
    /// tested without inspecting or controlling another application's UI.
    struct Environment {
        var isTrusted: () -> Bool
        var frontmostPID: () -> pid_t?
        var focusedElement: () -> AXUIElement?
        var isSafeEditable: (AXUIElement) -> Bool
        var elementPID: (AXUIElement) -> pid_t?
        var selectedRange: (AXUIElement) -> CFRange?
        var characterCount: (AXUIElement) -> Int?
        var exactRangeText: (AXUIElement, CFRange) -> String?
    }

    struct ExactRangeRead {
        let text: String?
        let method: PasteDiagnostics.RangeReadMethod
        let result: AXError
    }

    var onStatus: ((String) -> Void)?
    var onCandidate: ((MacVocabularyCandidate) -> Void)?
    var onEditingResumed: (() -> Void)?
    var onStopped: (() -> Void)?

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
        var offeredText: String?
        let leadingBoundary: String
        let trailingBoundary: String
    }

    private let monitoringLifetime: TimeInterval = 120
    private let reviewDelay: TimeInterval
    private let verificationRetryDelay: TimeInterval
    private let pollingInterval: TimeInterval
    private let environment: Environment?
    private let recordDiagnostic: (PasteDiagnostics.Event) -> Void
    private let maximumMonitoredUTF16Count = 100_000
    private var observer: AXObserver?
    private var session: Session?
    private var pendingStartID: UUID?
    private var reviewWorkItem: DispatchWorkItem?
    private var expirationWorkItem: DispatchWorkItem?
    private var pollingTimer: Timer?
    private var reportedRangeReads: Set<String> = []

    init(environment: Environment? = nil, reviewDelay: TimeInterval = 1.1,
         verificationRetryDelay: TimeInterval = 0.32, pollingInterval: TimeInterval = 0.25,
         recordDiagnostic: @escaping (PasteDiagnostics.Event) -> Void = { PasteDiagnostics.shared.record($0) }) {
        self.environment = environment
        self.reviewDelay = reviewDelay
        self.verificationRetryDelay = verificationRetryDelay
        self.pollingInterval = pollingInterval
        self.recordDiagnostic = recordDiagnostic
    }

    func captureFocusedEditableElement() -> AXUIElement? {
        guard isTrusted(),
              let element = focusedElement(),
              isSafeEditable(element) else {
            return nil
        }
        return element
    }

    /// Geometry only, from the currently verified input target. No window title
    /// or document contents are read for presentation placement.
    func presentationFrame() -> NSRect? {
        guard let session, currentTargetIsSafe(session),
              let primaryTop = NSScreen.screens.first?.frame.maxY else { return nil }
        var windowValue: CFTypeRef?
        var frame: NSRect?
        if AXUIElementCopyAttributeValue(session.element, kAXWindowAttribute as CFString, &windowValue) == .success,
           let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() {
            let window = windowValue as! AXUIElement
            if elementPID(window) == session.pid {
                frame = accessibilityFrame(of: window, primaryScreenTop: primaryTop)
            }
        }
        if frame == nil {
            frame = accessibilityFrame(of: session.element, primaryScreenTop: primaryTop)
        }
        guard currentTargetIsSafe(session) else { return nil }
        return frame
    }

    static func appKitFrame(fromAXFrame frame: NSRect, primaryScreenTop: CGFloat) -> NSRect? {
        guard primaryScreenTop.isFinite, frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { return nil }
        return NSRect(x: frame.minX, y: primaryScreenTop - frame.minY - frame.height,
                      width: frame.width, height: frame.height)
    }

    private func accessibilityFrame(of element: AXUIElement, primaryScreenTop: CGFloat) -> NSRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return Self.appKitFrame(fromAXFrame: NSRect(origin: position, size: size), primaryScreenTop: primaryScreenTop)
    }

    func beginMonitoringAfterPaste(
        originalText: String,
        targetElement: AXUIElement,
        verificationDelay: TimeInterval = 0.32
    ) {
        stop()
        reportedRangeReads.removeAll()
        guard !originalText.isEmpty,
              originalText.utf16.count <= maximumMonitoredUTF16Count else {
            onStatus?("未觀察修正：貼入文字為空或超過觀察範圍上限。")
            return
        }

        let startID = UUID()
        pendingStartID = startID
        trace(.learningStart, stage: .begin, accepted: true)
        onStatus?("正在驗證貼入範圍…")
        DispatchQueue.main.asyncAfter(deadline: .now() + verificationDelay) { [weak self] in
            guard let self, self.pendingStartID == startID else { return }
            self.startVerifiedSession(
                originalText: originalText,
                targetElement: targetElement,
                startID: startID,
                attempt: 0
            )
        }
    }

    func flushPendingCorrection() {
        guard reviewWorkItem != nil else { return }
        reviewWorkItem?.cancel()
        reviewCurrentCorrection()
    }

    func stop(reason: String = "修正觀察已停止。", diagnosticReason: PasteDiagnostics.LearningReason = .cancelled) {
        if session != nil || pendingStartID != nil {
            trace(.learningStopped, stage: .completed, reason: diagnosticReason, accepted: false)
        }
        onStopped?()
        onStatus?(reason)
        pendingStartID = nil
        reviewWorkItem?.cancel()
        reviewWorkItem = nil
        expirationWorkItem?.cancel()
        expirationWorkItem = nil
        pollingTimer?.invalidate()
        pollingTimer = nil

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

    /// Recheck at the opt-out deadline; a cached notification is not sufficient.
    func isCurrentCorrectionValid() -> Bool {
        // The deadline can beat the next polling tick. Synchronizing first lets
        // continued typing cancel the old toast and schedule a fresh review.
        if session != nil { recordValueChange() }
        guard let session, let offered = session.offeredText else { return false }
        func invalid(_ reason: PasteDiagnostics.LearningReason) -> Bool {
            trace(.learningReview, stage: .completed, reason: reason, accepted: false)
            return false
        }
        guard currentTargetIsSafe(session) else { return invalid(.targetChanged) }
        guard let selection = selectedTextRange(of: session.element) else { return invalid(.selectionUnavailable) }
        guard selection.length == 0 else { return invalid(.selectionPending) }
        guard selection.location >= session.trackedRange.location,
              selection.location <= session.trackedRange.upperBound else { return invalid(.selectionOutsideRange) }
        guard let count = numberOfCharacters(in: session.element) else { return invalid(.characterCountUnavailable) }
        guard count == session.characterCount else { return invalid(.characterCountMismatch) }
        if let failure = boundaryFailure(session) { return invalid(failure) }
        guard let text = string(in: session.element, range: CFRange(location: session.trackedRange.location,
                                                                  length: session.trackedRange.length)) else { return invalid(.rangeUnavailable) }
        guard text == offered else { return invalid(.rangeMismatch) }
        return true
    }

    /// Once accepted or declined, later edits are measured from this correction.
    func finishCurrentCorrection() {
        guard isCurrentCorrectionValid(), var session else {
            stop(reason: "修正目標已改變；未完成的自動加入已取消。", diagnosticReason: .contextChanged)
            return
        }
        session.referenceText = session.currentText
        session.offeredText = nil
        session.isEditingBurst = false
        session.recentSelection = nil
        self.session = session
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
        targetElement: AXUIElement,
        startID: UUID,
        attempt: Int
    ) {
        guard pendingStartID == startID else { return }
        func failed(_ stage: PasteDiagnostics.LearningStage, _ reason: PasteDiagnostics.LearningReason,
                    _ message: String, retry: Bool = true) {
            trace(.learningStart, stage: stage, reason: reason, accepted: false)
            if retry, attempt < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + verificationRetryDelay) { [weak self] in
                    self?.startVerifiedSession(originalText: originalText, targetElement: targetElement,
                                               startID: startID, attempt: attempt + 1)
                }
            } else {
                pendingStartID = nil
                onStatus?(message)
            }
        }
        guard isTrusted(),
              isSafeEditable(targetElement),
              let frontmostPID = frontmostPID(),
              let focused = focusedElement(),
              CFEqual(focused, targetElement) else {
            failed(.target, .targetUnavailable, "無法觀察修正：輸入目標已改變或不支援安全讀取。", retry: false)
            return
        }
        guard let targetPID = elementPID(targetElement), targetPID == frontmostPID else {
            failed(.target, .targetChanged, "無法觀察修正：輸入目標已改變。", retry: false)
            return
        }
        guard let selection = selectedTextRange(of: targetElement) else {
            failed(.selection, .selectionUnavailable, "此輸入框未提供可驗證的游標範圍，未啟用自動學習。")
            return
        }
        traceSelection(selection, tag: .learningStart)
        guard selection.length == 0 else {
            failed(.selection, .selectionPending, "貼上後游標仍在選取或組字，未啟用自動學習。")
            return
        }

        let originalLength = originalText.utf16.count
        let startLocation = selection.location - originalLength
        guard let characterCount = numberOfCharacters(in: targetElement) else {
            failed(.range, .characterCountUnavailable, "此輸入框未提供可驗證的文字長度，未啟用自動學習。")
            return
        }
        guard startLocation >= 0, characterCount >= selection.location else {
            failed(.range, .invalidRange, "貼入文字的游標範圍無法驗證，未啟用自動學習。")
            return
        }

        let range = TrackedPasteRange(
            location: startLocation,
            length: originalLength
        )
        guard let pasted = string(
            in: targetElement,
            range: CFRange(location: range.location, length: range.length)
        ) else {
            failed(.range, .rangeUnavailable, "此輸入框未提供限定範圍的文字讀取，未啟用自動學習。")
            return
        }
        guard pasted == originalText else {
            failed(.range, .rangeMismatch, "無法核對剛貼入的文字範圍，未啟用自動學習。")
            return
        }
        // Retain only small in-memory boundary guards, never the field's full
        // value. These catch edits crossing the range when an editor drops AX
        // selection notifications between polling ticks.
        let leadingLength = min(16, range.location)
        let trailingLength = min(16, characterCount - range.upperBound)
        guard let leadingBoundary = string(in: targetElement, range: CFRange(location: range.location - leadingLength, length: leadingLength)),
              let trailingBoundary = string(in: targetElement, range: CFRange(location: range.upperBound, length: trailingLength)) else {
            failed(.boundaries, .rangeUnavailable, "無法驗證貼入邊界，未啟用自動學習；可手動新增詞條。")
            return
        }

        var newObserver: AXObserver?
        if environment == nil { _ = AXObserverCreate(
            targetPID,
            pasteCorrectionObserverCallback,
            &newObserver
        ) }
        // Some web editors expose exact ranges but no AX notifications. Bounded
        // polling covers them without reading the document's AXValue.
        if let newObserver {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            _ = AXObserverAddNotification(newObserver, targetElement, kAXValueChangedNotification as CFString, refcon)
            _ = AXObserverAddNotification(newObserver, targetElement, kAXSelectedTextChangedNotification as CFString, refcon)
            observer = newObserver
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        }

        onStatus?("正在觀察本次貼入文字的修正，最多兩分鐘；修正後會提示六秒並自動加入字典；滑鼠移上提示會暫停倒數。")
        pendingStartID = nil
        trace(.learningStart, stage: .observing, accepted: true)
        session = Session(
            element: targetElement,
            pid: targetPID,
            referenceText: originalText,
            trackedRange: range,
            characterCount: characterCount,
            currentText: originalText,
            isEditingBurst: false,
            recentSelection: nil,
            offeredText: nil,
            leadingBoundary: leadingBoundary,
            trailingBoundary: trailingBoundary
        )
        if pollingInterval > 0 {
            let timer = Timer(timeInterval: pollingInterval, repeats: true) { [weak self] _ in self?.pollCurrentRange() }
            pollingTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        let expiration = DispatchWorkItem { [weak self] in
            self?.stop(reason: "兩分鐘觀察已結束。", diagnosticReason: .expired)
        }
        expirationWorkItem = expiration
        DispatchQueue.main.asyncAfter(
            deadline: .now() + monitoringLifetime,
            execute: expiration
        )
    }

    private func recordSelectionChange(syncValue: Bool = true) {
        // Selection notifications can arrive after the replacement has already
        // grown the text. Update its verified range before comparing boundaries.
        // An unchanged pre-edit crossing selection still stops below.
        if syncValue { recordValueChange() }
        guard var session,
              let selection = selectedTextRange(of: session.element) else {
            return
        }
        let tracked = session.trackedRange
        if TrackedPasteEditPolicy.selectionCrossesBoundary(location: selection.location, length: selection.length, range: tracked) {
            stop(reason: "選取範圍跨出本次貼入文字，已停止自動學習。", diagnosticReason: .selectionCrossesBoundary)
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
        guard var session else { return }
        guard currentTargetIsSafe(session) else {
            stop(reason: "觀察已停止：輸入目標已改變或不再安全。", diagnosticReason: .targetChanged)
            return
        }
        guard let selection = selectedTextRange(of: session.element) else {
            stop(reason: "觀察已停止：輸入框未提供可驗證的游標範圍。", diagnosticReason: .selectionUnavailable)
            return
        }
        guard let currentCharacterCount = numberOfCharacters(in: session.element) else {
            stop(reason: "觀察已停止：輸入框未提供可驗證的文字長度。", diagnosticReason: .characterCountUnavailable)
            return
        }
        let previousRangeText = string(in: session.element, range: CFRange(location: session.trackedRange.location,
                                                                         length: session.trackedRange.length))
        if currentCharacterCount == session.characterCount, previousRangeText == session.currentText { return }
        trace(.learningEdit, stage: .editing, accepted: true)
        if session.offeredText != nil {
            session.offeredText = nil
            onEditingResumed?()
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
            isEditingBurst: session.isEditingBurst,
            existingRangeTextChanged: previousRangeText != session.currentText
        )
        session.characterCount = currentCharacterCount

        switch decision {
        case .ignore:
            reviewWorkItem?.cancel()
            reviewWorkItem = nil
            self.session = session
            return
        case .shift(let newLocation):
            session.trackedRange.location = newLocation
            guard boundariesMatch(session),
                  string(in: session.element, range: CFRange(location: newLocation, length: session.trackedRange.length)) == session.currentText else {
                stop(reason: "貼入範圍已無法驗證，已停止自動學習。", diagnosticReason: .boundaryMismatch)
                return
            }
            session.recentSelection = nil
            self.session = session
            return
        case .observe(let newLength):
            guard newLength >= 0,
                  newLength <= maximumMonitoredUTF16Count,
                  session.trackedRange.location + newLength <= currentCharacterCount else {
                stop(diagnosticReason: .invalidRange)
                return
            }
            session.trackedRange.length = newLength
        }

        guard boundariesMatch(session) else {
            stop(reason: "變更跨出貼入範圍或周邊內容已改變，已停止自動學習。", diagnosticReason: .boundaryMismatch)
            return
        }

        guard let currentText = string(
            in: session.element,
            range: CFRange(
                location: session.trackedRange.location,
                length: session.trackedRange.length
            )
        ) else {
            stop(reason: "觀察已停止：文字範圍不再受支援。", diagnosticReason: .rangeUnavailable)
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
        guard session != nil else { return }
        // An edit may have arrived after the last poll but before this timer.
        // Let it restart debounce instead of treating the old snapshot as stale.
        recordValueChange()
        guard reviewWorkItem == nil else { return }
        guard var session else { return }
        func invalid(_ reason: PasteDiagnostics.LearningReason) {
            trace(.learningReview, stage: .review, reason: reason, accepted: false)
            stop(reason: "修正範圍無法再次驗證，未自動加入字典。", diagnosticReason: reason)
        }
        guard currentTargetIsSafe(session) else { invalid(.targetChanged); return }
        guard let selection = selectedTextRange(of: session.element) else { invalid(.selectionUnavailable); return }
        guard let count = numberOfCharacters(in: session.element) else { invalid(.characterCountUnavailable); return }
        guard count == session.characterCount else { invalid(.characterCountMismatch); return }
        if let failure = boundaryFailure(session) { invalid(failure); return }
        guard let text = string(in: session.element, range: CFRange(location: session.trackedRange.location,
                                                                  length: session.trackedRange.length)) else {
            invalid(.rangeUnavailable)
            return
        }
        guard text == session.currentText else { invalid(.rangeMismatch); return }
        guard selection.length == 0 else {
            trace(.learningReview, stage: .review, reason: .selectionPending, accepted: false)
            scheduleReview()
            return
        }
        guard let candidate = MacVocabularyCorrectionExtractor.candidate(
            original: session.referenceText,
            edited: session.currentText
        ) else {
            onStatus?("未發現可學習的詞彙修正，繼續觀察本次貼入範圍。")
            trace(.learningReview, stage: .review, reason: .noCandidate, accepted: false, candidateFound: false)
            // Deleting a misspelling and composing its replacement may span a
            // pause. Preserve the original until a real correction is resolved.
            session.recentSelection = nil
            self.session = session
            return
        }

        session.offeredText = session.currentText
        self.session = session
        trace(.learningReview, stage: .review, accepted: true, candidateFound: true)
        onCandidate?(candidate)
    }

    private func currentTargetIsSafe(_ session: Session) -> Bool {
        var event = PasteDiagnostics.Event(tag: .learningTarget)
        event.learningStage = .target
        event.learningReason = .targetChanged
        event.accepted = false
        let trusted = isTrusted()
        event.trusted = trusted
        guard trusted else {
            event.learningReason = .targetUnavailable
            recordDiagnostic(event)
            return false
        }

        let safe = isSafeEditable(session.element, diagnostic: &event)
        event.localEligible = safe
        guard safe else {
            recordDiagnostic(event)
            return false
        }
        let foreground = frontmostPID()
        let processMatches = foreground == session.pid
        event.frontmostAvailable = foreground != nil
        event.processMatches = processMatches
        guard processMatches else {
            recordDiagnostic(event)
            return false
        }
        // Preserve the normal validation's short-circuit order. No extra AX
        // queries are performed to fill in fields after an earlier gate fails.
        let focused = focusedElement()
        event.focusedElementAvailable = focused != nil
        guard let focused else {
            recordDiagnostic(event)
            return false
        }
        let elementMatches = CFEqual(focused, session.element)
        event.elementMatches = elementMatches
        guard elementMatches else {
            recordDiagnostic(event)
            return false
        }
        return true // Successful polling intentionally produces no event.
    }

    private func boundariesMatch(_ session: Session) -> Bool {
        boundaryFailure(session) == nil
    }

    private func boundaryFailure(_ session: Session) -> PasteDiagnostics.LearningReason? {
        let range = session.trackedRange
        let leadingLength = session.leadingBoundary.utf16.count
        let trailingLength = session.trailingBoundary.utf16.count
        guard range.location >= leadingLength,
              range.upperBound + trailingLength <= session.characterCount else { return .invalidRange }
        guard let leading = string(in: session.element, range: CFRange(location: range.location - leadingLength, length: leadingLength)),
              let trailing = string(in: session.element, range: CFRange(location: range.upperBound, length: trailingLength)) else { return .rangeUnavailable }
        return TrackedPasteEditPolicy.boundariesMatch(expectedLeading: session.leadingBoundary,
                                                    expectedTrailing: session.trailingBoundary,
                                                    currentLeading: leading, currentTrailing: trailing) ? nil : .boundaryMismatch
    }

    func pollCurrentRange() {
        guard let session else { return }
        guard currentTargetIsSafe(session) else {
            stop(reason: "輸入目標已改變，已停止自動學習。", diagnosticReason: .targetChanged)
            return
        }
        recordValueChange()
        guard self.session != nil else { return }
        recordSelectionChange(syncValue: false)
    }

    private func focusedElement() -> AXUIElement? {
        if let environment { return environment.focusedElement() }
        guard let pid = frontmostPID() else { return nil }
        let element = FocusTargetService.focusedElement(pid: pid)
        guard frontmostPID() == pid else { return nil }
        return element
    }

    private func isTrusted() -> Bool { environment?.isTrusted() ?? AXIsProcessTrusted() }

    private func frontmostPID() -> pid_t? {
        if let environment { return environment.frontmostPID() }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private func elementPID(_ element: AXUIElement) -> pid_t? {
        if let environment { return environment.elementPID(element) }
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    private func isSafeEditable(_ element: AXUIElement) -> Bool {
        var diagnostic = PasteDiagnostics.Event(tag: .learningTarget)
        return isSafeEditable(element, diagnostic: &diagnostic)
    }

    private func isSafeEditable(_ element: AXUIElement, diagnostic: inout PasteDiagnostics.Event) -> Bool {
        if let environment { return environment.isSafeEditable(element) }
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        let role = stringAttribute(kAXRoleAttribute, from: element)
        let subrole = stringAttribute(kAXSubroleAttribute, from: element)
        let enabled = boolAttribute(kAXEnabledAttribute, from: element)
        let readOnly = boolAttribute("AXReadOnly", from: element)
        let explicitlyEditable = boolAttribute("AXEditable", from: element)
        let protectedContent = boolAttribute("AXProtectedContent", from: element)
        // Reuse exactly the metadata already required by the safety policy.
        diagnostic.queryResult = result.rawValue
        diagnostic.canSetValue = result == .success && settable.boolValue
        diagnostic.role = PasteDiagnostics.Role(attribute: role)
        diagnostic.subrole = PasteDiagnostics.Subrole(attribute: subrole)
        diagnostic.enabled = enabled
        diagnostic.readOnly = readOnly
        diagnostic.explicitlyEditable = explicitlyEditable
        diagnostic.protectedContent = protectedContent
        return FocusTargetService.isLocalPasteTarget(
            role: role ?? "",
            subrole: subrole,
            canSetValue: result == .success && settable.boolValue,
            isEnabled: enabled,
            isReadOnly: readOnly,
            isExplicitlyEditable: explicitlyEditable,
            hasProtectedContent: protectedContent
        )
    }

    private func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private func selectedTextRange(of element: AXUIElement) -> CFRange? {
        if let environment { return environment.selectedRange(element) }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard result == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID() else {
            trace(.learningStart, stage: .selection, reason: .selectionUnavailable, accepted: false, queryResult: result.rawValue)
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func numberOfCharacters(in element: AXUIElement) -> Int? {
        if let environment { return environment.characterCount(element) }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXNumberOfCharactersAttribute as CFString,
            &value
        )
        guard result == .success,
        let number = value as? NSNumber else {
            trace(.learningStart, stage: .range, reason: .characterCountUnavailable, accepted: false, queryResult: result.rawValue)
            return nil
        }
        return number.intValue
    }

    private func string(in element: AXUIElement, range: CFRange) -> String? {
        if range.length == 0 { return "" }
        if let environment { return environment.exactRangeText(element, range) }
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }
        func read(_ attribute: CFString) -> (AXError, CFTypeRef?) {
            var value: CFTypeRef?
            let result = AXUIElementCopyParameterizedAttributeValue(element, attribute, rangeValue, &value)
            return (result, value)
        }
        let result = Self.readExactRange(
            plain: { read(kAXStringForRangeParameterizedAttribute as CFString) },
            attributed: { read(kAXAttributedStringForRangeParameterizedAttribute as CFString) }
        )
        let signature = "\(result.method.rawValue):\(result.result.rawValue)"
        if reportedRangeReads.insert(signature).inserted {
            var event = PasteDiagnostics.Event(tag: .learningStart)
            event.learningStage = .range
            event.rangeReadMethod = result.method
            event.rangeReadable = result.text != nil
            event.queryResult = result.result.rawValue
            recordDiagnostic(event)
        }
        return result.text
    }

    /// Both readers receive the same exact CFRange; never fall back to AXValue.
    static func readExactRange(plain: () -> (AXError, CFTypeRef?),
                               attributed: () -> (AXError, CFTypeRef?)) -> ExactRangeRead {
        let direct = plain()
        if direct.0 == .success, let text = direct.1 as? String {
            return ExactRangeRead(text: text, method: .plain, result: direct.0)
        }
        let styled = attributed()
        let text = styled.0 == .success ? (styled.1 as? NSAttributedString)?.string : nil
        return ExactRangeRead(text: text, method: .attributed, result: styled.0)
    }

    private func trace(_ tag: PasteDiagnostics.Tag, stage: PasteDiagnostics.LearningStage,
                       reason: PasteDiagnostics.LearningReason? = nil, accepted: Bool,
                       queryResult: Int32? = nil, candidateFound: Bool? = nil) {
        var event = PasteDiagnostics.Event(tag: tag)
        event.learningStage = stage
        event.learningReason = reason
        event.accepted = accepted
        event.queryResult = queryResult
        event.candidateFound = candidateFound
        if stage == .observing {
            event.selectionAvailable = true
            event.characterCountAvailable = true
            event.rangeReadable = true
            event.rangeMatches = true
            event.boundariesMatch = true
        }
        switch reason {
        case .selectionUnavailable: event.selectionAvailable = false
        case .selectionPending:
            event.selectionAvailable = true
            event.selectionCollapsed = false
        case .characterCountUnavailable: event.characterCountAvailable = false
        case .rangeUnavailable: event.rangeReadable = false
        case .rangeMismatch:
            event.rangeReadable = true
            event.rangeMatches = false
        case .boundaryMismatch: event.boundariesMatch = false
        default: break
        }
        recordDiagnostic(event)
    }

    private func traceSelection(_ selection: CFRange, tag: PasteDiagnostics.Tag) {
        var event = PasteDiagnostics.Event(tag: tag)
        event.learningStage = .selection
        event.selectionAvailable = true
        event.selectionCollapsed = selection.length == 0
        recordDiagnostic(event)
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
