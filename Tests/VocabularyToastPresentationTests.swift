import Foundation
import CoreGraphics

private final class PresentationFixture {
    struct Progress {
        var time: TimeInterval
        var remaining: TimeInterval
        var total: TimeInterval
        var paused: Bool
    }
    var now: TimeInterval = 0
    var jobs: [(TimeInterval, () -> Void)] = []
    var snapshot = VocabularyToastVisibility(panelVisible: true, panelOnActiveSpace: true,
        panelOcclusionVisible: true, panelIntersectsScreen: true, appHidden: false,
        focusUnchanged: true, panelIsKey: false, panelIsMain: false)
    var reveals = 0
    var visibleAt: [TimeInterval] = []
    var countdownAt: [TimeInterval] = []
    var completedAt: [TimeInterval] = []
    var finishedAt: [TimeInterval] = []
    var progress: [Progress] = []
    var contextChecks: [TimeInterval] = []
    var visibilityChecks: [TimeInterval] = []
    var unavailable = 0
    var contextValid = true
    var purpose: VocabularyToastPurpose?
    var duringContext: (() -> Void)?
    var duringProgress: (() -> Void)?
    lazy var subject = VocabularyToastPresentation(environment: .init(now: { [unowned self] in now }, schedule: { [unowned self] delay, action in
        jobs.append((now + delay, action))
    }))

    func show(transition: TimeInterval = 0, initiallyHovered: Bool = false) {
        subject.start(reveal: { [unowned self] in reveals += 1 }, visibility: { [unowned self] in visibilityChecks.append(now); return snapshot },
            isContextValid: { [unowned self] in contextChecks.append(now); duringContext?(); return contextValid }, onAttempt: { _ in },
            onVisible: { [unowned self] _ in visibleAt.append(now) }, transitionDuration: transition,
            onCountdownStarted: { [unowned self] in countdownAt.append(now) }, initiallyHovered: initiallyHovered,
            onProgress: { [unowned self] remaining, total, paused in
                progress.append(Progress(time: now, remaining: remaining, total: total, paused: paused))
                duringProgress?()
            }, onFinish: { [unowned self] outcome in
                switch outcome {
                case .completed(let valid, _):
                    finishedAt.append(now)
                    if purpose?.complete(isContextValid: valid) ?? valid { completedAt.append(now) }
                case .presentationUnavailable:
                    purpose?.cancel()
                    unavailable += 1
                }
            })
    }

    func advance(to time: TimeInterval) {
        while let next = jobs.enumerated().min(by: { $0.element.0 < $1.element.0 }), next.element.0 <= time {
            let job = jobs.remove(at: next.offset)
            now = job.0
            job.1()
        }
        now = time
    }
}

