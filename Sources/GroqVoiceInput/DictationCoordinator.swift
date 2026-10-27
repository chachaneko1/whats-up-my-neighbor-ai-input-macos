import Foundation

struct DictationSettings: Equatable {
    let language: LanguageSettings
    let outputMode: TextOutputMode
    let convertChineseNumerals: Bool
    let silenceAutoStopSeconds: Int
}

enum DictationState: Equatable {
    case idle, starting, recording, finalizing, transcribing, awaitingRetry, delivering
}

protocol DictationRecording: AnyObject {
    var onRecordingStarted: ((URL) -> Void)? { get set }
    var onRecordingFinished: ((URL, Error?) -> Void)? { get set }
    var onStartFailed: ((URL, Error) -> Void)? { get set }
    var isBusy: Bool { get }
    var averagePowerLevel: Float { get }
    func start(deviceUID: String, url: URL)
    func stop()
    func shutdown()
}

protocol DictationCancellable: AnyObject {
    func cancel()
}

protocol DictationTranscribing {
    /// The adapter delivers callbacks on the main thread. Tests can complete synchronously.
    func transcribe(
        url: URL, language: LanguageSettings, reinforce: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> DictationCancellable
}

protocol RecordingStorage {
    func makeURL() -> URL
    func isNonempty(_ url: URL) -> Bool
    func remove(_ url: URL)
    func cleanupStaleRecordings()
}

/// Owns one dictation job. All calls, recorder events and network completions are on
/// the main thread; platform adapters own their background work. No AppKit or keys.
final class DictationCoordinator {
    private struct Session {
        let id: UUID
        let url: URL
        let settings: DictationSettings
        var requestID: UUID?
        var automaticRetryUsed = false
        var startedAt: Date?
        var lastLoudAt: Date?
        var retryDeadline: Date?
    }

    private let recorder: DictationRecording
    private let transcriber: DictationTranscribing
    private let storage: RecordingStorage
    private let now: () -> Date
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var session: Session?
    private var request: DictationCancellable?
    private let maximumRecordingDuration: TimeInterval = 300
    private let retentionInterval: TimeInterval = 120

    private(set) var state: DictationState = .idle
    var sessionID: UUID? { session?.id }
    // 設計意圖：允許在等待重試（.awaitingRetry）期間直接發起新錄音。
    // 使用者若不想重試舊錄音，可直接重新講話；一旦發起新錄音，
    // 舊 session 的暫存音訊檔會在 start() 中被立即移除，確保舊任務徹底結束。
    var canStart: Bool { (state == .idle || state == .awaitingRetry) && !recorder.isBusy }
    var onStateChange: ((DictationState) -> Void)?
    var onError: ((String) -> Void)?
    var onRetryRequested: ((UUID, String) -> Void)?
    /// Return true when text is safely in the clipboard, even if paste was refused.
    /// Consume exact local commands before language processing or text delivery.
    var consumeTranscript: ((String) -> Bool)?
    var deliverText: ((String) -> Bool)?

    init(
        recorder: DictationRecording, transcriber: DictationTranscribing,
        storage: RecordingStorage, now: @escaping () -> Date = Date.init,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.storage = storage
        self.now = now
        self.schedule = schedule
        recorder.onRecordingStarted = { [weak self] url in self?.recordingStarted(url) }
        recorder.onStartFailed = { [weak self] url, error in self?.recordingFailed(url, error: error) }
        recorder.onRecordingFinished = { [weak self] url, error in self?.recordingFinished(url, error: error) }
    }

    @discardableResult
    func start(deviceUID: String, settings: DictationSettings) -> Bool {
        guard canStart else { return false }
        // Replacing a retained recording is an explicit terminal outcome.
        if let old = session { storage.remove(old.url) }
        request?.cancel()
        request = nil
        let current = Session(id: UUID(), url: storage.makeURL(), settings: settings)
        session = current
        setState(.starting)
        // 世代守衛（Generation Guard）：setState 會同步觸發外部 onStateChange 回呼。
        // 外部監聽者可能在回呼中呼叫 cancel() 或觸發狀態變更。
        // 必須維持條件：在命令底層 recorder 啟動前，確認 session 與狀態未被外部改變，避免競態。
        guard session?.id == current.id, state == .starting else { return false }
        recorder.start(deviceUID: deviceUID, url: current.url)
        return true
    }

