import Foundation

/// 轉錄文字的輸出模式。預設 `verbatim`，與 v1.1.0 以前完全不做後處理的行為一致。
enum TextOutputMode: String, CaseIterable {
    /// 純逐字：只修格式（簡繁、標點、空格、詞典大小寫），不刪任何內容。
    case verbatim
    /// 標準：在純逐字之上，移除句首語助詞、連續重複詞與重複的連接詞。
    case standard
    /// 簡潔：在標準之上，另外移除句尾語氣詞。**會改變語氣**，必須由使用者主動選擇。
    case concise

    var displayName: String {
        switch self {
        case .verbatim: return "純逐字（保留原話）"
        case .standard: return "標準（移除呃、嗯與重複詞）"
        case .concise: return "簡潔（另移除句尾語氣詞）"
        }
    }

    /// 是否執行「標準」以上的清理。
    var removesFillers: Bool {
        self != .verbatim
    }

    /// 是否執行句尾語氣詞清理。
    var removesSentenceFinalParticles: Bool {
        self == .concise
    }

    /// 讀取舊版設定值。0.1 版只有 verbatim／lightCleanup 兩級，
    /// 舊的 lightCleanup 對應到現在的 standard，避免既有使用者的設定被靜默重設。
    static func fromStoredValue(_ raw: String?) -> TextOutputMode? {
        guard let raw else { return nil }
        if raw == "lightCleanup" { return .standard }
        return TextOutputMode(rawValue: raw)
    }
}

/// 轉錄文字的本機後處理管線。
///
/// 全部為決定性規則，不呼叫任何語言模型，也不連網。每個階段都是純函式，
/// 可獨立測試；順序由 `process(_:mode:...)` 決定。
///
/// 核心原則：寧可少改，也不要錯改。任何階段在「可能改錯」與「維持原文」之間，
/// 一律選擇維持原文。
enum TextPostProcessor {
    /// 連接詞白名單：只有在「連續重複」時才整組刪除，單次出現一律保留。
    ///
    /// 刻意不收「這個」「那個」——它們常是指示代名詞（「那個案子」），
    /// 整組刪除會改變語意。它們交給 `collapseRepeatedWords` 收合成一個。
    static let discourseMarkers = ["然後", "就是說"]

    /// 句首語助詞。只處理句首或獨立出現的情況，不動句中。
    static let leadingFillerCharacters = "呃嗯"

    /// 句尾語氣詞。只在簡潔模式移除。
    static let sentenceFinalParticles = "啊啦喔耶吧呢嘛囉唷"

    /// 保護詞表：這些詞的最後一個字剛好是語氣詞，但它是詞的一部分，不得移除。
    ///
    /// 沒有這張表，「我們去酒吧」會被切成「我們去酒」。
    static let particleProtectedWords = [
        "酒吧", "網吧", "吧台", "吧檯",
        "毛呢", "呢喃", "呢絨",
        "芝麻", "麻嘛",
        "哪吒", "剎那",
        "咖啦", "沙啦", "劈啦",
        "耶穌", "耶誕",
        "喇叭"
    ]

    /// 重複詞偵測的最大詞長。超過此長度不自動收合，避免誤刪長句。
    static let maximumRepeatedWordLength = 4

