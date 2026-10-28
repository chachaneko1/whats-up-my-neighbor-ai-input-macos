import Foundation

@main
enum TextPipelineTests {
    static func main() {
        testTraditionalConversion()
        testPunctuation()
        testSpacing()
        testVocabulary()
        testVerbatimPreservesContent()
        testLightCleanup()
        testLegalTermsNeverChange()
        testEdgeCases()
        testLanguageGate()
        testModeMigration()
        testSentenceFinalParticles()
        testChineseNumerals()
        testNonChinesePrimaryLanguage()
        testLanguageSettings()
        testHallucinatedBoilerplateFiltration()
        print("Text pipeline tests passed")
    }

    // MARK: - 簡繁

    static func testTraditionalConversion() {
        expect(TextPostProcessor.toTraditional("简体中文测试"), "簡體中文測試")
        // ICU 具備上下文判斷，一對多的字不會轉錯。
        expect(TextPostProcessor.toTraditional("头发"), "頭髮")
        expect(TextPostProcessor.toTraditional("干了"), "乾了")
        expect(TextPostProcessor.toTraditional("里面"), "裡面")
        // 只轉字形不轉詞彙，詞彙差異交給個人詞典逐詞確認。
        expect(TextPostProcessor.toTraditional("软件"), "軟件")
        // 已經是繁體的內容不得被改動。
        expect(TextPostProcessor.toTraditional("假扣押"), "假扣押")
    }

    // MARK: - 標點

    static func testPunctuation() {
        expect(
            TextPostProcessor.process("我明天要去法院聲請假扣押,金額是新台幣50萬元", mode: .verbatim),
            "我明天要去法院聲請假扣押，金額是新台幣50萬元"
        )
        // 連續重複標點收合，包含半形與混合寬度。
        expect(
            TextPostProcessor.process("這個案子有沒有證據能力??我覺得沒有。。。", mode: .verbatim),
            "這個案子有沒有證據能力？我覺得沒有。"
        )
        expect(
            TextPostProcessor.process("真的嗎？？？", mode: .verbatim),
            "真的嗎？"
        )
        // 小數點不得被轉成句號。
        expect(
            TextPostProcessor.process("利率是2.5%", mode: .verbatim),
            "利率是2.5%"
        )
    }

    // MARK: - 空格

    static func testSpacing() {
        expect(
            TextPostProcessor.process("用ChatGPT寫prompt然後貼到Cursor裡面", mode: .verbatim),
            "用 ChatGPT 寫 prompt 然後貼到 Cursor 裡面"
        )
        // 數字刻意不加空格：中文排版的「第159條」「50萬元」不該被拆開。
        expect(
            TextPostProcessor.process("刑事訴訟法第159條", mode: .verbatim),
            "刑事訴訟法第159條"
        )
        expect(
            TextPostProcessor.process("新台幣50萬元", mode: .verbatim),
            "新台幣50萬元"
        )
    }

    // MARK: - 詞典

    static func testVocabulary() {
        // 高把握度的大小寫修正。
        expect(
            TextPostProcessor.process("我用groq跑whisper", mode: .verbatim, vocabulary: ["Groq", "Whisper"]),
            "我用 Groq 跑 Whisper"
        )
        // 不做部分比對，避免誤改。
        expect(
            TextPostProcessor.process("grokking", mode: .verbatim, vocabulary: ["Grok"]),
            "grokking"
        )
        // 純中文詞彙不在此階段替換，避免誤改法律名詞。
        expect(
            TextPostProcessor.process("假處分", mode: .verbatim, vocabulary: ["假扣押"]),
            "假處分"
        )
    }

    // MARK: - 純逐字不得刪內容

    static func testVerbatimPreservesContent() {
        // 純逐字保留語助詞與重複詞，只修格式。
        let raw = "呃，我覺得這個，這個功能其實不用做，然後，然後我們先處理語音辨識。"
        expect(TextPostProcessor.process(raw, mode: .verbatim), raw)

        // 不變性：已經合格的繁體中文必須逐字元相同。
        for text in [
            "今天我們來討論假扣押跟強制執行法的差別。",
            "民國115年3月1日的開庭通知已經收到。",
            "王小明律師說這個案子有機會。"
        ] {
            expect(TextPostProcessor.process(text, mode: .verbatim), text)
        }
    }

    // MARK: - 輕度整理

