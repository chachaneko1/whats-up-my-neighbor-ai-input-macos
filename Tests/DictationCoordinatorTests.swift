import Foundation

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "Test failure" }
}

private final class FakeRecorder: DictationRecording {
    var onRecordingStarted: ((URL) -> Void)?
    var onRecordingFinished: ((URL, Error?) -> Void)?
    var onStartFailed: ((URL, Error) -> Void)?
    var isBusy = false
    var averagePowerLevel: Float = -60
    var starts: [(device: String, url: URL)] = []
    var stopCount = 0
    var shutdownCount = 0
    var startsSynchronously = false
    var keepsBusyUntilFinished = false
    var onShutdown: (() -> Void)?

    func start(deviceUID: String, url: URL) {
        starts.append((deviceUID, url))
        isBusy = true
        if startsSynchronously { onRecordingStarted?(url) }
    }

    func stop() { stopCount += 1 }

    func shutdown() {
        shutdownCount += 1
        if !keepsBusyUntilFinished { isBusy = false }
        onShutdown?()
    }

    func finish(_ url: URL, error: Error? = nil) {
        isBusy = false
        onRecordingFinished?(url, error)
    }
}

private final class FakeToken: DictationCancellable {
    var cancelCount = 0
    var onCancel: (() -> Void)?
    func cancel() {
        cancelCount += 1
        onCancel?()
    }
}

private final class FakeTranscriber: DictationTranscribing {
    struct Call {
        let url: URL
        let language: LanguageSettings
        let reinforce: Bool
        let token: FakeToken
        let completion: (Result<String, Error>) -> Void
    }
    var calls: [Call] = []
    var synchronousResults: [Result<String, Error>] = []
    var completionOnCancel: Result<String, Error>?

    func transcribe(
        url: URL, language: LanguageSettings, reinforce: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> DictationCancellable {
        let token = FakeToken()
        if let result = completionOnCancel {
            token.onCancel = { completion(result) }
        }
        calls.append(Call(url: url, language: language, reinforce: reinforce, token: token, completion: completion))
        if !synchronousResults.isEmpty {
            completion(synchronousResults.removeFirst())
        }
        return token
    }

    func complete(_ index: Int, _ result: Result<String, Error>) {
        calls[index].completion(result)
    }
}

private final class FakeStorage: RecordingStorage {
    var created: [URL] = []
    var nonempty: Set<URL> = []
    var removed: [URL] = []

    func makeURL() -> URL {
        // These URLs are identities only. This fake never accesses the filesystem.
        let url = URL(fileURLWithPath: "/unused-dictation-tests/recording-\(created.count).m4a")
        created.append(url)
        return url
    }
    func isNonempty(_ url: URL) -> Bool { nonempty.contains(url) }
    func remove(_ url: URL) {
        removed.append(url)
        nonempty.remove(url)
    }
    func cleanupStaleRecordings() {}
}

private final class FakeClock {
    struct Task {
        let due: Date
        let action: () -> Void
    }
    var time = Date(timeIntervalSince1970: 1_000)
    var tasks: [Task] = []
    func schedule(_ delay: TimeInterval, action: @escaping () -> Void) {
        tasks.append(Task(due: time.addingTimeInterval(delay), action: action))
    }
    func advance(_ seconds: TimeInterval, runTimers: Bool = true) {
        time = time.addingTimeInterval(seconds)
        if runTimers { runDueTimers() }
    }
    func runDueTimers() {
        while let index = tasks.firstIndex(where: { $0.due <= time }) {
            let task = tasks.remove(at: index)
            task.action()
        }
    }
}

private final class Fixture {
    let recorder = FakeRecorder()
    let transcriber = FakeTranscriber()
    let storage = FakeStorage()
    let clock = FakeClock()
    let coordinator: DictationCoordinator
    var states: [DictationState] = []
    var errors: [String] = []
    var retryPrompts: [UUID] = []
    var delivered: [String] = []
    var copySucceeds = true

    init() {
        coordinator = DictationCoordinator(
            recorder: recorder, transcriber: transcriber, storage: storage,
            now: { [clock] in clock.time },
            schedule: { [clock] delay, action in clock.schedule(delay, action: action) }
        )
        coordinator.onStateChange = { [weak self] in self?.states.append($0) }
        coordinator.onError = { [weak self] in self?.errors.append($0) }
        coordinator.onRetryRequested = { [weak self] id, _ in self?.retryPrompts.append(id) }
        coordinator.deliverText = { [weak self] text in
            guard let self else { return false }
            self.delivered.append(text)
            return self.copySucceeds
        }
    }