    func stop() {
        guard state == .recording else { return }
        let id = session?.id
        setState(.finalizing)
        guard session?.id == id, state == .finalizing else { return }
        recorder.stop()
    }

    func cancel() {
        // Invalidate first: cancel/shutdown may cause a callback synchronously.
        let old = session
        session = nil
        let oldRequest = request
        request = nil
        oldRequest?.cancel()
        if recorder.isBusy { recorder.shutdown() }
        if let old { storage.remove(old.url) }
        setState(.idle)
    }

    func shutdown() {
        cancel()
        recorder.shutdown()
    }

    /// Called by the UI's lightweight meter timer, never performs UI work.
    func checkRecordingLimits() {
        guard state == .recording, let current = session, let started = current.startedAt else { return }
        let time = now()
        if time.timeIntervalSince(started) >= maximumRecordingDuration {
            stop()
            return
        }
        guard current.settings.silenceAutoStopSeconds > 0 else { return }
        if recorder.averagePowerLevel > -45 {
            session?.lastLoudAt = time
        } else if let lastLoud = current.lastLoudAt,
                  time.timeIntervalSince(lastLoud) >= Double(current.settings.silenceAutoStopSeconds) {
            stop()
        }
    }

    @discardableResult
    func retry(sessionID: UUID) -> Bool {
        guard state == .awaitingRetry, let current = session, current.id == sessionID else { return false }
        guard let deadline = current.retryDeadline, now() < deadline, storage.isNonempty(current.url) else {
            finish()
            onError?("暫存錄音已過期，請重新錄音。")
            return false
        }
        session?.retryDeadline = nil
        beginTranscription(reinforce: true, manualRetry: true)
        return true
    }

    func discard(sessionID: UUID) {
        guard session?.id == sessionID, state == .awaitingRetry else { return }
        finish()
    }

    private func recordingStarted(_ url: URL) {
        guard session?.url == url, state == .starting else {
            // A cancelled start can finish asynchronously; release it immediately.
            if session == nil { recorder.stop() }
            return
        }
        session?.startedAt = now()
        session?.lastLoudAt = now()
        setState(.recording)
    }

    private func recordingFailed(_ url: URL, error: Error) {
        guard session?.url == url, state == .starting else {
            if session?.url != url { storage.remove(url) }
            return
        }
        finish()
        onError?("無法開始錄音：\(error.localizedDescription)")
    }

    private func recordingFinished(_ url: URL, error: Error?) {
        guard session?.url == url,
              state == .starting || state == .recording || state == .finalizing else {
            if session?.url != url { storage.remove(url) }
            return
        }
        if let error {
            finish()
            onError?("錄音未能完成：\(error.localizedDescription)")
            return
        }
        guard storage.isNonempty(url) else {
            finish()
            onError?("錄音是空的，請確認麥克風後再試。")
            return
        }
        beginTranscription(reinforce: false, manualRetry: false)
    }

    private func beginTranscription(reinforce: Bool, manualRetry: Bool) {
        guard let current = session else { return }
        let requestID = UUID()
        session?.requestID = requestID
        setState(.transcribing)
        // 驗證當前任務世代仍有效；若已在 setState 回呼期間被取消，則不發出網路請求。
        guard session?.id == current.id, session?.requestID == requestID, state == .transcribing else { return }
        let token = transcriber.transcribe(
            url: current.url, language: current.settings.language, reinforce: reinforce
        ) { [weak self] result in
            self?.received(result, sessionID: current.id, requestID: requestID, manualRetry: manualRetry)
        }
        // A synchronous failure or completion may already have ended/replaced this attempt.
        if session?.id == current.id, session?.requestID == requestID, state == .transcribing {
            request = token
        } else {
            token.cancel()
        }
    }

