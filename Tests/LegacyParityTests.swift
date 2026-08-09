import Foundation

/// 介面 A 的重構等價性證明。
///
/// `LegacyReference` 是**重構前 `main.swift` 的程式碼原封不動搬過來**（commit 5f47150），
/// 唯一的改動是從 `VoiceTypeController` 的方法裡抽成獨立函式，邏輯一字未改。
///
/// 介面 A 的對外行為完全由兩件事決定：送上線的 multipart body，以及從回應取出的字串。
/// 這支測試對兩者做逐位元組／逐字元比對，因此「重構沒改壞介面 A」是被證明的，
/// 不是靠手動試幾句的印象。
///
/// 這個檔案要留著：日後有人動 `GroqTranscriptionRequest` 或 `GroqTranscriptionResponse`
/// 而不小心改變了介面 A 的線上行為，這裡會先紅。
@main
enum LegacyParityTests {
    static func main() {
        testRequestBodyMatchesLegacy()
        testResponseTextMatchesLegacy()
        testErrorMessageMatchesLegacy()
        print("Legacy parity tests passed")
    }

    // MARK: - 重構前的參考實作（逐字搬運，勿修改）

    enum LegacyReference {
        static func body(
            audioData: Data,
            boundary: String,
            language: String,
            prompt: String
        ) -> Data {
            var body = Data()
            func addField(_ name: String, _ value: String) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            }
            addField("model", "whisper-large-v3")
            addField("language", language)
            addField("response_format", "json")
            addField("temperature", "0")
            addField("prompt", prompt)

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"speech.m4a\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            return body
        }

        static func parseText(_ data: Data) -> String? {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = object["text"] as? String else {
                return nil
            }
            return text
        }

        static func errorMessage(_ data: Data, statusCode: Int) -> String {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?
                .flatMap { $0["message"] as? String }
            return detail ?? "Groq 回傳錯誤（HTTP \(statusCode)）。"
        }
    }

    // MARK: - 線上位元組

    static func testRequestBodyMatchesLegacy() {
        // 涵蓋實際會遇到的組合：正式提示、重試提示、非中文主要語言、空提示、空音檔。
        let chinesePrompt =
            "繁體中文口述，使用台灣繁體中文字形與自然標點。可能包含英文、macOS、ChatGPT、API、法律及專有名詞。"
        let retryPrompt =
            "這段錄音的語言是繁體中文，可能混合少量繁體中文、英文。請只輸出這些語言。" + chinesePrompt
        let englishPrompt =
            "Dictation with natural punctuation. May contain English technical terms and proper nouns."

        let cases: [(label: String, language: String, prompt: String, audio: Data)] = [
            ("中文正式提示", "zh", chinesePrompt, Data((0..<4096).map { UInt8($0 % 256) })),
            ("中文重試提示", "zh", retryPrompt, Data([0x00, 0xFF, 0x7F])),
            ("英文主要語言", "en", englishPrompt, Data([0xDE, 0xAD, 0xBE, 0xEF])),
            ("日文主要語言", "ja", "日本語の音声入力です。", Data([0x01])),
            ("空提示", "zh", "", Data([0x42])),
            ("空音檔", "zh", chinesePrompt, Data()),
        ]

        for testCase in cases {
            let boundary = "Boundary-FIXED-FOR-COMPARISON"
            let legacy = LegacyReference.body(
                audioData: testCase.audio,
                boundary: boundary,
                language: testCase.language,
                prompt: testCase.prompt
            )
            let current = GroqTranscriptionRequest.body(
                audio: testCase.audio,
                boundary: boundary,
                fields: GroqTranscriptionRequest.fields(
                    language: testCase.language,
                    prompt: testCase.prompt,
                    format: .plain
                )
            )
            precondition(
                legacy == current,
                """

                  \(testCase.label)：multipart body 與重構前不同
                  舊：\(legacy.count) bytes
                  新：\(current.count) bytes
                  首個相異位置：\(firstDifference(legacy, current).map(String.init) ?? "長度不同")
                """
            )
        }

        // 保險：確認比對本身有鑑別力——verbose 一定要跟舊的不同，否則上面的相等是假的。
        let verbose = GroqTranscriptionRequest.body(
            audio: Data([0x01]),
            boundary: "B",
            fields: GroqTranscriptionRequest.fields(
                language: "zh",
                prompt: "p",
                format: .verboseWithWords
            )
        )
        let plain = LegacyReference.body(audioData: Data([0x01]), boundary: "B", language: "zh", prompt: "p")
        precondition(verbose != plain, "verbose 與 plain 竟然相同，比對失去鑑別力")
    }

    // MARK: - 回應取字串

    static func testResponseTextMatchesLegacy() {
        let payloads = [
            #"{"text":"今天下午開會討論驗收條件。"}"#,
            #"{"text":""}"#,
            #"{"text":"混合 English 與中文的 API 測試"}"#,
            #"{"text":"有換行\n與\t定位字元"}"#,
            // verbose_json 也要取得同一個 text，介面 A 才能安全地改走 verbose。
            #"{"text":"帶 segment 的回應","segments":[{"id":0,"start":0,"end":1,"text":"帶 segment 的回應"}]}"#,
            // 失敗情境：兩邊都要判定為取不到文字。
            #"{"segments":[]}"#,
            #"{"text":123}"#,
            "not json",
            "[]",
        ]

        for payload in payloads {
            let data = Data(payload.utf8)
            let legacy = LegacyReference.parseText(data)
            let current = try? GroqTranscriptionResponse.parse(data).text
            precondition(
                legacy == current,
                "\n  回應解析不一致\n  payload：\(payload)\n  舊：\(legacy ?? "<nil>")\n  新：\(current ?? "<nil>")"
            )
        }
    }

    // MARK: - 錯誤訊息

    static func testErrorMessageMatchesLegacy() {
        let cases: [(payload: String, status: Int)] = [
            (#"{"error":{"message":"Invalid API Key","type":"invalid_request_error"}}"#, 401),
            (#"{"error":{"message":"Rate limit reached"}}"#, 429),
            (#"{"error":{"type":"no_message_field"}}"#, 400),
            (#"{"error":"字串而非物件"}"#, 400),
            ("{}", 500),
            ("broken json", 503),
        ]

        for testCase in cases {
            let data = Data(testCase.payload.utf8)
            let legacy = LegacyReference.errorMessage(data, statusCode: testCase.status)
            let current = GroqTranscriptionResponse
                .error(from: data, statusCode: testCase.status)
                .localizedDescription
            precondition(
                legacy == current,
                "\n  錯誤訊息不一致\n  payload：\(testCase.payload)\n  舊：\(legacy)\n  新：\(current)"
            )
        }
    }

    // MARK: - 工具

    static func firstDifference(_ a: Data, _ b: Data) -> Int? {
        for index in 0..<Swift.min(a.count, b.count) where a[index] != b[index] {
            return index
        }
        return a.count == b.count ? nil : Swift.min(a.count, b.count)
    }
}
