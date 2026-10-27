import Foundation

/// Groq 轉錄的共用核心。
///
/// 這個檔案刻意只 import Foundation，不碰 AppKit：
/// 介面 A（選單列快速語音輸入）與介面 B（逐字稿工作台）共用它，
/// 而且它必須能被 `scripts/test-transcription-client.sh` 單獨編成測試執行檔。
///
/// 分工：
/// - `GroqTranscriptionRequest`：組請求，純函式。
/// - `GroqTranscriptionResponse`：解析回應，純函式。
/// - `GroqTranscriptionClient`：只負責發出網路請求的薄殼。

// MARK: - 錯誤

enum VoiceTypeError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}

// MARK: - 結果模型

/// 單一詞的時間戳。只有在要求 `word` granularity 時才有內容。
struct TranscriptionWord: Equatable {
    let text: String
    let start: Double
    let end: Double
}

/// Whisper 的 segment。切點由模型決定，**不等於句子**——
/// 一個 segment 可能橫跨兩句，也可能把一句切成兩半。
/// 要得到句級時間戳必須另外以標點切句，再用 word timestamp 回推。
struct TranscriptionSegment: Equatable {
    let id: Int
    let start: Double
    let end: Double
    let text: String
    /// 對數機率平均。**不是校準過的信心值**，不可顯示成百分比。
    let avgLogprob: Double?
    let noSpeechProb: Double?
}

struct TranscriptionResult: Equatable {
    let text: String
    let segments: [TranscriptionSegment]
    let words: [TranscriptionWord]
    let language: String?
    let duration: Double?

    /// `response_format=json` 只回傳文字，沒有 segment 與 word。
    static func plain(_ text: String) -> TranscriptionResult {
        TranscriptionResult(text: text, segments: [], words: [], language: nil, duration: nil)
    }
}

// MARK: - 請求格式

enum TimestampGranularity: String, CaseIterable {
    case segment
    case word
}

/// 介面 A 用 `.plain`：不需要時間戳與把握度，也不必承擔額外的回應體積與延遲。
/// 介面 B 用 `.verbose`：句級時間戳與低把握度標記都依賴它。
enum TranscriptionFormat: Equatable {
    case plain
    case verbose(granularities: [TimestampGranularity])

    static let verboseWithWords = TranscriptionFormat.verbose(granularities: [.segment, .word])

    var responseFormatValue: String {
        switch self {
        case .plain: return "json"
        case .verbose: return "verbose_json"
        }
    }

    var granularities: [TimestampGranularity] {
        switch self {
        case .plain: return []
        case .verbose(let values): return values
        }
    }
}

// MARK: - 請求組裝（純函式）

enum GroqTranscriptionRequest {
    static let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    static let model = "whisper-large-v3"
    static let timeoutInterval: TimeInterval = 90
    static let audioFilename = "speech.m4a"
    static let audioContentType = "audio/mp4"

    /// multipart 的文字欄位，順序固定，方便測試比對。
    static func fields(
        language: String,
        prompt: String,
        format: TranscriptionFormat
    ) -> [(name: String, value: String)] {
        // 參數約束與確定性：
        // 1. temperature 固定為 "0"，降低隨機取樣機率，確保轉錄輸出具有最高確定性並極小化幻覺。
        // 2. response_format 區分 plain（json）與 verbose（verbose_json），前者極小化網路延遲與 Payload。
        var result: [(name: String, value: String)] = [
            ("model", model),
            ("language", language),
            ("response_format", format.responseFormatValue),
        ]
        for granularity in format.granularities {
            result.append(("timestamp_granularities[]", granularity.rawValue))
        }
        result.append(("temperature", "0"))
        result.append(("prompt", prompt))
        return result
    }

    static func body(
        audio: Data,
        boundary: String,
        fields: [(name: String, value: String)]
    ) -> Data {
        var body = Data()
        for field in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(field.value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFilename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(audioContentType)\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    static func make(
        audio: Data,
        apiKey: String,
        language: String,
        prompt: String,
        format: TranscriptionFormat,
        boundary: String
    ) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body(
            audio: audio,
            boundary: boundary,
            fields: fields(language: language, prompt: prompt, format: format)
        )
        return request
    }
}

// MARK: - 回應解析（純函式）

enum GroqTranscriptionResponse {
    /// 同時吃得下 `json` 與 `verbose_json`。
    /// `json` 只有 `text`，此時 segments 與 words 為空陣列。
    static func parse(_ data: Data) throws -> TranscriptionResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else {
            throw VoiceTypeError.message("無法讀取辨識結果。")
        }

        let segments = (object["segments"] as? [[String: Any]] ?? []).enumerated().map {
            index, raw in
            TranscriptionSegment(
                id: raw["id"] as? Int ?? index,
                start: raw["start"] as? Double ?? 0,
                end: raw["end"] as? Double ?? 0,
                text: raw["text"] as? String ?? "",
                avgLogprob: raw["avg_logprob"] as? Double,
                noSpeechProb: raw["no_speech_prob"] as? Double
            )
        }

        let words = (object["words"] as? [[String: Any]] ?? []).compactMap {
            raw -> TranscriptionWord? in
            guard let value = raw["word"] as? String else { return nil }
            return TranscriptionWord(
                text: value,
                start: raw["start"] as? Double ?? 0,
                end: raw["end"] as? Double ?? 0
            )
        }

        return TranscriptionResult(
            text: text,
            segments: segments,
            words: words,
            language: object["language"] as? String,
            duration: object["duration"] as? Double
        )
    }

    /// 非 2xx 時，優先取 Groq 回傳的 `error.message`，取不到才用泛用訊息。
    // 設計意圖：Groq 雲端在 API Key 無效、Rate Limit 或音訊不合法時會回傳包含具體原因的 JSON error payload。
    // 優先解析並向使用者顯示精準的雲端錯誤說明，避免只顯示模糊的 HTTP 狀態碼。
    static func error(from data: Data?, statusCode: Int) -> VoiceTypeError {
        let fallback = "Groq 回傳錯誤（HTTP \(statusCode)）。"
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["error"] as? [String: Any],
              let message = payload["message"] as? String else {
            return VoiceTypeError.message(fallback)
        }
        return VoiceTypeError.message(message)
    }
}

// MARK: - 呼叫殼

enum GroqTranscriptionClient {
    /// 讀檔、發請求、解析。錯誤訊息與重構前完全相同。
    @discardableResult
    static func transcribe(
        audioURL: URL,
        apiKey: String,
        language: String,
        prompt: String,
        format: TranscriptionFormat,
        session: URLSession = .shared,
        startImmediately: Bool = true,
        completion: @escaping (Result<TranscriptionResult, Error>) -> Void
    ) -> URLSessionDataTask? {
        let audio: Data
        do {
            audio = try Data(contentsOf: audioURL)
        } catch {
            completion(.failure(VoiceTypeError.message("無法讀取錄音：\(error.localizedDescription)")))
            return nil
        }

        let request = GroqTranscriptionRequest.make(
            audio: audio,
            apiKey: apiKey,
            language: language,
            prompt: prompt,
            format: format,
            boundary: "Boundary-\(UUID().uuidString)"
        )

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(VoiceTypeError.message("雲端辨識失敗：\(error.localizedDescription)")))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(VoiceTypeError.message("雲端沒有回傳有效結果。")))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(GroqTranscriptionResponse.error(from: data, statusCode: http.statusCode)))
                return
            }
            do {
                completion(.success(try GroqTranscriptionResponse.parse(data)))
            } catch {
                completion(.failure(error))
            }
        }
        if startImmediately { task.resume() }
        return task
    }
}