    private func received(
        _ result: Result<String, Error>, sessionID: UUID, requestID: UUID, manualRetry: Bool
    ) {
        guard state == .transcribing, var current = session,
              current.id == sessionID, current.requestID == requestID else { return }
        request = nil
        session?.requestID = nil
        switch result {
        case .failure(let error):
            retain(message: "\(error.localizedDescription)\n\n錄音已暫時保留，可以重新辨識，不用重講。",
                   prompt: !manualRetry)
        case .success(let value):
            let transcript = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                if manualRetry {
                    retain(message: "重新辨識仍未成功。錄音會再保留兩分鐘，你也可以直接重新錄音。", prompt: false)
                } else {
                    finish()
                    onError?("沒有辨識到語音，請再試一次。")
                }
                return
            }
            if TextPostProcessor.isPureHallucinatedBoilerplate(transcript) {
                if manualRetry {
                    retain(message: "未清楚辨識到有效語音。錄音會再保留兩分鐘，你也可以直接重新錄音。", prompt: false)
                } else {
                    finish()
                    onError?("未清楚辨識到有效語音，請再試一次。")
                }
                return
            }
            if consumeTranscript?(transcript) == true {
                guard session?.id == sessionID else { return }
                finish()
                return
            }
            if LanguagePolicy.shouldIntercept(transcript, settings: current.settings.language) {
                // 設計意圖：Groq Whisper 在極短音訊或雜音下偶爾會漂移為非目標語言。
                // 當語言不符時，若啟用自動重試，會以 reinforce: true 重新轉錄（在 Prompt 加入語言強制提示）。
                // 容易誤用之處：必須嚴格限制僅自動重試一次（!current.automaticRetryUsed），
                // 避免模型持續漂移造成無窮重試而耗盡 API 額度；再次失敗則保留錄音並交給使用者決定。
                if !manualRetry && !current.automaticRetryUsed && current.settings.language.automaticRetryEnabled {
                    current.automaticRetryUsed = true
                    current.requestID = nil
                    session = current
                    beginTranscription(reinforce: true, manualRetry: false)
                } else {
                    retain(message: "這段語音未能正確辨識為允許的語言。錄音已保留，你可以重新辨識或再次錄音。",
                           prompt: !manualRetry)
                }
                return
            }
            let processed = TextPostProcessor.process(
                transcript, mode: current.settings.outputMode,
                applyChineseRules: current.settings.language.primary.usesChineseTextRules,
                convertChineseNumerals: current.settings.convertChineseNumerals
            )
            let cleaned = !processed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            setState(.delivering)
            guard session?.id == sessionID, state == .delivering else { return }
            let copied = deliverText?(cleaned ? processed : transcript) ?? false
            guard session?.id == sessionID else { return }
            if copied {
                finish()
                if !cleaned { onError?("語音已成功轉錄，但文字清理暫時未完成。目前先使用原始轉錄。") }
            } else {
                retain(message: "無法把文字複製到剪貼簿。錄音已暫時保留，可重新辨識或捨棄。", prompt: true)
            }
        }
    }

    private func retain(message: String, prompt: Bool) {
        guard let current = session else { return }
        let deadline = now().addingTimeInterval(retentionInterval)
        session?.retryDeadline = deadline
        setState(.awaitingRetry)
        guard session?.id == current.id, state == .awaitingRetry else { return }
        // 設計意圖：使用 deadline 作為取消權杖（Token）。
        // 若使用者在寬限期內手動點擊重試並再次失敗，retryDeadline 會被展延；
        // 當排程閉包觸發時，若 deadline 已被更新，則不執行 finish()，避免提前清理仍處於寬限期的錄音檔。
        schedule(retentionInterval) { [weak self] in
            guard let self, self.state == .awaitingRetry,
                  self.session?.id == current.id, self.session?.retryDeadline == deadline else { return }
            self.finish()
        }
        if prompt {
            onRetryRequested?(current.id, message)
        } else {
            onError?(message)
        }
    }

    private func finish() {
        let old = session
        session = nil
        request = nil
        if let old { storage.remove(old.url) }
        setState(.idle)
    }

    private func setState(_ value: DictationState) {
        state = value
        onStateChange?(value)
    }
}