@main
enum VocabularyToastPresentationTests {
    static func main() {
        let normal = PresentationFixture()
        normal.show(transition: 0.18)
        precondition(normal.visibleAt.isEmpty && normal.countdownAt.isEmpty, "Never count an order request as visible synchronously")
        normal.advance(to: 0.17)
        precondition(normal.visibleAt == [0] && normal.countdownAt.isEmpty)
        normal.advance(to: 0.18)
        precondition(normal.countdownAt == [0.18])
        normal.advance(to: 6.17)
        precondition(normal.completedAt.isEmpty, "The entry animation must not consume opt-out time")
        normal.advance(to: 6.19)
        precondition(normal.completedAt.count == 1)
        precondition(abs(normal.completedAt[0] - 6.18) < 0.001,
                     "The full six-second reading period starts after the animation")

        for key in [\VocabularyToastVisibility.panelVisible, \.panelOnActiveSpace, \.panelOcclusionVisible,
                    \.panelIntersectsScreen, \.appHidden, \.focusUnchanged, \.panelIsKey, \.panelIsMain] {
            let fixture = PresentationFixture()
            fixture.snapshot[keyPath: key].toggle()
            fixture.show()
            fixture.advance(to: 3)
            precondition(fixture.completedAt.isEmpty && fixture.unavailable == 1 && fixture.countdownAt.isEmpty,
                         "Every visibility/focus gate must block automatic addition")
            precondition(fixture.reveals <= 8, "Reveal retries must be bounded")
        }

        let delayed = PresentationFixture()
        delayed.snapshot.panelOcclusionVisible = false
        delayed.show()
        delayed.advance(to: 0.19)
        precondition(delayed.countdownAt.isEmpty)
        delayed.snapshot.panelOcclusionVisible = true
        delayed.advance(to: 6.19)
        precondition(delayed.completedAt.isEmpty)
        delayed.advance(to: 6.21)
        precondition(delayed.completedAt.count == 1 && delayed.countdownAt == [0.2])

        let cancelled = PresentationFixture()
        cancelled.show()
        cancelled.advance(to: 0.5)
        cancelled.subject.cancel()
        cancelled.advance(to: 7)
        precondition(cancelled.completedAt.isEmpty && cancelled.unavailable == 0)

        let replaced = PresentationFixture()
        replaced.show()
        replaced.advance(to: 0.5)
        replaced.show()
        replaced.advance(to: 6.1)
        precondition(replaced.completedAt.isEmpty, "An older notice must not complete a newer one")
        replaced.advance(to: 6.6)
        precondition(replaced.completedAt.count == 1 && abs(replaced.completedAt[0] - 6.5) < 0.001)

        let reentrant = PresentationFixture()
        reentrant.duringContext = { reentrant.subject.cancel() }
        reentrant.show()
        reentrant.advance(to: 7)
        precondition(reentrant.completedAt.isEmpty, "Reentrant context cancellation must win")
        precondition(reentrant.contextChecks.count == 1, "Exercise cancellation at the actual commit boundary")

        let hiddenAtDeadline = PresentationFixture()
        hiddenAtDeadline.show()
        hiddenAtDeadline.advance(to: 1)
        hiddenAtDeadline.snapshot.panelVisible = false
        hiddenAtDeadline.advance(to: 3)
        precondition(hiddenAtDeadline.completedAt.isEmpty && hiddenAtDeadline.unavailable == 1)

        for key in [\VocabularyToastVisibility.panelVisible, \.panelOcclusionVisible] {
            let hiddenMidway = PresentationFixture()
            hiddenMidway.show()
            hiddenMidway.advance(to: 0.75)
            hiddenMidway.snapshot[keyPath: key] = false
            hiddenMidway.advance(to: 0.85)
            precondition(hiddenMidway.unavailable == 1, "Losing visibility must cancel during the countdown")
            hiddenMidway.snapshot[keyPath: key] = true
            hiddenMidway.advance(to: 3)
            precondition(hiddenMidway.completedAt.isEmpty && hiddenMidway.unavailable == 1,
                         "Restoring visibility before the old deadline must not revive automatic addition")
        }

        let obscuredDuringEntry = PresentationFixture()
        obscuredDuringEntry.show(transition: 0.18)
        obscuredDuringEntry.advance(to: 0.1)
        obscuredDuringEntry.snapshot.panelOcclusionVisible = false
        obscuredDuringEntry.advance(to: 3)
        precondition(obscuredDuringEntry.countdownAt.isEmpty && obscuredDuringEntry.unavailable == 1)

        let changedContext = PresentationFixture()
        changedContext.contextValid = false
        changedContext.show()
        changedContext.advance(to: 7)
        precondition(changedContext.completedAt.isEmpty && changedContext.finishedAt.count == 1)

        var dictionaryCalls = 0
        let production = VocabularyToastPurpose.learning(.init(
            complete: { valid in dictionaryCalls += 1; return valid },
            cancel: { dictionaryCalls += 1 }, reject: { dictionaryCalls += 1 }))
        let preview = PresentationFixture()
        preview.purpose = .preview
        preview.show(transition: 0.18)
        preview.advance(to: 7)
        preview.purpose?.cancel()
        preview.purpose?.reject()
        precondition(preview.visibleAt.count == 1 && preview.countdownAt == [0.18])
        precondition(preview.finishedAt.count == 1 && abs(preview.finishedAt[0] - 6.18) < 0.001)
        precondition(preview.completedAt.isEmpty && dictionaryCalls == 0,
                     "Preview must animate and count down without committing or mutating dictionary records")
        let actualLearning = PresentationFixture()
        actualLearning.purpose = production
        actualLearning.show()
        actualLearning.advance(to: 7)
        precondition(dictionaryCalls == 1 && actualLearning.completedAt.count == 1 && abs(actualLearning.completedAt[0] - 6) < 0.001,
                     "A real correction must still reach its learning callback exactly once")
        production.cancel()
        production.reject()
        precondition(dictionaryCalls == 3)
        precondition(VocabularyToastPurpose.preview.acceptsForeground(expected: 7, current: 7, ownPID: 7))
        precondition(!production.acceptsForeground(expected: 7, current: 7, ownPID: 7),
                     "Allowing our own app for preview must not relax the production focus rule")
        precondition(production.acceptsForeground(expected: 8, current: 8, ownPID: 7))
        precondition(!VocabularyToastPurpose.preview.acceptsForeground(expected: 8, current: 7, ownPID: 7))
        precondition(!VocabularyToastPurpose.preview.acceptsForeground(expected: nil, current: nil, ownPID: 7))

        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: 100, width: 1920, height: 1080)]
        precondition(VocabularyToastPlacement.screenIndex(targetFrame: CGRect(x: -1700, y: 200, width: 1500, height: 700), screenFrames: screens, fallbackIndex: 0) == 1)
        precondition(VocabularyToastPlacement.screenIndex(targetFrame: CGRect(x: -100, y: 0, width: 1000, height: 800), screenFrames: screens, fallbackIndex: 1) == 0)
        precondition(VocabularyToastPlacement.screenIndex(targetFrame: nil, screenFrames: screens, fallbackIndex: 1) == 1)
        precondition(VocabularyToastPlacement.screenIndex(targetFrame: .zero, screenFrames: [], fallbackIndex: nil) == nil)
        let placement = VocabularyToastPlacement.frame(size: CGSize(width: 576, height: 176), in: screens[1])
        precondition(placement.midX == screens[1].midX && placement.maxY == screens[1].maxY - 12)
        precondition(VocabularyToastPlacement.transitionDuration(reduceMotion: true) < VocabularyToastPlacement.transitionDuration(reduceMotion: false))
        testHoverCountdown()
        print("VocabularyToastPresentationTests passed: six-second reading time, hover pause/resume, visibility/context gates during pauses, reentrancy, placement and preview isolation")
    }

    private static func testHoverCountdown() {
        let paused = PresentationFixture()
        paused.show()
        paused.advance(to: 1.25)
        paused.subject.setHovered(true)
        precondition(paused.progress.last?.paused == true && abs(paused.progress.last!.remaining - 4.75) < 0.001)
        paused.advance(to: 12)
        precondition(paused.completedAt.isEmpty && abs(paused.progress.last!.remaining - 4.75) < 0.001,
                     "Hovering longer than the entire countdown must preserve its remaining reading time")
        precondition(paused.visibilityChecks.filter { $0 >= 2 && $0 <= 10 }.count >= 150,
                     "Visibility and foreground focus checks continue at 50ms intervals throughout a hover pause")
        precondition(paused.contextChecks.isEmpty,
                     "A long hover must not cause extra high-frequency AX context checks")
        paused.subject.setHovered(false)
        paused.advance(to: 16.74)
        precondition(paused.completedAt.isEmpty)
        paused.advance(to: 16.76)
        precondition(paused.completedAt.count == 1 && abs(paused.completedAt[0] - 16.75) < 0.001,
                     "Leaving the bubble resumes the preserved time instead of restarting or consuming the pause")

        let enteredLate = PresentationFixture()
        enteredLate.show()
        enteredLate.advance(to: 5.98)
        enteredLate.subject.setHovered(true)
        enteredLate.advance(to: 9)
        precondition(enteredLate.completedAt.isEmpty)
        enteredLate.subject.setHovered(false)
        precondition(abs(enteredLate.progress.last!.remaining - 1) < 0.001,
                     "Leaving with less than one second remaining grants one second of reaction time")
        enteredLate.advance(to: 9.99)
        precondition(enteredLate.completedAt.isEmpty)
        enteredLate.advance(to: 10.01)
        precondition(enteredLate.completedAt.count == 1)

        let repeated = PresentationFixture()
        repeated.show()
        repeated.advance(to: 1)
        repeated.subject.setHovered(true)
        repeated.advance(to: 3)
        repeated.subject.setHovered(false)
        repeated.advance(to: 5)
        repeated.subject.setHovered(true)
        repeated.advance(to: 9)
        repeated.subject.setHovered(false)
        repeated.subject.setHovered(false) // Duplicate mouse-exit events are inert.
        repeated.advance(to: 11.99)
        precondition(repeated.completedAt.isEmpty)
        repeated.advance(to: 12.01)
        precondition(repeated.completedAt.count == 1 && abs(repeated.completedAt[0] - 12) < 0.001,
                     "Multiple pauses preserve accumulated active reading time")

        let initiallyHovered = PresentationFixture()
        initiallyHovered.show(transition: 0.18, initiallyHovered: true)
        initiallyHovered.advance(to: 8)
        precondition(initiallyHovered.completedAt.isEmpty && initiallyHovered.progress.last?.paused == true
                     && abs(initiallyHovered.progress.last!.remaining - 6) < 0.001,
                     "A pointer already inside the revealed bubble pauses from the first displayed frame")
        initiallyHovered.subject.setHovered(false)
        initiallyHovered.advance(to: 13.99)
        precondition(initiallyHovered.completedAt.isEmpty)
        initiallyHovered.advance(to: 14.01)
        precondition(initiallyHovered.completedAt.count == 1)

        for key in [\VocabularyToastVisibility.panelVisible, \.panelOcclusionVisible, \.focusUnchanged] {
            let hidden = PresentationFixture()
            hidden.show(initiallyHovered: true)
            hidden.advance(to: 1)
            hidden.snapshot[keyPath: key] = false
            hidden.advance(to: 1.06)
            precondition(hidden.unavailable == 1 && hidden.completedAt.isEmpty,
                         "Hovering cannot bypass visibility or foreground focus gates")
            hidden.snapshot[keyPath: key] = true
            hidden.subject.setHovered(false)
            hidden.advance(to: 20)
            precondition(hidden.completedAt.isEmpty, "Restoring a hidden paused notice cannot revive its countdown")
        }

        let obsolete = PresentationFixture()
        obsolete.show(initiallyHovered: true)
        obsolete.advance(to: 1)
        obsolete.contextValid = false
        obsolete.advance(to: 1.06)
        precondition(obsolete.contextChecks.isEmpty && obsolete.finishedAt.isEmpty)
        obsolete.subject.setHovered(false)
        obsolete.advance(to: 7.1)
        precondition(obsolete.finishedAt.count == 1 && obsolete.completedAt.isEmpty && obsolete.contextChecks.count == 1,
                     "A changed context cannot commit after a pause, even if its monitor cancellation was missed")

        let cancelled = PresentationFixture()
        cancelled.show(initiallyHovered: true)
        cancelled.advance(to: 1)
        cancelled.subject.cancel() // Includes the monitor's existing lifetime cutoff.
        cancelled.subject.setHovered(false)
        cancelled.advance(to: 130)
        precondition(cancelled.completedAt.isEmpty && cancelled.finishedAt.isEmpty,
                     "A monitor stop cancels a paused pending notice and all queued checks")

        let reentrant = PresentationFixture()
        reentrant.show(initiallyHovered: true)
        reentrant.advance(to: 1)
        reentrant.duringProgress = {
            reentrant.duringProgress = nil
            reentrant.show()
        }
        reentrant.advance(to: 1.1)
        let replacementStarted = reentrant.countdownAt.last!
        precondition(reentrant.countdownAt.count == 2)
        reentrant.advance(to: replacementStarted + 5.99)
        precondition(reentrant.completedAt.isEmpty, "A paused old notice cannot complete a reentrant replacement")
        reentrant.advance(to: replacementStarted + 6.01)
        precondition(reentrant.completedAt.count == 1 && abs(reentrant.completedAt[0] - replacementStarted - 6) < 0.001)

        let progressPause = PresentationFixture()
        progressPause.duringProgress = {
            if progressPause.progress.last?.remaining == 0 {
                progressPause.duringProgress = nil
                progressPause.subject.setHovered(true)
            }
        }
        progressPause.show()
        progressPause.advance(to: 8)
        precondition(progressPause.completedAt.isEmpty && progressPause.progress.last?.paused == true,
                     "Hover reported by the final progress callback wins over a simultaneous expiry")
        progressPause.subject.setHovered(false)
        progressPause.advance(to: 9.01)
        precondition(progressPause.completedAt.count == 1)

        let contextPause = PresentationFixture()
        contextPause.duringContext = {
            contextPause.duringContext = nil
            contextPause.subject.setHovered(true)
        }
        contextPause.show()
        contextPause.advance(to: 8)
        precondition(contextPause.completedAt.isEmpty && contextPause.progress.last?.paused == true,
                     "Hover arriving during the final context callback must also prevent completion")
        contextPause.subject.setHovered(false)
        contextPause.advance(to: 9.01)
        precondition(contextPause.completedAt.count == 1)

        let refreshedPointer = PresentationFixture()
        var pointerMovedDuringValidation = false
        refreshedPointer.duringContext = { pointerMovedDuringValidation = true }
        refreshedPointer.duringProgress = {
            if pointerMovedDuringValidation {
                refreshedPointer.duringProgress = nil
                refreshedPointer.subject.setHovered(true)
            }
        }
        refreshedPointer.show()
        refreshedPointer.advance(to: 8)
        precondition(refreshedPointer.completedAt.isEmpty && refreshedPointer.progress.last?.paused == true,
                     "The post-validation progress refresh must catch pointer entry whose mouse event was delayed")
        refreshedPointer.subject.setHovered(false)
        refreshedPointer.advance(to: 9.01)
        precondition(refreshedPointer.completedAt.count == 1)

        for replace in [false, true] {
            let postValidation = PresentationFixture()
            var validationReturned = false
            postValidation.duringContext = { validationReturned = true }
            postValidation.duringProgress = {
                guard validationReturned else { return }
                postValidation.duringProgress = nil
                if replace { postValidation.show() }
                else { postValidation.subject.cancel() }
            }
            postValidation.show()
            postValidation.advance(to: 6.1)
            precondition(postValidation.completedAt.isEmpty,
                         "Post-validation progress cancellation or replacement must invalidate the previous generation")
            postValidation.advance(to: 12.1)
            precondition(postValidation.completedAt.count == (replace ? 1 : 0))
            if replace {
                precondition(abs(postValidation.completedAt[0] - postValidation.countdownAt.last! - 6) < 0.001,
                             "A post-validation replacement receives its own full reading period")
            }
        }
    }
}
