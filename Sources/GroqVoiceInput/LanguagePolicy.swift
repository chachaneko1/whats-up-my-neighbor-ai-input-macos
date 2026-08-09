import Foundation

/// 使用者可以選擇的語言。
///
/// 一個語言同時決定兩件事：送給雲端辨識的語言代碼，以及語言閘門允許的
/// Unicode 腳本。兩者不是同一回事，見 `LanguagePolicy` 的說明。
enum LanguageOption: String, CaseIterable {
    case traditionalChinese = "zh"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case thai = "th"
    case vietnamese = "vi"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    var displayName: String {
        switch self {
        case .traditionalChinese: return "繁體中文"
        case .english: return "英文"
        case .japanese: return "日文"
        case .korean: return "韓文"
        case .thai: return "泰文"
        case .vietnamese: return "越南文"
        case .spanish: return "西班牙文"
        case .french: return "法文"
        case .german: return "德文"
        }
    }

    /// 這個語言會用到的 Unicode 腳本。
    ///
    /// 日文包含漢字，所以會連帶允許 Han；韓文的漢字用法同理。
    var scripts: [String] {
        switch self {
        case .traditionalChinese: return ["Han"]
        case .english, .vietnamese, .spanish, .french, .german: return ["Latin"]
        case .japanese: return ["Han", "Hiragana", "Katakana"]
        case .korean: return ["Hangul", "Han"]
        case .thai: return ["Thai"]
        }
    }

    /// 是否套用中文專屬的後處理（簡繁轉換、全形標點）。
    ///
    /// 對日文做 `Hans-Hant` 轉換會破壞日文漢字，所以只有中文能開。
    var usesChineseTextRules: Bool {
        self == .traditionalChinese
    }

    /// 傳給雲端辨識的提示字串。
    var transcriptionPrompt: String {
        switch self {
        case .traditionalChinese:
            return "繁體中文口述，使用台灣繁體中文字形與自然標點。可能包含英文、macOS、ChatGPT、API、法律及專有名詞。"
        case .japanese:
            return "日本語の音声入力です。自然な句読点を使ってください。英語の固有名詞が混ざることがあります。"
        case .korean:
            return "한국어 음성 입력입니다. 자연스러운 문장 부호를 사용하세요. 영어 고유명사가 섞일 수 있습니다."
        case .english, .vietnamese, .spanish, .french, .german, .thai:
            return "Dictation with natural punctuation. May contain English technical terms and proper nouns."
        }
    }
}

/// 使用者的語言設定：一個主要語言，加上最多兩個允許混用的語言。
///
/// 上限三種是刻意的。就算是三語使用者，同一段口述混到第四種語言的機會很低，
/// 而允許的語言愈多，語言閘門能擋下的誤判就愈少。
struct LanguageSettings: Equatable {
    static let maximumAdditionalLanguages = 2

    var primary: LanguageOption
    var additional: [LanguageOption]
    var automaticRetryEnabled: Bool

    static let `default` = LanguageSettings(
        primary: .traditionalChinese,
        additional: [.english],
        automaticRetryEnabled: true
    )

    /// 主要語言永遠允許，後面接使用者選的混用語言，去重且不超過上限。
    var allowedLanguages: [LanguageOption] {
        var result = [primary]
        for language in additional.prefix(Self.maximumAdditionalLanguages) where !result.contains(language) {
            result.append(language)
        }
        return result
    }

    /// 語言閘門實際使用的腳本清單。
    var allowedScripts: [String] {
        var result: [String] = []
        for script in allowedLanguages.flatMap({ $0.scripts }) where !result.contains(script) {
            result.append(script)
        }
        return result
    }
}

/// 轉錄結果的語言檢查。
///
/// 用 Unicode 腳本比例判定，不使用任何語言模型，也不使用 `NLLanguageRecognizer`
/// ——後者在中英混用與極短字串上實測會誤判（「用 ChatGPT 寫 prompt」被判成西班牙文，
/// 「OK」被判成波蘭文）。腳本比例是決定性的，可完整單元測試。
///
/// **這一層判斷的是「字屬於哪種文字系統」，不是「這是哪個語言」。** 英文、越南文、
/// 西班牙文、法文、德文都寫成拉丁字母，閘門分不出來；允許其中任何一個，效果都等於
/// 允許拉丁字母。要真正分辨語言需要語言模型，而那正是本產品刻意不引入的東西。
///
/// 用途是攔截「音訊過短、沒說話或全是雜訊時，模型憑空產生使用者不會用的語言」，
/// 不是做語言辨識產品。判定一律從寬，寧可放行也不要誤攔正常內容。
enum LanguagePolicy {
    /// 預設允許的腳本：漢字與拉丁字母（繁體中文＋英文混用）。
    static let defaultAllowedScripts = LanguageSettings.default.allowedScripts

    /// 低於這個字母數不攔截。短句的語言判定不可靠，「嗯」「好」「OK」都必須放行。
    static let minimumLetterCount = 6

    /// 未允許腳本佔比達到這個門檻才攔截。
    static let interceptionThreshold = 0.5

    /// 字母總數。標點、數字、空白與 emoji 不計入語言判定。
    static func letterCount(_ s: String) -> Int {
        matchCount(s, "\\p{L}")
    }

    /// 指定腳本的字母佔全部字母的比例。
    static func scriptRatio(_ s: String, script: String) -> Double {
        let total = letterCount(s)
        guard total > 0 else { return 0 }
        return Double(matchCount(s, "\\p{script=\(script)}")) / Double(total)
    }

    /// 未允許腳本的佔比。
    static func disallowedRatio(_ s: String, allowed: [String] = defaultAllowedScripts) -> Double {
        let total = letterCount(s)
        guard total > 0 else { return 0 }
        let allowedRatio = allowed.reduce(0.0) { $0 + scriptRatio(s, script: $1) }
        return max(0, 1.0 - allowedRatio)
    }

    /// 是否應該攔截這段轉錄結果。
    ///
    /// 兩個條件必須同時成立：字母數達到 `minimumLetterCount`，
    /// 且未允許腳本佔比達到 `interceptionThreshold`。
    static func shouldIntercept(_ s: String, allowed: [String] = defaultAllowedScripts) -> Bool {
        guard letterCount(s) >= minimumLetterCount else { return false }
        return disallowedRatio(s, allowed: allowed) >= interceptionThreshold
    }

    static func shouldIntercept(_ s: String, settings: LanguageSettings) -> Bool {
        shouldIntercept(s, allowed: settings.allowedScripts)
    }

    private static func matchCount(_ s: String, _ pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
    }
}
