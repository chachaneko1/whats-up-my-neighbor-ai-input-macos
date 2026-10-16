import AppKit
import ApplicationServices

private final class SyntheticEditor {
    let element = AXUIElementCreateApplication(1) // Identity token; never queried.
    let replacementElement = AXUIElementCreateApplication(2)
    var text: String
    var selection: CFRange
    var trusted = true
    var focused = true
    var safe = true
    var foregroundPID: pid_t = 123
    var focusAvailable = true
    var focusReplaced = false
    var countAvailable = true
    var selectionAvailable = true
    var unavailableRangeReads = 0
    var countQueries = 0
    var selectionQueries = 0
    var safetyQueries = 0
    var safetyOverride: ((Int) -> Bool)?
    var selectionOverride: ((Int) -> CFRange?)?
    var countOverride: ((Int) -> Int?)?
    var rangeOverride: ((CFRange, Int) -> String?)?
    var rangeReads: [CFRange] = []
    var statuses: [String] = []
    var candidates: [MacVocabularyCandidate] = []
    var stopped = 0
    var editsResumed = 0
    var diagnosticEvents: [PasteDiagnostics.Event] = []

    init(text: String, caret: Int? = nil) {
        self.text = text
        selection = CFRange(location: caret ?? text.utf16.count, length: 0)
    }

    func monitor(reviewDelay: TimeInterval = 0.02) -> PasteCorrectionMonitor {
        let environment = PasteCorrectionMonitor.Environment(
            isTrusted: { self.trusted },
            frontmostPID: { self.focused ? self.foregroundPID : nil },
            focusedElement: { self.focused && self.focusAvailable ? (self.focusReplaced ? self.replacementElement : self.element) : nil },
            isSafeEditable: { _ in
                self.safetyQueries += 1
                return self.safetyOverride?(self.safetyQueries) ?? self.safe
            },
            elementPID: { _ in 123 },
            selectedRange: { _ in
                self.selectionQueries += 1
                if let override = self.selectionOverride { return override(self.selectionQueries) }
                return self.selectionAvailable ? self.selection : nil
            },
            characterCount: { _ in
                self.countQueries += 1
                if let override = self.countOverride { return override(self.countQueries) }
                return self.countAvailable ? self.text.utf16.count : nil
            },
            exactRangeText: { _, range in
                self.rangeReads.append(range)
                if let override = self.rangeOverride { return override(range, self.rangeReads.count) }
                if self.unavailableRangeReads > 0 {
                    self.unavailableRangeReads -= 1
                    return nil
                }
                let value = self.text as NSString
                guard range.location >= 0, range.length >= 0,
                      range.location + range.length <= value.length else { return nil }
                return value.substring(with: NSRange(location: range.location, length: range.length))
            }
        )
        let monitor = PasteCorrectionMonitor(environment: environment, reviewDelay: reviewDelay,
                                             verificationRetryDelay: 0.01, pollingInterval: 0,
                                             recordDiagnostic: { self.diagnosticEvents.append($0) })
        monitor.onStatus = { self.statuses.append($0) }
        monitor.onCandidate = { self.candidates.append($0) }
        monitor.onStopped = { self.stopped += 1 }
        monitor.onEditingResumed = { self.editsResumed += 1 }
        return monitor
    }

    func replace(_ text: String, selection: CFRange? = nil) {
        self.text = text
        self.selection = selection ?? CFRange(location: text.utf16.count, length: 0)
    }

    var observing: Bool { statuses.contains { $0.contains("正在觀察本次") } }
}

@main enum PasteCorrectionMonitorTests {
    private static var assertions = 0

