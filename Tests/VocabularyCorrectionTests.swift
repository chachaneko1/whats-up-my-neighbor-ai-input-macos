import Foundation

@main
enum VocabularyCorrectionTests {
    static func main() {
        let corrections: [(String, String, String, String)] = [
            ("我用字點輸入", "我用字典輸入", "字點", "字典"),
            ("我在台南工作", "我在台北工作", "台南", "台北"),
            ("我用字點輸入。", "我用字典輸入。", "字點", "字典"),
            ("請使用 ChatGPTT 模型", "請使用 ChatGPT 模型", "ChatGPTT", "ChatGPT"),
            ("我使用語語音輸入", "我使用語音輸入", "語語音", "語音"),
            ("請使用 ChatGPT 模型", "請使用 ChatGPTs 模型", "ChatGPT", "ChatGPTs"),
            ("我用語輸入", "我用語音輸入", "語", "語音"),
            ("我在用 NekoEye 開發", "我在用 NekoAI 開發", "NekoEye", "NekoAI"),
            ("請使用 foo_baz", "請使用 foo_bar", "foo_baz", "foo_bar"),
            ("請使用 gpt-4x", "請使用 gpt-4o", "gpt-4x", "gpt-4o"),
            ("🙂 我用字點輸入", "🙂 我用字典輸入", "字點", "字典"),
            ("I use zChatGPT", "I use ChatGPT", "zChatGPT", "ChatGPT"),
            ("ChatGPTT", "ChatGPT", "ChatGPTT", "ChatGPT"),
            ("字點", "字典", "字點", "字典"),
        ]
        for (before, after, originalTerm, correctedTerm) in corrections {
            let actual = MacVocabularyCorrectionExtractor.candidate(original: before, edited: after)
            precondition(actual == .init(originalSegment: originalTerm, suggestedTerm: correctedTerm),
                         "Incorrect term for \(before) -> \(after): \(String(describing: actual))")
        }

        let nonCorrections: [(String, String)] = [
            ("字典", "字典"),
            ("語音輸入", "語音輸入。"),
            ("語音，輸入", "語音、輸入"),
            ("我用語音輸入", "我用輸入"),
            ("我用語音語音輸入", "我用語音輸入"),
            ("Please remove this word", "Please remove word"),
            ("我用語音輸入", "我用語音快速輸入"),
            ("I use models", "I use ChatGPT models"),
            ("我今天想出去玩", "咖啡"),
            ("I like this", "We love that"),
            ("字典", ""),
            ("", "字典"),
            ("Chat GPT", "ChatGPT"),
            ("測試", "測試\n"),
        ]
        for (before, after) in nonCorrections {
            precondition(MacVocabularyCorrectionExtractor.candidate(original: before, edited: after) == nil,
                         "Unexpected candidate for \(before) -> \(after)")
        }
        let forty = String(repeating: "a", count: 39) + "b"
        precondition(MacVocabularyCorrectionExtractor.candidate(
            original: String(repeating: "a", count: 40), edited: forty)?.suggestedTerm == forty)
        precondition(MacVocabularyCorrectionExtractor.candidate(
            original: String(repeating: "a", count: 40), edited: String(repeating: "a", count: 40) + "b") == nil)
        precondition(MacVocabularyCorrectionExtractor.candidate(
            original: "字點", edited: "字典", maximumTermLength: 1) == nil)
        print("VocabularyCorrectionTests passed: \(corrections.count + nonCorrections.count + 3) word-boundary, insertion/deletion and exclusion checks")
    }
}