    static func testLightCleanup() {
        // 使用者提供的範例，輸出必須完全一致。
        expect(
            TextPostProcessor.process(
                "呃，我覺得這個，這個功能其實不用做，然後，然後我們先處理語音辨識。",
                mode: .standard
            ),
            "我覺得這個功能其實不用做，我們先處理語音辨識。"
        )
        // 單次出現的連接詞必須保留，不得誤刪順序語意。
        expect(
            TextPostProcessor.process("我先去吃飯，然後我們就出發", mode: .standard),
            "我先去吃飯，然後我們就出發"
        )
        expect(
            TextPostProcessor.process("然後我們就去聲請強制執行", mode: .standard),
            "然後我們就去聲請強制執行"
        )
        // 指示代名詞只收合成一個，不整組刪除。
        expect(
            TextPostProcessor.process("那個，那個案子的假扣押聲請通過了", mode: .standard),
            "那個案子的假扣押聲請通過了"
        )
        // 句首語助詞可移除，句中的不動。
        expect(
            TextPostProcessor.process("嗯，我知道了", mode: .standard),
            "我知道了"
        )
        expect(
            TextPostProcessor.process("他嗯了一聲", mode: .standard),
            "他嗯了一聲"
        )
    }

    // MARK: - 法律名詞

    static func testLegalTermsNeverChange() {
        let terms = [
            "不起訴處分", "假扣押", "假處分", "證據能力", "傳聞法則",
            "強制執行法", "非訟事件法", "消費者債務清理條例", "司法事務官",
            "准許提起自訴", "再議", "更生程序", "清算程序", "破產程序"
        ]
        for term in terms {
            for mode in TextOutputMode.allCases {
                let sentence = "關於\(term)的部分我再確認一次。"
                let result = TextPostProcessor.process(
                    sentence,
                    mode: mode,
                    convertChineseNumerals: true
                )
                precondition(
                    result.contains(term),
                    "法律名詞被改動：\(term) 在 \(mode) 模式下變成 \(result)"
                )
            }
        }
    }

    // MARK: - 邊界

    static func testEdgeCases() {
        expect(TextPostProcessor.process("", mode: .standard), "")
        expect(TextPostProcessor.process("   ", mode: .standard), "")
        expect(TextPostProcessor.process("好", mode: .standard), "好")
        expect(TextPostProcessor.process("嗯", mode: .standard), "")
        expect(TextPostProcessor.process("OK", mode: .verbatim), "OK")
        // 極長重複不得造成內容遺失以外的破壞。
        let long = String(repeating: "測試", count: 500)
        precondition(!TextPostProcessor.process(long, mode: .verbatim).isEmpty)
    }

    // MARK: - 語言閘門

    static func testLanguageGate() {
        // 未允許語言：攔截。
        precondition(
            LanguagePolicy.shouldIntercept("สวัสดีครับ ผมชอบกินข้าวผัดกระเพราหมูสับ"),
            "泰文長句必須攔截"
        )
        precondition(
            LanguagePolicy.shouldIntercept("日本語のテストです、これは長い文章になります"),
            "日文長句必須攔截"
        )
        // 正常內容：放行。
        for text in [
            "今天我們來討論假扣押跟強制執行法的差別",
            "用 ChatGPT 寫 prompt 然後貼到 Cursor",
            "我想吃拉麵 ramen 很好吃",
            "這個 sushi 很好吃 おいしい"
        ] {
            precondition(!LanguagePolicy.shouldIntercept(text), "正常內容被誤攔：\(text)")
        }
        // 短句一律放行。
        for text in ["嗯", "好", "OK", "是", ""] {
            precondition(!LanguagePolicy.shouldIntercept(text), "短句被誤攔：\(text)")
        }
        // 允許清單可調整：關閉英文後，純英文長句應被攔截。
        precondition(
            LanguagePolicy.shouldIntercept("this is a normal english sentence", allowed: ["Han"]),
            "允許清單必須生效"
        )
        // 門檻是具名常數，方便日後調整。
        precondition(LanguagePolicy.minimumLetterCount == 6)
        precondition(LanguagePolicy.interceptionThreshold == 0.5)
    }

    // MARK: - 模式遷移