    private static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        assertions += 1
    }

    private static func settle(_ seconds: TimeInterval = 0.05) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private static func begin(_ monitor: PasteCorrectionMonitor, _ editor: SyntheticEditor, original: String) {
        monitor.beginMonitoringAfterPaste(originalText: original, targetElement: editor.element, verificationDelay: 0)
        settle(0.005)
    }

    static func main() {
        testBoundedReaderFallback()
        testStartRetries()
        testSelectionRaceAndComposition()
        testDeletionPause()
        testContextAndPendingChanges()
        testDeadlineRaces()
        testPresentationCoordinates()
        testFailedTargetDiagnostics()
        testReviewAndCommitFailureDiagnostics()
        print("PasteCorrectionMonitorTests passed: \(assertions) injected checks; no external UI or clipboard access")
    }

    private static func testBoundedReaderFallback() {
        var fallbackCalls = 0
        let plain = PasteCorrectionMonitor.readExactRange(plain: { (.success, "NekoAI" as CFString) }, attributed: {
            fallbackCalls += 1
            return (.success, NSAttributedString(string: "unused"))
        })
        check(plain.text == "NekoAI" && plain.method == .plain && fallbackCalls == 0,
              "A supported exact plain reader should not call another reader")
        let fallback = PasteCorrectionMonitor.readExactRange(plain: { (.parameterizedAttributeUnsupported, nil) }, attributed: {
            fallbackCalls += 1
            return (.success, NSAttributedString(string: "NekoAI"))
        })
        check(fallback.text == "NekoAI" && fallback.method == .attributed && fallbackCalls == 1,
              "Attributed exact-range text supports editors without AXStringForRange")
        let unavailable = PasteCorrectionMonitor.readExactRange(plain: { (.cannotComplete, nil) },
                                                               attributed: { (.parameterizedAttributeUnsupported, nil) })
        check(unavailable.text == nil, "No document-wide fallback is permitted")
        let malformed = PasteCorrectionMonitor.readExactRange(plain: { (.success, NSNumber(value: 3)) },
                                                             attributed: { (.success, "untyped" as CFString) })
        check(malformed.text == nil, "Unexpected AX value types are not text")
    }

    private static func testPresentationCoordinates() {
        check(PasteCorrectionMonitor.appKitFrame(fromAXFrame: NSRect(x: 100, y: 100, width: 400, height: 300),
                                                 primaryScreenTop: 900) == NSRect(x: 100, y: 500, width: 400, height: 300),
              "Primary-screen AX coordinates flip around the primary screen's top")
        check(PasteCorrectionMonitor.appKitFrame(fromAXFrame: NSRect(x: -1800, y: 200, width: 800, height: 600),
                                                 primaryScreenTop: 900) == NSRect(x: -1800, y: 100, width: 800, height: 600),
              "A monitor to the left retains its negative global x coordinate")
        check(PasteCorrectionMonitor.appKitFrame(fromAXFrame: NSRect(x: 100, y: -1000, width: 500, height: 700),
                                                 primaryScreenTop: 900) == NSRect(x: 100, y: 1200, width: 500, height: 700),
              "A monitor above the primary screen maps into positive AppKit y")
        check(PasteCorrectionMonitor.appKitFrame(fromAXFrame: NSRect(x: 1600, y: 1100, width: 500, height: 400),
                                                 primaryScreenTop: 900) == NSRect(x: 1600, y: -600, width: 500, height: 400),
              "A monitor below the primary screen maps into negative AppKit y")
        check(PasteCorrectionMonitor.appKitFrame(fromAXFrame: .zero, primaryScreenTop: 900) == nil,
              "Missing geometry must not place a toast on a guessed target")
        check(PasteCorrectionMonitor.appKitFrame(fromAXFrame: NSRect(x: 0, y: 0, width: 40, height: 40),
                                                 primaryScreenTop: .infinity) == nil,
              "Non-finite geometry is rejected")
    }

    private static func testFailedTargetDiagnostics() {
        func failure(_ mutate: (SyntheticEditor) -> Void) -> PasteDiagnostics.Event {
            let editor = SyntheticEditor(text: "NekoEye")
            let monitor = editor.monitor()
            defer { monitor.stop() }
            begin(monitor, editor, original: "NekoEye")
            editor.diagnosticEvents.removeAll()
            monitor.pollCurrentRange()
            check(editor.diagnosticEvents.isEmpty, "Successful polling must not fill diagnostic history")
            mutate(editor)
            monitor.pollCurrentRange()
            let failures = editor.diagnosticEvents.filter { $0.tag == .learningTarget }
            check(failures.count == 1 && failures[0].accepted == false && editor.candidates.isEmpty,
                  "A failed target check emits one metadata event and cannot create a candidate")
            return failures[0]
        }
        let untrusted = failure { $0.trusted = false }
        check(untrusted.trusted == false && untrusted.learningReason == .targetUnavailable,
              "Permission loss has an explicit trust failure")
        let unsafe = failure { $0.safe = false }
        check(unsafe.localEligible == false && unsafe.elementMatches == nil,
              "An unsafe field is identified without querying later focus gates")
        let missingApp = failure { $0.focused = false }
        check(missingApp.frontmostAvailable == false && missingApp.processMatches == false,
              "Missing foreground app is reported separately")
        let otherApp = failure { $0.foregroundPID = 456 }
        check(otherApp.frontmostAvailable == true && otherApp.processMatches == false,
              "Changing applications must not resemble a recreated text field")
        let missingFocus = failure { $0.focusAvailable = false }
        check(missingFocus.processMatches == true && missingFocus.focusedElementAvailable == false,
              "Missing AX focus in the same app is identifiable")
        let replaced = failure { $0.focusReplaced = true }
        check(replaced.localEligible == true && replaced.processMatches == true
              && replaced.focusedElementAvailable == true && replaced.elementMatches == false,
              "A replaced focused object is identifiable without rebinding or logging identity")

        for unavailableCount in [false, true] {
            let editor = SyntheticEditor(text: "NekoEye")
            let monitor = editor.monitor()
            begin(monitor, editor, original: "NekoEye")
            editor.diagnosticEvents.removeAll()
            if unavailableCount { editor.countAvailable = false }
            else { editor.selectionAvailable = false }
            monitor.pollCurrentRange()
            let stopped = editor.diagnosticEvents.first { $0.tag == .learningStopped }
            check(stopped?.learningReason == (unavailableCount ? .characterCountUnavailable : .selectionUnavailable),
                  "Missing selection/count uses a specific stop reason rather than contextChanged")
            check(!editor.diagnosticEvents.contains { $0.tag == .learningTarget },
                  "Range capability failures do not masquerade as focus failures")
            monitor.stop()
        }
    }

    private static func testReviewAndCommitFailureDiagnostics() {
        typealias Failure = (reason: PasteDiagnostics.LearningReason, configure: (SyntheticEditor) -> Void)
        let failures: [Failure] = [
            (.targetChanged, { editor in editor.safetyOverride = { $0 != 2 } }),
            (.selectionUnavailable, { editor in
                editor.selectionOverride = { $0 == 2 ? nil : editor.selection }
            }),
            (.characterCountUnavailable, { editor in
                editor.countOverride = { $0 == 2 ? nil : editor.text.utf16.count }
            }),
            (.characterCountMismatch, { editor in
                editor.countOverride = { editor.text.utf16.count + ($0 == 2 ? 1 : 0) }
            }),
            (.rangeUnavailable, { editor in
                editor.rangeOverride = { range, _ in
                    range.location == 0 ? nil : (editor.text as NSString).substring(with: NSRange(location: range.location, length: range.length))
                }
            }),
            (.boundaryMismatch, { editor in
                editor.rangeOverride = { range, _ in
                    range.location == 0 ? "hellX " : (editor.text as NSString).substring(with: NSRange(location: range.location, length: range.length))
                }
            }),
            (.rangeUnavailable, { editor in
                editor.rangeOverride = { range, read in
                    read == 4 ? nil : (editor.text as NSString).substring(with: NSRange(location: range.location, length: range.length))
                }
            }),
            (.rangeMismatch, { editor in
                editor.rangeOverride = { range, read in
                    read == 4 ? "NekoZZ" : (editor.text as NSString).substring(with: NSRange(location: range.location, length: range.length))
                }
            })
        ]
        let commitOnly: [Failure] = [
            (.selectionPending, { editor in
                editor.selectionOverride = { $0 == 2 ? CFRange(location: 6, length: 2) : editor.selection }
            }),
            (.selectionOutsideRange, { editor in
                editor.selectionOverride = { $0 == 2 ? CFRange(location: 0, length: 0) : editor.selection }
            })
        ]
        for committing in [false, true] {
            for failure in failures + (committing ? commitOnly : []) {
                let editor = SyntheticEditor(text: "hello NekoEye world", caret: 13)
                let monitor = editor.monitor()
                begin(monitor, editor, original: "NekoEye")
                editor.replace("hello NekoAI world", selection: CFRange(location: 12, length: 0))
                monitor.pollCurrentRange()
                if committing {
                    settle()
                    check(editor.candidates.count == 1, "Commit revalidation fixture must first offer a candidate")
                }
                editor.diagnosticEvents.removeAll()
                editor.safetyQueries = 0
                editor.selectionQueries = 0
                editor.countQueries = 0
                editor.rangeReads.removeAll()
                failure.configure(editor)
                if committing {
                    check(!monitor.isCurrentCorrectionValid(), "An invalid commit snapshot cannot be accepted")
                } else {
                    settle()
                    check(editor.candidates.isEmpty, "A failed review snapshot cannot offer a candidate")
                }
                let diagnostic = editor.diagnosticEvents.first {
                    $0.tag == .learningReview && $0.learningStage == (committing ? .completed : .review)
                }
                check(diagnostic?.learningReason == failure.reason && diagnostic?.accepted == false,
                      "Each review/commit gate must identify its exact failure without generic contextChanged")
                if !committing {
                    check(editor.diagnosticEvents.first { $0.tag == .learningStopped }?.learningReason == failure.reason,
                          "Review stop reason must preserve the failed gate")
                }
                monitor.stop()
            }
        }
    }

    private static func testStartRetries() {
        let transient = SyntheticEditor(text: "NekoAI")
        transient.unavailableRangeReads = 1
        let monitor = transient.monitor()
        defer { monitor.stop() }
        begin(monitor, transient, original: "NekoAI")
        settle()
        check(transient.observing, "A transient post-paste range failure should retry the same target")
        check(transient.rangeReads.count >= 2, "The retry must read the exact range again")

        let delayed = SyntheticEditor(text: "")
        let delayedMonitor = delayed.monitor()
        defer { delayedMonitor.stop() }
        begin(delayedMonitor, delayed, original: "NekoAI")
        delayed.replace("NekoAI")
        settle()
        check(delayed.observing, "Asynchronous paste realization can finish during the short retry window")

        let missing = SyntheticEditor(text: "NekoAI")
        missing.countAvailable = false
        let missingMonitor = missing.monitor()
        defer { missingMonitor.stop() }
        begin(missingMonitor, missing, original: "NekoAI")
        settle(0.08)
        check(!missing.observing && missing.countQueries == 4, "Unsupported character counts stop after four bounded attempts")
        check(missing.rangeReads.isEmpty, "Missing counts must not trigger broad text reads")
        missing.countAvailable = true
        settle()
        check(!missing.observing, "An expired verification window must not restart silently")

        let moved = SyntheticEditor(text: "NekoAI")
        // Move focus as part of the failed read so a busy run loop cannot
        // complete the retry before the fixture changes the target.
        moved.rangeOverride = { _, _ in
            moved.focused = false
            return nil
        }
        let movedMonitor = moved.monitor()
        defer { movedMonitor.stop() }
        begin(movedMonitor, moved, original: "NekoAI")
        settle()
        moved.focused = true
        settle()
        check(!moved.observing && moved.rangeReads.count == 1, "Retries cannot follow the user to a different target")
    }

    private static func testSelectionRaceAndComposition() {
        let editor = SyntheticEditor(text: "NekoAI")
        let monitor = editor.monitor()
        defer { monitor.stop() }
        begin(monitor, editor, original: "NekoAI")
        let before = editor.stopped
        // Poll observes the new marked selection beyond the *old* range. The
        // value/length must be incorporated before the crossing-selection check.
        editor.replace("NekoEyes", selection: CFRange(location: 4, length: 4))
        monitor.pollCurrentRange()
        settle(0.08)
        check(editor.stopped == before && editor.candidates.isEmpty,
              "An in-range IME replacement may grow past the old endpoint and remain pending")
        editor.selection = CFRange(location: 8, length: 0)
        monitor.pollCurrentRange()
        settle()
        check(editor.candidates.count == 1 && editor.candidates[0].suggestedTerm == "NekoEyes",
              "Collapsing marked text after a pause must still produce the correction")
        check(monitor.isCurrentCorrectionValid(), "The offered correction retains the validated target")

        let crossing = SyntheticEditor(text: "hello NekoAI world", caret: 12)
        let crossingMonitor = crossing.monitor()
        defer { crossingMonitor.stop() }
        begin(crossingMonitor, crossing, original: "NekoAI")
        crossing.selection = CFRange(location: 4, length: 5)
        crossingMonitor.pollCurrentRange()
        check(crossing.statuses.last?.contains("選取範圍跨出") == true,
              "A pre-edit selection crossing the original boundary must still stop")
        crossing.replace("hellXYZAI world", selection: CFRange(location: 7, length: 0))
        crossingMonitor.pollCurrentRange()
        settle()
        check(crossing.candidates.isEmpty, "A stopped crossing selection must not create a candidate")

        let missed = SyntheticEditor(text: "hello apple world", caret: 11)
        let missedMonitor = missed.monitor()
        defer { missedMonitor.stop() }
        begin(missedMonitor, missed, original: "apple")
        missed.replace("hellXYZle world", selection: CFRange(location: 7, length: 0))
        missedMonitor.pollCurrentRange()
        settle()
        check(missed.candidates.isEmpty && missed.statuses.last?.contains("跨出貼入範圍") == true,
              "Boundary guards must catch crossing replacements even when the selection event was missed")
    }

    private static func testDeletionPause() {
        let editor = SyntheticEditor(text: "NekoEye")
        let monitor = editor.monitor()
        defer { monitor.stop() }
        begin(monitor, editor, original: "NekoEye")
        editor.replace("")
        monitor.pollCurrentRange()
        settle()
        check(editor.candidates.isEmpty, "Temporarily deleting the whole dictated term does not learn an empty word")
        editor.replace("NekoAI")
        monitor.pollCurrentRange()
        settle()
        check(editor.candidates.count == 1 && editor.candidates[0].originalSegment == "NekoEye"
              && editor.candidates[0].suggestedTerm == "NekoAI",
              "Typing a replacement after a deletion pause must retain the original correction baseline")
    }

    private static func testContextAndPendingChanges() {
        let editor = SyntheticEditor(text: "NekoEye")
        let monitor = editor.monitor()
        defer { monitor.stop() }
        begin(monitor, editor, original: "NekoEye")
        editor.replace("NekoAI")
        monitor.pollCurrentRange()
        settle()
        check(editor.candidates.count == 1, "A regular correction should be offered")
        editor.replace("NekoAIs")
        monitor.pollCurrentRange()
        check(editor.editsResumed == 1 && !monitor.isCurrentCorrectionValid(),
              "More typing invalidates the offer before its opt-out deadline")
        editor.safe = false
        monitor.pollCurrentRange()
        settle()
        check(!monitor.isCurrentCorrectionValid() && editor.candidates.count == 1,
              "A secure or unsafe target ends monitoring and prevents a replacement offer")
    }

    private static func testDeadlineRaces() {
        let editor = SyntheticEditor(text: "NekoEye")
        // Drive review boundaries explicitly so a busy CI run loop cannot
        // deliver both debounce timers before the intermediate assertion.
        let monitor = editor.monitor(reviewDelay: 60)
        defer { monitor.stop() }
        begin(monitor, editor, original: "NekoEye")
        editor.replace("NekoAI")
        monitor.pollCurrentRange()
        let stoppedBefore = editor.stopped
        editor.replace("NekoEyes")
        monitor.flushPendingCorrection()
        check(editor.candidates.isEmpty && editor.stopped == stoppedBefore,
              "An edit between the last poll and review timer restarts debounce without stopping")
        monitor.flushPendingCorrection()
        check(editor.candidates.count == 1 && editor.candidates[0].suggestedTerm == "NekoEyes",
              "The re-debounced review offers the latest edit even if no notification arrived")

        // Simulate another edit immediately before the toast's expiry, without
        // a polling tick. Validation must notify cancellation before resolving.
        editor.replace("NekoEyelet")
        check(!monitor.isCurrentCorrectionValid() && editor.editsResumed == 1,
              "Deadline validation synchronizes unseen edits and cancels the prior offer")
        check(editor.stopped == stoppedBefore, "An outdated toast does not stop the next correction session")
        monitor.flushPendingCorrection()
        check(editor.candidates.count == 2 && editor.candidates[1].suggestedTerm == "NekoEyelet",
              "The replacement candidate is still offered after deadline cancellation")
    }
}