    @discardableResult
    func start(_ settings: DictationSettings = makeSettings()) -> URL {
        precondition(coordinator.start(deviceUID: "test-device", settings: settings))
        return recorder.starts.last!.url
    }

    @discardableResult
    func record(_ settings: DictationSettings = makeSettings()) -> URL {
        let url = start(settings)
        recorder.onRecordingStarted?(url)
        return url
    }

    @discardableResult
    func transcribe(_ settings: DictationSettings = makeSettings()) -> URL {
        let url = record(settings)
        storage.nonempty.insert(url)
        coordinator.stop()
        recorder.finish(url)
        return url
    }
}

private func makeSettings(
    language: LanguageSettings = .default,
    mode: TextOutputMode = .verbatim,
    numerals: Bool = false,
    silence: Int = 0
) -> DictationSettings {
    DictationSettings(language: language, outputMode: mode,
                      convertChineseNumerals: numerals, silenceAutoStopSeconds: silence)
}

@main
enum DictationCoordinatorTests {
    static let disallowedText = "ภาษาไทยทดสอบข้อความภาษาไทย"

    static func main() throws {
        testCommandConsumptionSkipsLanguageAndDelivery()
        testLifecycleWaitsForFinalizedAudio()
        testInvalidRecordingsNeverUpload()
        testSettingsSnapshotAndTextProcessing()
        testAutomaticRetryAndStaleRequestCallbacks()
        testDisabledAutomaticRetryAndManualLanguageGate()
        testRetainedRecordingAndManualRetry()
        testRetentionDeadlineAndReplacement()
        testRenewedRetentionIgnoresPreviousTimer()
        testCancelStartingRecordingAndNetwork()
        testCancelWaitsForRecorderFinalization()
        testStaleRecorderAndSessionCallbacks()
        testSynchronousCompletions()
        testRecordingLimits()
        testClipboardFailureRetainsAudio()
        testEmptyTranscriptAndCleanupFallback()
        testHallucinatedBoilerplateIntercepted()
        testDeliveryCanCancelWithoutDeletingANewSession()
        try testTemporaryRecordingStore()
        print("Dictation coordinator tests passed (19 scenarios)")
    }

    static func testCommandConsumptionSkipsLanguageAndDelivery() {
        let f = Fixture()
        var consumed: [String] = []
        f.coordinator.consumeTranscript = { text in consumed.append(text); return true }
        let url = f.transcribe()
        // Even a disallowed-language command must be handled before any retry,
        // text transformation, clipboard write or output side effect.
        f.transcriber.complete(0, .success(disallowedText))
        precondition(consumed == [disallowedText])
        precondition(f.delivered.isEmpty && f.retryPrompts.isEmpty)
        precondition(f.transcriber.calls.count == 1)
        precondition(f.storage.removed == [url] && f.coordinator.state == .idle)
    }

    static func testLifecycleWaitsForFinalizedAudio() {
        let f = Fixture()
        precondition(f.coordinator.state == .idle && f.coordinator.sessionID == nil)
        f.recorder.isBusy = true
        precondition(!f.coordinator.canStart)
        precondition(!f.coordinator.start(deviceUID: "busy", settings: makeSettings()))
        precondition(f.storage.created.isEmpty)
        f.recorder.isBusy = false

        let url = f.start()
        precondition(f.coordinator.state == .starting && !f.coordinator.canStart)
        precondition(f.recorder.starts.first?.device == "test-device")
        f.coordinator.stop()
        precondition(f.recorder.stopCount == 0)
        precondition(!f.coordinator.start(deviceUID: "another", settings: makeSettings()))
        f.storage.nonempty.insert(url) // A partially written file is not ready for upload.
        precondition(f.transcriber.calls.isEmpty)
        f.recorder.onRecordingStarted?(url)
        precondition(f.coordinator.state == .recording)
        f.coordinator.stop()
        f.coordinator.stop()
        precondition(f.coordinator.state == .finalizing && f.recorder.stopCount == 1)
        precondition(f.transcriber.calls.isEmpty && f.storage.removed.isEmpty)
        precondition(!f.coordinator.start(deviceUID: "another", settings: makeSettings()))
        f.recorder.finish(url)
        precondition(f.coordinator.state == .transcribing && f.transcriber.calls.count == 1)
        precondition(!f.transcriber.calls[0].reinforce && f.transcriber.calls[0].url == url)
        f.recorder.onRecordingFinished?(url, nil) // Duplicate recorder completion cannot upload twice.
        precondition(f.transcriber.calls.count == 1)
        f.transcriber.complete(0, .success("完成轉錄"))
        precondition(f.delivered == ["完成轉錄"] && f.storage.removed == [url])
        precondition(f.coordinator.state == .idle && f.coordinator.sessionID == nil)
        precondition(f.states == [.starting, .recording, .finalizing, .transcribing, .delivering, .idle])
        f.transcriber.complete(0, .success("重複結果"))
        precondition(f.delivered.count == 1 && f.storage.removed == [url])
    }