    static func testModeMigration() {
        // 0.1 版只有兩級，舊值必須讀成 standard，不能靜默掉回預設。
        precondition(TextOutputMode.fromStoredValue("lightCleanup") == .standard)
        precondition(TextOutputMode.fromStoredValue("verbatim") == .verbatim)
        precondition(TextOutputMode.fromStoredValue("standard") == .standard)
        precondition(TextOutputMode.fromStoredValue("concise") == .concise)
        precondition(TextOutputMode.fromStoredValue("nonsense") == nil)
        precondition(TextOutputMode.fromStoredValue(nil) == nil)
        precondition(TextOutputMode.allCases.count == 3)
    }

    // MARK: - 句尾語氣詞

    static func testSentenceFinalParticles() {
        // 簡潔模式才移除。
        expect(
            TextPostProcessor.process("好啊，我知道了喔", mode: .concise),
            "好，我知道了"
        )
        expect(
            TextPostProcessor.process("這樣就可以了吧", mode: .concise),
            "這樣就可以了"
        )
        // 標準模式不得移除。
        expect(
            TextPostProcessor.process("好啊，我知道了喔", mode: .standard),
            "好啊，我知道了喔"
        )
        expect(
            TextPostProcessor.process("好啊，我知道了喔", mode: .verbatim),
            "好啊，我知道了喔"
        )

        // 保護詞：語氣詞是詞的一部分時絕對不能切。
        for text in [
            "我們去酒吧",
            "他在網吧",
            "服務生站在吧台",
            "這件毛呢大衣很貴",
            "他在旁邊呢喃",
            "牆上掛著喇叭",
            "今天是耶誕節"
        ] {
            let result = TextPostProcessor.process(text, mode: .concise)
            expect(result, text)
        }

        // 句中的語氣詞不動，只處理子句結尾。
        expect(
            TextPostProcessor.process("他說吧台在那邊", mode: .concise),
            "他說吧台在那邊"
        )
    }

    // MARK: - 中文數字

    static func testChineseNumerals() {
        // 數值換算本身。
        precondition(TextPostProcessor.chineseNumeralValue("一百五十九") == 159)
        precondition(TextPostProcessor.chineseNumeralValue("五十") == 50)
        precondition(TextPostProcessor.chineseNumeralValue("十五") == 15)
        precondition(TextPostProcessor.chineseNumeralValue("三") == 3)
        precondition(TextPostProcessor.chineseNumeralValue("兩百") == 200)
        precondition(TextPostProcessor.chineseNumeralValue("abc") == nil)

        // 該轉的三種錨定型式。
        expect(
            TextPostProcessor.process("依刑事訴訟法第一百五十九條", mode: .verbatim, convertChineseNumerals: true),
            "依刑事訴訟法第159條"
        )
        expect(
            TextPostProcessor.process("聲請金額五十萬元", mode: .verbatim, convertChineseNumerals: true),
            "聲請金額50萬元"
        )
        expect(
            TextPostProcessor.process("大約百分之三十", mode: .verbatim, convertChineseNumerals: true),
            "大約30%"
        )

        // 絕對不能轉的：成語與副詞裡的中文數字。
        for text in [
            "我一直在等你",
            "這樣比較一致",
            "十分感謝你的幫忙",
            "三思而後行",
            "他四處奔波",
            "七上八下的心情",
            "我們一起去",
            "這件事一定要做",
            "五花八門的說法"
        ] {
            let result = TextPostProcessor.process(text, mode: .verbatim, convertChineseNumerals: true)
            expect(result, text)
        }

        // 預設關閉時完全不轉換。
        expect(
            TextPostProcessor.process("依刑事訴訟法第一百五十九條", mode: .verbatim),
            "依刑事訴訟法第一百五十九條"
        )
    }

    // MARK: - 非中文主要語言

    static func testNonChinesePrimaryLanguage() {
        // 對日文做 Hans-Hant 轉換會破壞日文，主要語言非中文時必須整組跳過。
        let japanese = "日本語のテストです、これは長い文章になります"
        expect(
            TextPostProcessor.process(japanese, mode: .verbatim, applyChineseRules: false),
            japanese
        )
        // 半形逗號在非中文模式下不得被轉成全形。
        expect(
            TextPostProcessor.process("hello, world", mode: .verbatim, applyChineseRules: false),
            "hello, world"
        )
        // 中文專屬階段關閉時，數字轉換也不執行。
        expect(
            TextPostProcessor.process(
                "第一百五十九條",
                mode: .verbatim,
                applyChineseRules: false,
                convertChineseNumerals: true
            ),
            "第一百五十九條"
        )
    }