    static func process(
        _ text: String,
        mode: TextOutputMode,
        vocabulary: [String] = [],
        applyChineseRules: Bool = true,
        convertChineseNumerals: Bool = false
    ) -> String {
        var output = text

        // 中文專屬階段。對日文做 Hans-Hant 轉換會破壞日文漢字，
        // 所以主要語言不是中文時整組跳過。
        if applyChineseRules {
            output = toTraditional(output)
            output = removeTrailingHallucinatedBoilerplate(output)
            output = collapseRepeatedPunctuation(output)
            output = normalizePunctuation(output)
            output = collapseRepeatedPunctuation(output)
        }

        output = normalizeSpacing(output)
        output = applyVocabulary(output, vocabulary)

        if applyChineseRules && convertChineseNumerals {
            output = convertAnchoredNumerals(output)
        }

        if mode.removesFillers {
            output = removeLeadingFillers(output)
            output = removeRepeatedDiscourseMarkers(output)
            output = collapseRepeatedWords(output)
        }
        if mode.removesSentenceFinalParticles {
            output = removeSentenceFinalParticles(output)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 格式階段

    /// 簡體轉繁體。使用 macOS 內建的 ICU 轉換，具備上下文判斷
    /// （头发→頭髮、干了→乾了、里面→裡面），且只轉字形不轉詞彙
    /// （软件→軟件，不會變成軟體），符合法律用語的保守要求。
    static func toTraditional(_ s: String) -> String {
        s.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false) ?? s
    }

    /// 半形標點在中文語境改為全形。
    ///
    /// 前一個字元允許是漢字或已轉換的全形標點，這樣連續的 "？?" 才能一次處理完。
    /// 小數點與千分位（`.` 後面接數字）不轉換。
    static func normalizePunctuation(_ s: String) -> String {
        var output = s
        let previous = "\\p{Han}，。？！、；："
        output = replace(output, "(?<=[\(previous)])\\s*,\\s*", with: "，")
        output = replace(output, "(?<=[\(previous)])\\s*\\.(?!\\d)\\s*", with: "。")
        output = replace(output, "(?<=[\(previous)])\\s*\\?\\s*", with: "？")
        output = replace(output, "(?<=[\(previous)])\\s*!\\s*", with: "！")
        output = replace(output, "(?<=[\(previous)])\\s*;\\s*", with: "；")
        return output
    }

    /// 收合連續重複的同一個標點，半形與全形都處理。
    static func collapseRepeatedPunctuation(_ s: String) -> String {
        var output = s
        output = replace(output, "([，。？！、；：])\\1+", with: "$1")
        output = replace(output, "([,.?!;:])\\1+", with: "$1")
        return output
    }

    /// 在漢字與英文字母之間補一個空格。
    ///
    /// 刻意**不處理數字**：中文排版習慣是「第159條」「50萬元」不加空格，
    /// 加了反而破壞法條與金額的可讀性。
    static func normalizeSpacing(_ s: String) -> String {
        var output = s
        output = replace(output, "(\\p{Han})([A-Za-z])", with: "$1 $2")
        output = replace(output, "([A-Za-z])(\\p{Han})", with: "$1 $2")
        output = replace(output, "[ \\t]{2,}", with: " ")
        return output
    }

    /// 套用個人詞典。
    ///
    /// 只做**大小寫修正**這種高把握度的替換（groq → Groq），不做模糊比對，
    /// 也不因發音相似而替換。純中文詞彙不在此階段處理，避免誤改法律名詞。
    static func applyVocabulary(_ s: String, _ vocabulary: [String]) -> String {
        var output = s
        for term in vocabulary {
            guard term.range(of: "^[A-Za-z][A-Za-z0-9]*$", options: .regularExpression) != nil else {
                continue
            }
            let escaped = NSRegularExpression.escapedPattern(for: term)
            output = replace(
                output,
                "(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])",
                with: NSRegularExpression.escapedTemplate(for: term),
                options: [.caseInsensitive]
            )
        }
        return output
    }

    // MARK: - 清理階段

    /// 移除句首的「呃」「嗯」。只處理句首，不動句中。
    static func removeLeadingFillers(_ s: String) -> String {
        replace(s, "^\\s*[\(leadingFillerCharacters)]+\\s*，?\\s*", with: "")
    }

    /// 連接詞連續重複時整組刪除（「然後，然後我們…」→「我們…」）。
    /// 單次出現一律保留（「我先去吃飯，然後我們就出發」不變）。
    static func removeRepeatedDiscourseMarkers(_ s: String) -> String {
        var output = s
        for marker in discourseMarkers {
            let escaped = NSRegularExpression.escapedPattern(for: marker)
            output = replace(output, "(^|，)(?:\(escaped)，?\\s*){2,}", with: "$1")
        }
        return output
    }

    /// 收合連續重複的詞（「這個，這個功能」→「這個功能」）。
    /// 只處理 `maximumRepeatedWordLength` 以內的短詞。
    static func collapseRepeatedWords(_ s: String) -> String {
        replace(s, "(\\p{Han}{1,\(maximumRepeatedWordLength)})，?\\1", with: "$1")
    }

    /// 移除句尾語氣詞（「好啊，我知道了喔」→「好，我知道了」）。
    ///
    /// 三個條件必須同時成立才移除，否則「我們去酒吧」會被切成「我們去酒」：
    /// 1. 語氣詞位於子句結尾（後面是標點或字串結尾）。
    /// 2. 前一個字是漢字。
    /// 3. 「前一字＋語氣詞」不在 `particleProtectedWords` 內。
    ///
    /// 這個階段**會改變語氣**，只在簡潔模式執行。
    static func removeSentenceFinalParticles(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(\\p{Han})([\(sentenceFinalParticles)])(?=[，。！？；：]|$)"
        ) else { return s }

        let source = s as NSString
        var output = ""
        var cursor = 0

        for match in regex.matches(in: s, range: NSRange(location: 0, length: source.length)) {
            let precedingCharacter = source.substring(with: match.range(at: 1))
            let particle = source.substring(with: match.range(at: 2))
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            // 保護詞：整段原樣保留。
            if particleProtectedWords.contains(precedingCharacter + particle) {
                output += precedingCharacter + particle
            } else {
                output += precedingCharacter
            }
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    // MARK: - 中文數字

    /// 錨定式中文數字轉換。
    ///
    /// **只轉三種型式**，其餘一律保留原文。中文數字大量出現在成語與副詞裡
    /// （一直、一定、十分、三思），全域轉換會把「我一直在等」變成「我1直在等」。
    static func convertAnchoredNumerals(_ s: String) -> String {
        var output = s
        let digits = "零一二三四五六七八九十百千萬兩"

        // 1. 法條：第一百五十九條 → 第159條
        output = replaceMatches(output, "第([\(digits)]+)(條|項|款|目|章|節|編)") { groups in
            guard let value = chineseNumeralValue(groups[0]) else { return nil }
            return "第\(value)\(groups[1])"
        }

        // 2. 金額：五十萬元 → 50萬元
        //    數字部分刻意排除「萬」「億」，否則貪婪比對會把「五十萬」整個換算成 500000。
        let amountDigits = "零一二三四五六七八九十百千兩"
        output = replaceMatches(output, "([\(amountDigits)]+)(萬|億)?(元|塊)") { groups in
            guard let value = chineseNumeralValue(groups[0]) else { return nil }
            return "\(value)\(groups[1])\(groups[2])"
        }

        // 3. 百分比：百分之五十 → 50%
        output = replaceMatches(output, "百分之([\(digits)]+)") { groups in
            guard let value = chineseNumeralValue(groups[0]) else { return nil }
            return "\(value)%"
        }

        return output
    }

    /// 中文數字轉整數。無法確定時回傳 nil，呼叫端保留原文。
    static func chineseNumeralValue(_ s: String) -> Int? {
        let digitMap: [Character: Int] = [
            "零": 0, "一": 1, "二": 2, "兩": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        let unitMap: [Character: Int] = ["十": 10, "百": 100, "千": 1000, "萬": 10000]

        guard !s.isEmpty else { return nil }

        var total = 0
        var section = 0
        var current = 0
        var sawAnything = false

        for character in s {
            if let digit = digitMap[character] {
                current = digit
                sawAnything = true
            } else if let unit = unitMap[character] {
                sawAnything = true
                if unit == 10000 {
                    section = (section + max(current, 0)) * unit
                    total += section
                    section = 0
                } else {
                    // 「十五」開頭省略的一。
                    section += (current == 0 ? 1 : current) * unit
                }
                current = 0
            } else {
                return nil
            }
        }
        guard sawAnything else { return nil }
        let result = total + section + current
        return result > 0 || s == "零" ? result : nil
    }

    // MARK: - 工具

    private static func replace(
        _ s: String,
        _ pattern: String,
        with template: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            // 規則本身有問題時維持原文，不讓後處理吃掉使用者的文字。
            return s
        }
        return regex.stringByReplacingMatches(
            in: s,
            range: NSRange(s.startIndex..., in: s),
            withTemplate: template
        )
    }

    /// 用 closure 決定替換內容。closure 回傳 nil 時保留原文。
    private static func replaceMatches(
        _ s: String,
        _ pattern: String,
        _ transform: ([String]) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let source = s as NSString
        var output = ""
        var cursor = 0

        for match in regex.matches(in: s, range: NSRange(location: 0, length: source.length)) {
            var groups: [String] = []
            for index in 1..<match.numberOfRanges {
                let range = match.range(at: index)
                groups.append(range.location == NSNotFound ? "" : source.substring(with: range))
            }
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += transform(groups) ?? source.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    // MARK: - 宣傳語與幻覺防護階段

    /// 常見的 YouTube / Podcast 片尾宣傳語模式。
    ///
    /// Whisper 在無聲、環境底噪或短語音結尾時，容易受訓練集偏誤影響憑空產生這些語句。
    private static let standaloneBoilerplatePatterns = [
        "^[\\s，。！？、]*(?:請?(?:記得)?(?:不要忘記)?(?:不吝嗇)?(?:打賞)?(?:訂閱|按讚|點讚|關注|分享)(?:我的頻道|我們|點讚)?)[\\s，。！？、！]*$",
        "^[\\s，。！？、]*(?:請?(?:記得)?(?:不要忘記)?(?:打賞)?(?:[、，\\s]*(?:按讚|訂閱|點讚|分享|關注|開啟小鈴鐺|開小鈴鐺|我的頻道))+)[\\s，。！？、！]*$",
        "^[\\s，。！？、]*(?:感謝|謝謝)(?:大家|您)?(?:的)?(?:收看|觀看|收聽|支持)[\\s，。！？、！]*$",
        "^[\\s，。！？、]*歡迎訂閱(?:我的頻道)?[\\s，。！？、！]*$"
    ]

    private static let trailingBoilerplatePatterns = [
        "(?<=[。！？\n])\\s*(?:請?(?:記得)?(?:不要忘記)?(?:不吝嗇)?(?:打賞)?(?:[、，\\s]*(?:按讚|訂閱|點讚|分享|關注|開啟小鈴鐺|開小鈴鐺|我的頻道))+)[！。]?$",
        "(?<=[。！？\n])\\s*(?:感謝|謝謝)(?:大家|您)?(?:的)?(?:收看|觀看|收聽|支持)[！。]?$",
        "(?<=[。！？\n])\\s*歡迎訂閱(?:我的頻道)?[！。]?$"
    ]

    /// 判斷整段辨識文字是否純粹為模型憑空產生的 YouTube 宣傳語或片尾套話。
    ///
    /// 若整段皆為此類套話，代表錄音無有效語音，呼叫端應攔截並提示使用者重錄，
    /// 避免將幻覺文字直接貼入輸入框。
    static func isPureHallucinatedBoilerplate(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        for pattern in standaloneBoilerplatePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil {
                return true
            }
        }
        return false
    }

    /// 剝除句子尾端獨立附掛的 YouTube 宣傳語套話。
    ///
    /// 必須緊接在句尾標點符號（。！？或換行）之後，且符合宣傳語格式才會移除。
    /// 使用者在正常文句中說出「訂閱」「按讚」（例如「請訂閱我們的電子報」、「這本書值得按讚」）
    /// 因具有上下文語義，絕不會被誤刪。
    static func removeTrailingHallucinatedBoilerplate(_ s: String) -> String {
        var output = s
        for pattern in trailingBoilerplatePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let ns = output as NSString
                output = regex.stringByReplacingMatches(in: output, range: NSRange(location: 0, length: ns.length), withTemplate: "")
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
