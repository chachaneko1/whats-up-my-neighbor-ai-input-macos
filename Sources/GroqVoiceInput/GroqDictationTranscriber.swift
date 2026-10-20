import Foundation

/// Cancellation also covers the interval before the background file read finishes.
private final class PendingDictationRequest: DictationCancellable {
    private let lock = NSLock()
    private var cancelled = false
    private var task: URLSessionDataTask?

    func attach(_ task: URLSessionDataTask?) {
        lock.lock()
        self.task = task
        if cancelled { task?.cancel() }
        else { task?.resume() }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let current = task
        lock.unlock()
        current?.cancel()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

struct GroqDictationTranscriber: DictationTranscribing {
    let readAPIKey: () -> String?
    var makePrompt: ((LanguageSettings, Bool) -> String)? = nil

    func transcribe(
        url: URL, language: LanguageSettings, reinforce: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> DictationCancellable {
        let pending = PendingDictationRequest()
        guard let apiKey = readAPIKey() else {
            completion(.failure(VoiceTypeError.message("無法讀取 Groq API Key，請重新設定金鑰。")))
            return pending
        }
        let primary = language.primary
        let allowed = language.allowedLanguages.map(\.displayName).joined(separator: "、")
        let hint = "這段錄音的語言是\(primary.displayName)，可能混合少量\(allowed)。請只輸出這些語言。"
        let prompt = makePrompt?(language, reinforce) ?? (reinforce ? hint + primary.transcriptionPrompt : primary.transcriptionPrompt)
        DispatchQueue.global(qos: .userInitiated).async {
            guard !pending.isCancelled else { return }
            _ = AudioSilenceTrimmer.trimTrailingSilence(at: url)
            guard !pending.isCancelled else { return }
            let task = GroqTranscriptionClient.transcribe(
                audioURL: url, apiKey: apiKey, language: primary.rawValue,
                prompt: prompt, format: .plain, startImmediately: false
            ) { result in
                DispatchQueue.main.async {
                    guard !pending.isCancelled else { return }
                    completion(result.map(\.text))
                }
            }
            pending.attach(task)
        }
        return pending
    }
}