    static func testInvalidRecordingsNeverUpload() {
        let incomplete = Fixture()
        let incompleteURL = incomplete.record()
        incomplete.storage.nonempty.insert(incompleteURL)
        incomplete.coordinator.stop()
        incomplete.recorder.finish(incompleteURL, error: TestFailure())
        precondition(incomplete.transcriber.calls.isEmpty && incomplete.delivered.isEmpty)
        precondition(incomplete.coordinator.state == .idle && incomplete.storage.removed == [incompleteURL])
        precondition(incomplete.errors.count == 1)

        let empty = Fixture()
        let emptyURL = empty.record()
        empty.coordinator.stop()
        empty.recorder.finish(emptyURL)
        precondition(empty.transcriber.calls.isEmpty && empty.coordinator.state == .idle)
        precondition(empty.storage.removed == [emptyURL] && empty.errors.count == 1)

        let failedStart = Fixture()
        let failedURL = failedStart.start()
        failedStart.recorder.isBusy = false
        failedStart.recorder.onStartFailed?(failedURL, TestFailure())
        precondition(failedStart.transcriber.calls.isEmpty && failedStart.coordinator.state == .idle)
        precondition(failedStart.storage.removed == [failedURL] && failedStart.errors.count == 1)
    }

    static func testSettingsSnapshotAndTextProcessing() {
        let f = Fixture()
        var currentLanguage = LanguageSettings.default
        var currentSettings = makeSettings(language: currentLanguage, mode: .concise, numerals: true)
        let snapshot = currentSettings
        let url = f.record(currentSettings)
        currentLanguage.primary = .japanese
        currentLanguage.additional = []
        currentSettings = makeSettings(language: currentLanguage, mode: .verbatim, numerals: false)
        precondition(currentSettings != snapshot)
        f.storage.nonempty.insert(url)
        f.coordinator.stop()
        f.recorder.finish(url)
        precondition(f.transcriber.calls[0].language == snapshot.language)
        f.transcriber.complete(0, .failure(TestFailure()))
        precondition(f.coordinator.retry(sessionID: f.coordinator.sessionID!))
        precondition(f.transcriber.calls[1].language == snapshot.language)
        f.transcriber.complete(1, .success("嗯，依刑事訴訟法第一百五十九條喔"))
        precondition(f.delivered == ["依刑事訴訟法第159條"])

        let japanese = Fixture()
        japanese.transcribe(currentSettings)
        japanese.transcriber.complete(0, .success("図書館で日本語を勉強しています。"))
        precondition(japanese.delivered == ["図書館で日本語を勉強しています。"])
    }

    static func testAutomaticRetryAndStaleRequestCallbacks() {
        let f = Fixture()
        let url = f.transcribe()
        f.transcriber.complete(0, .success(disallowedText))
        precondition(f.transcriber.calls.count == 2 && f.transcriber.calls[1].reinforce)
        precondition(f.transcriber.calls[1].url == url && f.coordinator.state == .transcribing)
        precondition(f.delivered.isEmpty && f.retryPrompts.isEmpty)
        f.transcriber.complete(0, .success("舊請求遲到"))
        f.transcriber.complete(0, .failure(TestFailure()))
        precondition(f.delivered.isEmpty && f.coordinator.state == .transcribing)
        f.transcriber.complete(1, .success(disallowedText))
        precondition(f.transcriber.calls.count == 2 && f.coordinator.state == .awaitingRetry)
        precondition(f.delivered.isEmpty && f.retryPrompts.count == 1 && f.storage.removed.isEmpty)
        f.transcriber.complete(1, .success("同請求重複回呼"))
        precondition(f.delivered.isEmpty && f.retryPrompts.count == 1)

        let recovered = Fixture()
        recovered.transcribe()
        recovered.transcriber.complete(0, .success(disallowedText))
        recovered.transcriber.complete(1, .success("允許的轉錄內容"))
        precondition(recovered.delivered == ["允許的轉錄內容"])
        precondition(recovered.coordinator.state == .idle && recovered.transcriber.calls.count == 2)
    }