    // MARK: - 語言設定

    static func testLanguageSettings() {
        let defaults = LanguageSettings.default
        precondition(defaults.primary == .traditionalChinese)
        precondition(defaults.allowedScripts == ["Han", "Latin"])
        precondition(defaults.primary.usesChineseTextRules)

        // 上限三種語言：主要 1 ＋ 混用 2，多的忽略。
        let tooMany = LanguageSettings(
            primary: .traditionalChinese,
            additional: [.english, .japanese, .korean, .thai],
            automaticRetryEnabled: true
        )
        precondition(tooMany.allowedLanguages.count == 3)
        precondition(!tooMany.allowedLanguages.contains(.korean))

        // 日文帶進假名與漢字。
        let withJapanese = LanguageSettings(
            primary: .traditionalChinese,
            additional: [.japanese],
            automaticRetryEnabled: true
        )
        precondition(withJapanese.allowedScripts.contains("Hiragana"))
        precondition(!LanguagePolicy.shouldIntercept(
            "日本語のテストです、これは長い文章になります",
            settings: withJapanese
        ))
        // 沒開日文時，同一句要被攔截。
        precondition(LanguagePolicy.shouldIntercept(
            "日本語のテストです、これは長い文章になります",
            settings: defaults
        ))

        // 主要語言非中文時不套用中文規則。
        precondition(!LanguageOption.japanese.usesChineseTextRules)
        // 重複的語言不會出現兩次。
        let duplicated = LanguageSettings(
            primary: .english,
            additional: [.english, .french],
            automaticRetryEnabled: true
        )
        precondition(duplicated.allowedLanguages.count == 2)
        precondition(duplicated.allowedScripts == ["Latin"])
    }

    // MARK: - 宣傳語與幻覺防護

    static func testHallucinatedBoilerplateFiltration() {
        // 1. 純宣傳語幻覺（整段命中時應判定為無效語音）
        let standaloneHallucinations = [
            "請訂閱我的頻道",
            "請不吝嗇打賞訂閱",
            "請按讚、分享、開啟小鈴鐺",
            "感謝收看！",
            "謝謝大家收看",
            "歡迎訂閱",
            "訂閱、訂閱、訂閱",
            "訂閱",
            "請按讚",
            "請訂閱",
            "按讚、分享",
            "感謝您的支持！"
        ]
        for s in standaloneHallucinations {
            precondition(
                TextPostProcessor.isPureHallucinatedBoilerplate(s),
                "應判定為純宣傳語幻覺：\(s)"
            )
        }

        // 正常語意中提到「訂閱」或「按讚」絕不能被誤判為純宣傳語
        let legitimateCases = [
            "使用者確實說出訂閱請按讚等內容時必須保留",
            "請訂閱我們的電子報",
            "這本書很多人按讚",
            "我想訂閱經濟學人雜誌",
            "這部影片的按讚數很高",
            "請不要訂閱那個不良頻道"
        ]
        for s in legitimateCases {
            precondition(
                !TextPostProcessor.isPureHallucinatedBoilerplate(s),
                "正常內容不得誤判為純宣傳語：\(s)"
            )
        }

        // Outro-shaped final sentences can be real speech, including the review example.
        let legitimateEndings = [
            "請把簡報傳給團隊。謝謝大家支持",
            "今天下午開會記得帶筆電。請訂閱我的頻道",
            "好的收到。請按讚、分享、開啟小鈴鐺！",
            "明天見。謝謝大家收看",
            "沒問題。感謝收看！",
            "這是影片的結尾。歡迎訂閱我的頻道"
        ]
        for text in legitimateEndings {
            expect(TextPostProcessor.process(text, mode: .verbatim), text)
        }
        // Standard/concise also have independent repeated-word cleanup; use a
        // non-repeated ending to isolate suffix preservation across all modes.
        let endingInAllModes = "請把簡報傳給團隊。感謝您的支持！"
        for mode in TextOutputMode.allCases {
            expect(TextPostProcessor.process(endingInAllModes, mode: mode), endingInAllModes)
        }

        // 正常文句即使包含訂閱與按讚，process 後必須完整保留
        for s in legitimateCases {
            expect(
                TextPostProcessor.process(s, mode: .verbatim),
                s
            )
        }
    }

    // MARK: - 工具

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
