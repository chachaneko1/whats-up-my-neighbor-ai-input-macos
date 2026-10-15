import Foundation

/// Used only by explicitly injected ephemeral sessions. Accept every request so
/// these tests cannot fall through to an actual network transport.
private final class OfflineTranscriptionProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var starts = 0

    static var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    static func reset() {
        lock.lock()
        starts = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.starts += 1
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"text":"離線測試回應"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ClientCompletionProbe {
    private let lock = NSLock()
    private var values: [Result<TranscriptionResult, Error>] = []
    let completed = DispatchSemaphore(value: 0)

    func receive(_ value: Result<TranscriptionResult, Error>) {
        lock.lock()
        values.append(value)
        lock.unlock()
        completed.signal()
    }

    var results: [Result<TranscriptionResult, Error>] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@main
enum TranscriptionClientTests {
    static func main() throws {
        testPlainResponseParsing()
        testVerboseResponseParsing()
        testMissingAndMalformedFields()
        testErrorExtraction()
        testRequestFields()
        testRequestBody()
        testRequestHeaders()
        try testSuspendedTaskWaitsForResume()
        try testCancelBeforeResumeNeverSends()
        try testDefaultTaskStartsImmediately()
        testUnreadableAudioCompletesWithoutATask()
        print("Transcription client tests passed")
    }

    // MARK: - 回應解析：json

    static func testPlainResponseParsing() {
        let result = try! GroqTranscriptionResponse.parse(json(#"{"text":"今天下午開會討論驗收條件。"}"#))
        expect(result.text, "今天下午開會討論驗收條件。")
        // `json` 沒有 segment 與 word，必須是空陣列而不是 crash。
        precondition(result.segments.isEmpty)
        precondition(result.words.isEmpty)
        precondition(result.language == nil)
        precondition(result.duration == nil)
        precondition(result == TranscriptionResult.plain("今天下午開會討論驗收條件。"))
    }

    // MARK: - 回應解析：verbose_json

    static func testVerboseResponseParsing() {
        let result = try! GroqTranscriptionResponse.parse(json(#"""
        {
          "text": "先確認履約期限。我認為應該再討論。",
          "language": "chinese",
          "duration": 7.5,
          "segments": [
            {"id":0,"start":0.0,"end":3.2,"text":"先確認履約期限。",
             "avg_logprob":-0.21,"no_speech_prob":0.01},
            {"id":1,"start":3.2,"end":7.5,"text":"我認為應該再討論。",
             "avg_logprob":-0.88,"no_speech_prob":0.04}
          ],
          "words": [
            {"word":"先確認","start":0.0,"end":1.1},
            {"word":"履約期限","start":1.1,"end":3.2},
            {"word":"我認為","start":3.2,"end":4.6}
          ]
        }
        """#))

        expect(result.text, "先確認履約期限。我認為應該再討論。")
        expect(result.language ?? "", "chinese")
        precondition(result.duration == 7.5)

        precondition(result.segments.count == 2)
        precondition(result.segments[0].id == 0)
        precondition(result.segments[0].start == 0.0)
        precondition(result.segments[0].end == 3.2)
        expect(result.segments[0].text, "先確認履約期限。")
        precondition(result.segments[0].avgLogprob == -0.21)
        precondition(result.segments[0].noSpeechProb == 0.01)
        // 低把握度的那一段要拿得到數值，門檻校準才有資料可用。
        precondition(result.segments[1].avgLogprob == -0.88)

        precondition(result.words.count == 3)
        expect(result.words[0].text, "先確認")
        precondition(result.words[2].start == 3.2)
    }

    // MARK: - 缺欄位與格式錯誤

    static func testMissingAndMalformedFields() {
        // 沒有 text：必須丟出既有的錯誤訊息，不能 crash。
        expectFailure(#"{"segments":[]}"#, "無法讀取辨識結果。")
        expectFailure("not json at all", "無法讀取辨識結果。")
        expectFailure("[]", "無法讀取辨識結果。")

        // segments 缺欄位時給安全預設值，仍然解析得出來。
        let partial = try! GroqTranscriptionResponse.parse(json(#"""
        {"text":"測試","segments":[{"text":"測試"}],"words":[{"start":0.0}]}
        """#))
        precondition(partial.segments.count == 1)
        precondition(partial.segments[0].id == 0)
        precondition(partial.segments[0].start == 0)
        // 沒有 avg_logprob 就是 nil，不可以假裝成 0——0 會被誤判成高把握度。
        precondition(partial.segments[0].avgLogprob == nil)
        precondition(partial.segments[0].noSpeechProb == nil)
        // 沒有 word 欄位的項目直接略過，不產生空字串詞。
        precondition(partial.words.isEmpty)

        // segments 是空陣列時同樣安全。
        let empty = try! GroqTranscriptionResponse.parse(json(#"{"text":"","segments":[],"words":[]}"#))
        expect(empty.text, "")
        precondition(empty.segments.isEmpty)
    }

    // MARK: - 錯誤訊息

    static func testErrorExtraction() {
        // 有 Groq 的 error.message 就用它。
        expectErrorMessage(
            data: json(#"{"error":{"message":"Invalid API Key","type":"invalid_request_error"}}"#),
            statusCode: 401,
            expected: "Invalid API Key"
        )
        // 取不到細節就退回泛用訊息，且帶上 HTTP 狀態碼。
        expectErrorMessage(data: json("{}"), statusCode: 500, expected: "Groq 回傳錯誤（HTTP 500）。")
        expectErrorMessage(data: json("broken"), statusCode: 429, expected: "Groq 回傳錯誤（HTTP 429）。")
        expectErrorMessage(data: nil, statusCode: 503, expected: "Groq 回傳錯誤（HTTP 503）。")
    }

    // MARK: - 請求組裝

    static func testRequestFields() {
        // 介面 A：plain，不得出現 timestamp_granularities。
        let plain = GroqTranscriptionRequest.fields(language: "zh", prompt: "提示", format: .plain)
        expect(names(plain).joined(separator: ","), "model,language,response_format,temperature,prompt")
        expect(value(plain, "model"), "whisper-large-v3")
        expect(value(plain, "language"), "zh")
        expect(value(plain, "response_format"), "json")
        expect(value(plain, "temperature"), "0")
        expect(value(plain, "prompt"), "提示")

        // 介面 B：verbose 帶兩種 granularity。
        let verbose = GroqTranscriptionRequest.fields(
            language: "zh",
            prompt: "提示",
            format: .verboseWithWords
        )
        expect(
            names(verbose).joined(separator: ","),
            "model,language,response_format,timestamp_granularities[],timestamp_granularities[],temperature,prompt"
        )
        expect(value(verbose, "response_format"), "verbose_json")
        let granularities = verbose.filter { $0.name == "timestamp_granularities[]" }.map(\.value)
        expect(granularities.joined(separator: ","), "segment,word")

        // 只要 segment 時不得夾帶 word。
        let segmentOnly = GroqTranscriptionRequest.fields(
            language: "en",
            prompt: "",
            format: .verbose(granularities: [.segment])
        )
        precondition(segmentOnly.filter { $0.name == "timestamp_granularities[]" }.count == 1)
    }

    static func testRequestBody() {
        let audio = Data([0xAA, 0xBB, 0xCC])
        let body = GroqTranscriptionRequest.body(
            audio: audio,
            boundary: "BOUND",
            fields: [("model", "whisper-large-v3"), ("language", "zh")]
        )
        let text = String(decoding: body, as: UTF8.self)

        precondition(text.contains("--BOUND\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-large-v3\r\n"))
        precondition(text.contains("name=\"language\"\r\n\r\nzh\r\n"))
        // 檔案欄位的檔名與 Content-Type 必須與重構前一致。
        precondition(text.contains("name=\"file\"; filename=\"speech.m4a\""))
        precondition(text.contains("Content-Type: audio/mp4\r\n\r\n"))
        precondition(text.hasSuffix("\r\n--BOUND--\r\n"))
        // 音訊位元組原封不動地包在裡面。
        precondition(body.range(of: audio) != nil)
    }

    static func testRequestHeaders() {
        let request = GroqTranscriptionRequest.make(
            audio: Data([0x01]),
            apiKey: "sk-test",
            language: "zh",
            prompt: "提示",
            format: .plain,
            boundary: "BOUND"
        )
        expect(request.httpMethod ?? "", "POST")
        expect(request.url?.absoluteString ?? "", "https://api.groq.com/openai/v1/audio/transcriptions")
        expect(request.value(forHTTPHeaderField: "Authorization") ?? "", "Bearer sk-test")
        expect(
            request.value(forHTTPHeaderField: "Content-Type") ?? "",
            "multipart/form-data; boundary=BOUND"
        )
        precondition(request.timeoutInterval == 90)
        precondition(request.httpBody != nil)
    }

    // MARK: - 離線 URLSession 生命週期

    static func testSuspendedTaskWaitsForResume() throws {
        try withOfflineSession { session, audioURL in
            let probe = ClientCompletionProbe()
            let task = GroqTranscriptionClient.transcribe(
                audioURL: audioURL, apiKey: "unit-test-only", language: "zh", prompt: "測試",
                format: .plain, session: session, startImmediately: false,
                completion: probe.receive
            )!
            precondition(task.state == .suspended)
            precondition(probe.completed.wait(timeout: .now() + 0.05) == .timedOut)
            precondition(OfflineTranscriptionProtocol.startCount == 0 && probe.results.isEmpty)

            task.resume()
            precondition(probe.completed.wait(timeout: .now() + 3) == .success)
            precondition(OfflineTranscriptionProtocol.startCount == 1 && probe.results.count == 1)
            expect(try probe.results[0].get().text, "離線測試回應")
        }
    }

    static func testCancelBeforeResumeNeverSends() throws {
        try withOfflineSession { session, audioURL in
            let probe = ClientCompletionProbe()
            let task = GroqTranscriptionClient.transcribe(
                audioURL: audioURL, apiKey: "unit-test-only", language: "zh", prompt: "測試",
                format: .plain, session: session, startImmediately: false,
                completion: probe.receive
            )!
            precondition(task.state == .suspended && OfflineTranscriptionProtocol.startCount == 0)
            task.cancel()
            // A late attach/resume must not revive an already cancelled request.
            task.resume()
            precondition(probe.completed.wait(timeout: .now() + 3) == .success)
            precondition(OfflineTranscriptionProtocol.startCount == 0 && probe.results.count == 1)
            guard case .failure = probe.results[0] else {
                preconditionFailure("Cancelling a suspended request must report failure")
            }
            task.cancel()
            task.resume()
            precondition(probe.completed.wait(timeout: .now() + 0.05) == .timedOut)
            precondition(OfflineTranscriptionProtocol.startCount == 0 && probe.results.count == 1)
        }
    }

    static func testDefaultTaskStartsImmediately() throws {
        try withOfflineSession { session, audioURL in
            let probe = ClientCompletionProbe()
            let task = GroqTranscriptionClient.transcribe(
                audioURL: audioURL, apiKey: "unit-test-only", language: "zh", prompt: "測試",
                format: .plain, session: session, completion: probe.receive
            )
            precondition(task != nil)
            precondition(probe.completed.wait(timeout: .now() + 3) == .success)
            precondition(OfflineTranscriptionProtocol.startCount == 1 && probe.results.count == 1)
            expect(try probe.results[0].get().text, "離線測試回應")
        }
    }

    static func testUnreadableAudioCompletesWithoutATask() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineTranscriptionProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        OfflineTranscriptionProtocol.reset()
        let probe = ClientCompletionProbe()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingAudio-\(UUID().uuidString).m4a")
        let task = GroqTranscriptionClient.transcribe(
            audioURL: missingURL, apiKey: "unit-test-only", language: "zh", prompt: "測試",
            format: .plain, session: session, startImmediately: false, completion: probe.receive
        )
        precondition(task == nil && probe.results.count == 1)
        precondition(OfflineTranscriptionProtocol.startCount == 0)
        guard case .failure(let error) = probe.results[0] else {
            preconditionFailure("Missing audio must fail synchronously without a URLSession task")
        }
        precondition(error.localizedDescription.hasPrefix("無法讀取錄音："))
    }

    static func withOfflineSession(_ body: (URLSession, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionClientTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = directory.appendingPathComponent("test.m4a")
        try Data([0x01, 0x02, 0x03]).write(to: audioURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineTranscriptionProtocol.self]
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        OfflineTranscriptionProtocol.reset()
        try body(session, audioURL)
    }

    // MARK: - 工具

    static func json(_ raw: String) -> Data { Data(raw.utf8) }

    static func names(_ fields: [(name: String, value: String)]) -> [String] {
        fields.map(\.name)
    }

    static func value(_ fields: [(name: String, value: String)], _ name: String) -> String {
        fields.first { $0.name == name }?.value ?? "<缺少 \(name)>"
    }

    static func expectFailure(
        _ raw: String,
        _ expected: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            _ = try GroqTranscriptionResponse.parse(json(raw))
            precondition(false, "\n  預期失敗但成功了：\(raw)", file: file, line: line)
        } catch {
            expect(error.localizedDescription, expected, file: file, line: line)
        }
    }

    static func expectErrorMessage(
        data: Data?,
        statusCode: Int,
        expected: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let error = GroqTranscriptionResponse.error(from: data, statusCode: statusCode)
        expect(error.localizedDescription, expected, file: file, line: line)
    }

    static func expect(
        _ actual: String,
        _ expected: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        precondition(
            actual == expected,
            "\n  預期：\(expected)\n  實際：\(actual)",
            file: file,
            line: line
        )
    }
}