    static func testDisabledAutomaticRetryAndManualLanguageGate() {
        let f = Fixture()
        var language = LanguageSettings.default
        language.automaticRetryEnabled = false
        f.transcribe(makeSettings(language: language))
        f.transcriber.complete(0, .success(disallowedText))
        let id = f.coordinator.sessionID!
        precondition(f.transcriber.calls.count == 1 && f.coordinator.state == .awaitingRetry)
        precondition(f.coordinator.retry(sessionID: id))
        precondition(f.transcriber.calls.count == 2 && f.transcriber.calls[1].reinforce)
        f.transcriber.complete(1, .success(disallowedText))
        precondition(f.transcriber.calls.count == 2 && f.coordinator.state == .awaitingRetry)
        precondition(f.delivered.isEmpty && f.retryPrompts.count == 1 && f.errors.count == 1)
        precondition(f.coordinator.retry(sessionID: id))
        f.transcriber.complete(2, .success("人工重試成功"))
        precondition(f.delivered == ["人工重試成功"] && f.coordinator.state == .idle)
    }

    static func testRetainedRecordingAndManualRetry() {
        let f = Fixture()
        let url = f.transcribe()
        f.transcriber.complete(0, .failure(TestFailure()))
        let id = f.coordinator.sessionID!
        precondition(f.coordinator.state == .awaitingRetry && f.storage.removed.isEmpty)
        precondition(f.retryPrompts == [id] && f.clock.tasks.count == 1)
        precondition(!f.coordinator.retry(sessionID: UUID()))
        f.coordinator.discard(sessionID: UUID())
        precondition(f.coordinator.sessionID == id)
        precondition(f.coordinator.retry(sessionID: id))
        precondition(f.transcriber.calls[1].url == url && f.recorder.starts.count == 1)
        f.transcriber.complete(1, .failure(TestFailure()))
        precondition(f.coordinator.state == .awaitingRetry && f.retryPrompts == [id])
        precondition(f.errors.count == 1 && f.storage.removed.isEmpty)
        f.coordinator.discard(sessionID: id)
        precondition(f.coordinator.state == .idle && f.storage.removed == [url])

        let missing = Fixture()
        let missingURL = missing.transcribe()
        missing.transcriber.complete(0, .failure(TestFailure()))
        missing.storage.nonempty.remove(missingURL)
        precondition(!missing.coordinator.retry(sessionID: missing.coordinator.sessionID!))
        precondition(missing.coordinator.state == .idle && missing.transcriber.calls.count == 1)
    }

    static func testRetentionDeadlineAndReplacement() {
        let f = Fixture()
        let url = f.transcribe()
        f.transcriber.complete(0, .failure(TestFailure()))
        let id = f.coordinator.sessionID!
        f.clock.advance(119)
        precondition(f.coordinator.state == .awaitingRetry && f.storage.removed.isEmpty)
        f.clock.advance(1)
        precondition(f.coordinator.state == .idle && f.storage.removed == [url])
        precondition(!f.coordinator.retry(sessionID: id))

        // Even if the timer has not run yet, retry rejects the exact deadline.
        let delayedTimer = Fixture()
        delayedTimer.transcribe()
        delayedTimer.transcriber.complete(0, .failure(TestFailure()))
        let expiredID = delayedTimer.coordinator.sessionID!
        delayedTimer.clock.advance(120, runTimers: false)
        precondition(!delayedTimer.coordinator.retry(sessionID: expiredID))
        precondition(delayedTimer.coordinator.state == .idle)

        let replaced = Fixture()
        let oldURL = replaced.transcribe()
        replaced.transcriber.complete(0, .failure(TestFailure()))
        let oldID = replaced.coordinator.sessionID!
        let newURL = replaced.record()
        let newID = replaced.coordinator.sessionID!
        precondition(oldID != newID && replaced.storage.removed == [oldURL])
        replaced.clock.advance(120)
        replaced.coordinator.discard(sessionID: oldID)
        precondition(!replaced.coordinator.retry(sessionID: oldID))
        precondition(replaced.coordinator.state == .recording && replaced.coordinator.sessionID == newID)
        precondition(!replaced.storage.removed.contains(newURL))
    }

    static func testRenewedRetentionIgnoresPreviousTimer() {
        let f = Fixture()
        let url = f.transcribe()
        f.transcriber.complete(0, .failure(TestFailure()))
        let id = f.coordinator.sessionID!
        f.clock.advance(119)
        precondition(f.coordinator.retry(sessionID: id))
        f.transcriber.complete(1, .failure(TestFailure()))
        f.clock.advance(1) // First timer expires; second attempt still has 119 seconds.
        precondition(f.coordinator.state == .awaitingRetry && f.storage.removed.isEmpty)
        f.clock.advance(118)
        precondition(f.coordinator.state == .awaitingRetry)
        f.clock.advance(1)
        precondition(f.coordinator.state == .idle && f.storage.removed == [url])
    }

    static func testCancelStartingRecordingAndNetwork() {
        for phase in [DictationState.starting, .recording, .transcribing] {
            let f = Fixture()
            let url: URL
            switch phase {
            case .starting: url = f.start()
            case .recording: url = f.record()
            default:
                f.transcriber.completionOnCancel = .failure(TestFailure())
                url = f.transcribe()
            }
            f.recorder.onShutdown = { [weak recorder = f.recorder] in
                recorder?.onRecordingFinished?(url, TestFailure())
            }
            f.coordinator.cancel()
            precondition(f.coordinator.state == .idle && f.coordinator.sessionID == nil)
            precondition(f.storage.removed.contains(url) && f.delivered.isEmpty)
            precondition(f.errors.isEmpty && f.retryPrompts.isEmpty)
            if phase == .transcribing {
                precondition(f.transcriber.calls[0].token.cancelCount == 1)
                f.transcriber.complete(0, .success("取消後的舊結果"))
                precondition(f.delivered.isEmpty)
            } else {
                precondition(f.recorder.shutdownCount == 1)
            }
        }

        let f = Fixture()
        let url = f.start()
        f.coordinator.cancel()
        f.recorder.onRecordingStarted?(url)
        precondition(f.recorder.stopCount == 1 && f.coordinator.state == .idle)
        f.recorder.onRecordingFinished?(url, nil)
        precondition(f.transcriber.calls.isEmpty)
        f.coordinator.shutdown()
        precondition(f.coordinator.state == .idle && f.recorder.shutdownCount >= 2)
    }

    static func testStaleRecorderAndSessionCallbacks() {
        let f = Fixture()
        let oldURL = f.transcribe()
        f.coordinator.cancel()
        let currentURL = f.start()
        let currentID = f.coordinator.sessionID
        let stopped = f.recorder.stopCount
        f.recorder.onRecordingStarted?(oldURL)
        f.recorder.onStartFailed?(oldURL, TestFailure())
        f.recorder.onRecordingFinished?(oldURL, nil)
        f.transcriber.complete(0, .success("上一段遲到的結果"))
        precondition(f.coordinator.state == .starting && f.coordinator.sessionID == currentID)
        precondition(f.recorder.stopCount == stopped && f.errors.isEmpty && f.delivered.isEmpty)
        precondition(!f.storage.removed.contains(currentURL))
        f.recorder.onRecordingStarted?(currentURL)
        f.storage.nonempty.insert(currentURL)
        f.coordinator.stop()
        f.recorder.finish(currentURL)
        f.transcriber.complete(1, .success("目前的結果"))
        precondition(f.delivered == ["目前的結果"])
    }

    static func testCancelWaitsForRecorderFinalization() {
        let f = Fixture()
        f.recorder.keepsBusyUntilFinished = true
        let oldURL = f.record()
        f.storage.nonempty.insert(oldURL)
        f.coordinator.stop()
        precondition(f.coordinator.state == .finalizing && f.recorder.isBusy)
        f.coordinator.cancel()
        precondition(f.coordinator.state == .idle && !f.coordinator.canStart)
        precondition(!f.coordinator.start(deviceUID: "too-early", settings: makeSettings()))
        precondition(f.recorder.starts.count == 1 && f.transcriber.calls.isEmpty)

        // Cancellation is terminal for the session, but the recording adapter
        // remains busy until its asynchronous file finalization is complete.
        f.recorder.finish(oldURL)
        precondition(f.coordinator.canStart && f.transcriber.calls.isEmpty)
        let currentURL = f.record()
        precondition(currentURL != oldURL && f.recorder.starts.count == 2)
        f.recorder.onRecordingFinished?(oldURL, nil)
        precondition(f.coordinator.state == .recording && f.transcriber.calls.isEmpty)
        precondition(!f.storage.removed.contains(currentURL))
    }

    static func testSynchronousCompletions() {
        let f = Fixture()
        f.recorder.startsSynchronously = true
        let url = f.start()
        precondition(f.coordinator.state == .recording)
        f.storage.nonempty.insert(url)
        f.transcriber.synchronousResults = [.success(disallowedText), .success("同步重試成功")]
        f.transcriber.completionOnCancel = .failure(TestFailure())
        f.coordinator.stop()
        f.recorder.finish(url)
        precondition(f.coordinator.state == .idle && f.delivered == ["同步重試成功"])
        precondition(f.transcriber.calls.count == 2 && f.storage.removed == [url])
        precondition(f.errors.isEmpty && f.retryPrompts.isEmpty)

        // A synchronous first response must not replace the live retry's cancel token.
        let mixed = Fixture()
        mixed.transcriber.synchronousResults = [.success(disallowedText)]
        mixed.transcriber.completionOnCancel = .failure(TestFailure())
        mixed.transcribe()
        precondition(mixed.coordinator.state == .transcribing && mixed.transcriber.calls.count == 2)
        precondition(mixed.transcriber.calls[0].token.cancelCount == 1)
        precondition(mixed.transcriber.calls[1].token.cancelCount == 0)
        mixed.coordinator.cancel()
        precondition(mixed.transcriber.calls[1].token.cancelCount == 1)
        precondition(mixed.coordinator.state == .idle && mixed.errors.isEmpty && mixed.delivered.isEmpty)

        let failed = Fixture()
        failed.transcriber.synchronousResults = [.failure(TestFailure())]
        failed.transcriber.completionOnCancel = .success("失敗後取消的舊回應")
        let failedURL = failed.transcribe()
        precondition(failed.coordinator.state == .awaitingRetry && failed.retryPrompts.count == 1)
        precondition(failed.delivered.isEmpty && failed.storage.removed.isEmpty)
        failed.coordinator.discard(sessionID: failed.coordinator.sessionID!)
        precondition(failed.storage.removed == [failedURL])
    }

    static func testRecordingLimits() {
        let maximum = Fixture()
        maximum.record()
        maximum.clock.advance(299)
        maximum.coordinator.checkRecordingLimits()
        precondition(maximum.coordinator.state == .recording)
        maximum.clock.advance(1)
        maximum.coordinator.checkRecordingLimits()
        maximum.coordinator.checkRecordingLimits()
        precondition(maximum.coordinator.state == .finalizing && maximum.recorder.stopCount == 1)
        precondition(maximum.transcriber.calls.isEmpty)

        let silence = Fixture()
        silence.record(makeSettings(silence: 3))
        silence.clock.advance(2)
        silence.coordinator.checkRecordingLimits()
        precondition(silence.coordinator.state == .recording)
        silence.recorder.averagePowerLevel = -20
        silence.coordinator.checkRecordingLimits() // Speech resets the silence interval.
        silence.recorder.averagePowerLevel = -45
        silence.clock.advance(2)
        silence.coordinator.checkRecordingLimits()
        precondition(silence.coordinator.state == .recording)
        silence.clock.advance(1)
        silence.coordinator.checkRecordingLimits()
        precondition(silence.coordinator.state == .finalizing && silence.recorder.stopCount == 1)

        let disabled = Fixture()
        disabled.record(makeSettings(silence: 0))
        disabled.clock.advance(30)
        disabled.coordinator.checkRecordingLimits()
        precondition(disabled.coordinator.state == .recording && disabled.recorder.stopCount == 0)
    }

    static func testClipboardFailureRetainsAudio() {
        let f = Fixture()
        f.copySucceeds = false
        let url = f.transcribe()
        f.transcriber.complete(0, .success("不可遺失的內容"))
        precondition(f.coordinator.state == .awaitingRetry && f.storage.removed.isEmpty)
        precondition(f.storage.isNonempty(url) && f.retryPrompts.count == 1)
        f.transcriber.complete(0, .success("重複回呼"))
        precondition(f.delivered == ["不可遺失的內容"])
        f.copySucceeds = true
        precondition(f.coordinator.retry(sessionID: f.coordinator.sessionID!))
        f.transcriber.complete(1, .success("不可遺失的內容"))
        precondition(f.coordinator.state == .idle && f.storage.removed == [url])

        let noConsumer = Fixture()
        noConsumer.coordinator.deliverText = nil
        noConsumer.transcribe()
        noConsumer.transcriber.complete(0, .success("沒有剪貼簿服務"))
        precondition(noConsumer.coordinator.state == .awaitingRetry && noConsumer.storage.removed.isEmpty)
    }

    static func testEmptyTranscriptAndCleanupFallback() {
        let empty = Fixture()
        let emptyURL = empty.transcribe()
        empty.transcriber.complete(0, .success(" \n\t "))
        precondition(empty.coordinator.state == .idle && empty.storage.removed == [emptyURL])
        precondition(empty.delivered.isEmpty && empty.errors.count == 1)

        let retry = Fixture()
        retry.transcribe()
        retry.transcriber.complete(0, .failure(TestFailure()))
        precondition(retry.coordinator.retry(sessionID: retry.coordinator.sessionID!))
        retry.transcriber.complete(1, .success("\n"))
        precondition(retry.coordinator.state == .awaitingRetry && retry.storage.removed.isEmpty)
        precondition(retry.retryPrompts.count == 1 && retry.errors.count == 1)

        let cleanedAway = Fixture()
        cleanedAway.transcribe(makeSettings(mode: .standard))
        cleanedAway.transcriber.complete(0, .success("嗯"))
        precondition(cleanedAway.delivered == ["嗯"] && cleanedAway.coordinator.state == .idle)
        precondition(cleanedAway.errors.count == 1)
    }

    static func testHallucinatedBoilerplateIntercepted() {
        let f = Fixture()
        let url = f.transcribe()
        f.transcriber.complete(0, .success("請訂閱我的頻道"))
        precondition(f.coordinator.state == .idle && f.storage.removed == [url])
        precondition(f.delivered.isEmpty)
        precondition(f.errors.count == 1 && f.errors[0].contains("未清楚辨識到有效語音"))

        let retry = Fixture()
        retry.transcribe()
        retry.transcriber.complete(0, .failure(TestFailure()))
        precondition(retry.coordinator.retry(sessionID: retry.coordinator.sessionID!))
        retry.transcriber.complete(1, .success("請按讚、分享、開啟小鈴鐺"))
        precondition(retry.coordinator.state == .awaitingRetry && retry.storage.removed.isEmpty)
        precondition(retry.delivered.isEmpty)
    }

    static func testDeliveryCanCancelWithoutDeletingANewSession() {
        let f = Fixture()
        let oldURL = f.transcribe()
        var newURL: URL?
        f.coordinator.deliverText = { _ in
            f.coordinator.cancel()
            newURL = f.start()
            return true
        }
        f.transcriber.complete(0, .success("交付時已切換工作"))
        precondition(f.coordinator.state == .starting && newURL != nil)
        precondition(f.storage.removed == [oldURL] && !f.storage.removed.contains(newURL!))
        f.coordinator.deliverText = nil
    }

    static func testTemporaryRecordingStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DictationCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TemporaryRecordingStore(directory: directory)
        let first = store.makeURL()
        let second = store.makeURL()
        precondition(first != second && first.deletingLastPathComponent() == directory)
        precondition(!store.isNonempty(first))
        try Data().write(to: first)
        precondition(!store.isNonempty(first))
        try Data([1, 2, 3]).write(to: first)
        precondition(store.isNonempty(first))
        store.remove(first)
        precondition(!FileManager.default.fileExists(atPath: first.path))
        store.remove(first) // Removing an already cleaned recording is harmless.

        let unrelated = directory.appendingPathComponent("keep.m4a")
        let otherExtension = directory.appendingPathComponent("FreeVoiceType-keep.txt")
        for file in [second, unrelated, otherExtension] { try Data([4]).write(to: file) }
        store.cleanupStaleRecordings()
        precondition(!FileManager.default.fileExists(atPath: second.path))
        precondition(FileManager.default.fileExists(atPath: unrelated.path))
        precondition(FileManager.default.fileExists(atPath: otherExtension.path))
    }
}
