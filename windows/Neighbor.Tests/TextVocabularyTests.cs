using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using Neighbor.Core;

namespace Neighbor.Tests
{
    public static class TextVocabularyTests
    {
        public static void Run(Action<bool, string> check)
        {
            Text(check); Languages(check); Learning(check); Store(check);
        }
        private static void Text(Action<bool, string> check)
        {
            var normalizer = new CountingNormalizer(); var settings = new AppSettings();
            Func<string, string> process = s => TextRules.Process(s, settings, normalizer);
            check(process("我明天要去法院聲請假扣押,金額是新台幣50萬元") == "我明天要去法院聲請假扣押，金額是新台幣50萬元", "Chinese punctuation keeps legal terms");
            check(process("這個案子有沒有證據能力??我覺得沒有。。。。") == "這個案子有沒有證據能力？我覺得沒有。", "Repeated mixed punctuation collapses");
            check(process("利率是2.5%，金額1,000元") == "利率是2.5%，金額1,000元", "Decimals and thousand separators survive");
            check(process("用ChatGPT寫prompt然後貼到Cursor裡面") == "用 ChatGPT 寫 prompt 然後貼到 Cursor 裡面", "Han ASCII boundaries have spaces");
            check(process("刑事訴訟法第159條") == "刑事訴訟法第159條", "No spaces inserted into article number");
            check(TextRules.Process("我用groq跑whisper，grokking", settings, normalizer, new[] { "Groq", "Whisper", "Grok" }) == "我用 Groq 跑 Whisper，grokking", "Vocabulary exact ASCII casing respects boundaries");
            check(TextRules.Process("假處分", settings, normalizer, new[] { "假扣押" }) == "假處分", "Vocabulary does not replace similar legal terms");
            string spoken = "呃，我覺得這個，這個功能其實不用做，然後，然後我們先處理語音辨識。";
            check(process(spoken) == spoken, "Verbatim preserves fillers and repetition");
            settings.Mode = OutputMode.Standard;
            check(process(spoken) == "我覺得這個功能其實不用做，我們先處理語音辨識。", "Standard Mac parity fixture");
            check(process("那個，那個案子的假扣押聲請通過了") == "那個案子的假扣押聲請通過了", "Demonstrative is retained once");
            check(process("我先去吃飯，然後我們就出發") == "我先去吃飯，然後我們就出發", "Single discourse marker preserved");
            check(process("他嗯了一聲") == "他嗯了一聲", "Internal filler preserved");
            check(process("好啊，我知道了喔") == "好啊，我知道了喔", "Standard preserves final particles");
            settings.Mode = OutputMode.Concise;
            check(process("好啊，我知道了喔") == "好，我知道了", "Concise removes only final particles");
            foreach (var term in new[] { "酒吧", "網吧", "毛呢", "呢喃", "喇叭", "吧台", "耶穌" }) check(process("我們去" + term) == "我們去" + term, "Protected final-particle word " + term);
            foreach (var mode in new[] { OutputMode.Verbatim, OutputMode.Standard, OutputMode.Concise })
            foreach (var term in new[] { "不起訴處分", "假扣押", "假處分", "證據能力", "傳聞法則", "強制執行法", "非訟事件法", "消費者債務清理條例", "司法事務官", "准許提起自訴", "再議", "更生程序", "清算程序", "破產程序" })
            { settings.Mode = mode; check(process("關於" + term + "的部分我再確認一次。").Contains(term), "Legal protection " + mode + " " + term); }
            settings.Mode = OutputMode.Verbatim; settings.ConvertChineseNumerals = true;
            check(process("依刑事訴訟法第一百五十九條，金額五十萬元，大約百分之三十") == "依刑事訴訟法第159條，金額50萬元，大約30%", "Three anchored numeral forms");
            foreach (string sentence in new[] { "我一直在等你", "這樣比較一致", "十分感謝你的幫忙", "三思而後行", "他四處奔波", "七上八下的心情", "我們一起去", "這件事一定要做", "五花八門的說法" })
                check(process(sentence) == sentence, "Unanchored numeral idiom preserved " + sentence);
            check(TextRules.ChineseNumeralValue("一百五十九") == 159 && TextRules.ChineseNumeralValue("兩百") == 200 && TextRules.ChineseNumeralValue("一萬零三") == 10003, "Chinese integer parser");
            check(TextRules.ChineseNumeralValue("一二") == null && TextRules.ChineseNumeralValue("百百") == null && TextRules.ChineseNumeralValue("abc") == null, "Ambiguous numerals left untouched");
            check(process("第一二條") == "第一二條", "Malformed article numeral preserved");
            settings.ConvertChineseNumerals = false;
            check(process("第一百五十九條") == "第一百五十九條", "Numeral conversion default off");
            check(process("𠀀API🙂") == "𠀀 API🙂", "Astral Han and emoji keep scalar boundaries");
            check(process("𠀀??") == "𠀀？", "Astral Han contextual punctuation");
            settings.PrimaryLanguage = "ja"; settings.ConvertChineseNumerals = true;
            int calls = normalizer.Calls;
            check(process("日本語のテストです、これは長い文章になります") == "日本語のテストです、これは長い文章になります", "Japanese untouched");
            check(process("第一百五十九條") == "第一百五十九條" && normalizer.Calls == calls, "Non-Chinese primary bypasses conversion and numerals");
            settings.PrimaryLanguage = "en";
            check(process("hello, world") == "hello, world", "English punctuation untouched");
            check(process("") == "" && process("  ") == "", "Empty input remains empty");
        }
        private static void Languages(Action<bool, string> check)
        {
            var settings = new AppSettings();
            check(LanguagePolicy.Languages.Count == 9 && LanguagePolicy.IsSupported("vi") && !LanguagePolicy.IsSupported("xx"), "Nine language options");
            check(!LanguagePolicy.ShouldIntercept("用 ChatGPT 寫 prompt", settings), "Chinese English mixing allowed");
            check(!LanguagePolicy.ShouldIntercept("สวั", settings), "Short foreign fragment below threshold allowed");
            check(LanguagePolicy.ShouldIntercept("สวัสดีครับ ผมชอบกินข้าวผัดกระเพราหมูสับ", settings), "Long unselected Thai intercepted");
            check(LanguagePolicy.ShouldIntercept("日本語のテストです、これは長い文章になります", settings), "Unselected Japanese intercepted");
            check(!LanguagePolicy.ShouldIntercept("12345 😀🙂 ！？", settings), "Digits punctuation emoji excluded");
            check(!LanguagePolicy.ShouldIntercept("𠀀𠀁𠀂𠀃𠀄𠀅", settings), "Astral Han accepted");
            check(!LanguagePolicy.ShouldIntercept("éàöüñê", settings), "Accented Latin allowed");
            check(LanguagePolicy.ShouldIntercept("你好呀абв", settings), "50 percent disallowed at six letters intercepted");
            check(!LanguagePolicy.ShouldIntercept("你呀абв", settings), "Five letters below minimum");
            settings.PrimaryLanguage = "ja"; settings.AdditionalLanguages.Clear();
            check(!LanguagePolicy.ShouldIntercept("日本語のテストです、これは長い文章になります", settings), "Selected Japanese allows scripts");
            settings.PrimaryLanguage = "ko";
            check(!LanguagePolicy.ShouldIntercept("한국어 음성 입력입니다", settings), "Selected Korean allows Hangul");
            settings.PrimaryLanguage = "th";
            check(!LanguagePolicy.ShouldIntercept("สวัสดีครับ ผมชอบกินข้าว", settings), "Selected Thai accepted");
            settings.PrimaryLanguage = "zh"; settings.AdditionalLanguages = new List<string> { "en", "ja", "th" };
            check(LanguagePolicy.ShouldIntercept("สวัสดีครับ ผมชอบกินข้าวผัดกระเพราหมูสับ", settings), "Third additional language ignored");
            foreach (var code in LanguagePolicy.Languages.Keys)
            { check(Encoding.UTF8.GetByteCount(LanguagePolicy.BasePrompt(code, true)) <= 200, "Strengthened base prompt fits budget " + code); }
        }
        private static void Learning(Action<bool, string> check)
        {
            var time = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc); var engine = new LearningEngine(new FixtureSegmenter());
            var cases = new[] {
                new[] { "我用字點輸入", "我用字典輸入", "字點", "字典" },
                new[] { "我在台南工作", "我在台北工作", "台南", "台北" },
                new[] { "請使用 ChatGPTT 模型", "請使用 ChatGPT 模型", "ChatGPTT", "ChatGPT" },
                new[] { "請使用 ChatGPT 模型", "請使用 ChatGPTs 模型", "ChatGPT", "ChatGPTs" },
                new[] { "我使用語語音輸入", "我使用語音輸入", "語語音", "語音" },
                new[] { "我用語輸入", "我用語音輸入", "語", "語音" },
                new[] { "我在用 NekoEye 開發", "我在用 NekoAI 開發", "NekoEye", "NekoAI" },
                new[] { "請使用 foo_baz", "請使用 foo_bar", "foo_baz", "foo_bar" },
                new[] { "請使用 gpt-4x", "請使用 gpt-4o", "gpt-4x", "gpt-4o" },
                new[] { "🙂 我用字點輸入", "🙂 我用字典輸入", "字點", "字典" },
                new[] { "I use zChatGPT", "I use ChatGPT", "zChatGPT", "ChatGPT" },
                new[] { "ChatGPTT", "ChatGPT", "ChatGPTT", "ChatGPT" },
                new[] { "字點", "字典", "字點", "字典" }
            };
            foreach (var c in cases)
            {
                engine.Reset(); var candidate = engine.Observe(c[0], c[1], time);
                check(candidate != null && candidate.Original == c[2] && candidate.Corrected == c[3], "Bounded correction " + c[2]);
            }
            foreach (var c in new[] {
                new[] { "字典", "字典" }, new[] { "語音輸入", "語音輸入。" }, new[] { "語音，輸入", "語音、輸入" },
                new[] { "我用語音輸入", "我用輸入" }, new[] { "我用語音語音輸入", "我用語音輸入" },
                new[] { "Please remove this word", "Please remove word" }, new[] { "我用語音輸入", "我用語音快速輸入" },
                new[] { "I use models", "I use ChatGPT models" }, new[] { "我今天想出去玩", "咖啡" },
                new[] { "I like this", "We love that" }, new[] { "字典", "" }, new[] { "", "字典" }, new[] { "Chat GPT", "ChatGPT" }, new[] { "測試", "測試\n" }
            })
            { engine.Reset(); check(engine.Observe(c[0], c[1], time) == null, "Sentence editing is not learning: " + c[0]); }
            engine.Reset(); var first = engine.Observe("old", "new", time);
            check(first != null && engine.Poll(time.AddMilliseconds(1099)) == null && engine.Complete() == null, "No learning before stability deadline");
            engine.Observe("old", "new", time.AddMilliseconds(1000));
            check(engine.Poll(time.AddMilliseconds(1100))?.Id == first.Id, "Repeated UIA notifications do not restart stability");
            check(engine.Poll(time.AddSeconds(2)) == null && !engine.IsReadyToCommit(time.AddMilliseconds(3099)), "Toast announced once with full opt-out duration");
            check(engine.IsReadyToCommit(time.AddMilliseconds(3100)) && engine.Complete()?.Corrected == "new" && engine.Complete() == null, "Deadline commits exactly once");
            engine.Reset(); first = engine.Observe("Neighbour", "Neighbo", time); engine.Poll(time.AddMilliseconds(1100));
            var revised = engine.Observe("Neighbour", "Neighbor", time.AddSeconds(2));
            check(revised != null && revised.Id != first.Id && engine.CountdownUntilUtc == null && !engine.IsReadyToCommit(time.AddMilliseconds(3100)), "Typing changes candidate and cancels stale toast");
            engine.Poll(time.AddMilliseconds(3100)); engine.Cancel();
            check(engine.Pending == null && !engine.IsReadyToCommit(time.AddSeconds(8)) && engine.Observe("Neighbour", "Neighbor", time.AddSeconds(9)) == null, "Opt-out cannot be re-proposed by unchanged notifications");
            engine.Reset(); engine.Observe("old", "new", time); engine.Poll(time.AddMilliseconds(1100)); engine.Observe("old", "old", time.AddSeconds(2));
            check(engine.Pending == null && !engine.IsReadyToCommit(time.AddSeconds(8)), "Undo cancels candidate");
            engine.Reset(); engine.Observe("old", "new", time); engine.Poll(time.AddSeconds(119));
            check(!engine.IsReadyToCommit(time.AddSeconds(121)) && engine.Observe("foo", "bar", time.AddSeconds(122)) == null, "Learning expires and cannot restart until explicit Reset");
            engine.Reset(); check(engine.Observe(new string('a', 40), new string('a', 39) + "b", time) != null, "Forty-character learned term allowed");
            engine.Reset(); check(engine.Observe(new string('a', 40), new string('a', 40) + "b", time) == null, "Forty-one-character learned term rejected");
            engine.Reset(); check(engine.Observe(new string('a', 32769), "b", time) == null, "Oversized observations ignored");
            var broken = new LearningEngine(new InvalidSegmenter());
            check(broken.Observe("𠀀x", "𠀀y", time) == null, "Invalid surrogate word boundaries fail closed");
        }
        private static void Store(Action<bool, string> check)
        {
            string directory = Path.Combine(Path.GetTempPath(), "NeighborVocabularyTests-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(directory);
            try
            {
                string path = Path.Combine(directory, "vocabulary.json"); var store = new VocabularyStore(path); int changes = 0; store.Changed += () => changes++;
                var first = store.Add("Groq"); check(changes == 1 && new VocabularyStore(path).Entries.Single().Id == first.Id, "Entry persisted with stable ID and change event");
                check(Throws(() => store.Add("ｇｒｏｑ")), "Width and case duplicate rejected");
                store.Add("café"); check(Throws(() => store.Add("cafe")), "Diacritic duplicate rejected");
                check(Throws(() => store.Add("")) && Throws(() => store.Add(new string('a', 41))) && Throws(() => store.Add("two\nlines")), "Empty, long, and multiline entries rejected");
                string astral = string.Concat(Enumerable.Repeat("𠀀", 40)); store.Add(astral);
                check(store.Contains(astral) && Throws(() => store.Add(astral + "𠀁")), "Vocabulary limit counts Unicode scalars");
                var outside = store.Entries[0]; outside.Term = "changed without save";
                check(store.Entries[0].Term == "Groq", "Snapshot entries cannot mutate the store");
                first.Pinned = true; store.Update(first);
                var prompt = store.BuildPrompt(LanguagePolicy.BasePrompt("zh"));
                check(prompt.IncludedIds.First() == first.Id && Encoding.UTF8.GetByteCount(prompt.Text) <= 200, "Pinned term has prompt priority within UTF-8 cap");
                var c = store.AddCandidate(new VocabularyCandidate { Original = "NekoEye", Corrected = "NekoAI" });
                check(!store.BuildPrompt("原文").Text.Contains("NekoAI"), "Candidate excluded from prompt before confirmation");
                check(store.AddCandidate(new VocabularyCandidate { Original = "old", Corrected = "nekoai" }).Id == c.Id, "Duplicate candidate reuses bounded record");
                store.SetCandidateStatus(c.Id, VocabularyStore.Added);
                check(store.Contains("NekoAI") && new VocabularyStore(path).Candidates.Single().Status == VocabularyStore.Added, "Candidate approval and term persisted atomically");
                store.SetCandidateStatus(c.Id, VocabularyStore.Added); check(store.Entries.Count(e => e.Term == "NekoAI") == 1, "Repeated approval idempotent");
                var reject = store.AddCandidate(new VocabularyCandidate { Original = "foo", Corrected = "bar" });
                store.SetCandidateStatus(reject.Id, VocabularyStore.Rejected);
                check(store.AddCandidate(new VocabularyCandidate { Original = "foo", Corrected = "BAR" }) == null, "Rejected terms stay rejected across case variants");
                store.RemoveCandidate(reject.Id); check(!new VocabularyStore(path).Candidates.Any(x => x.Id == reject.Id), "Candidate deletion persisted");
                check(Throws(() => store.AddCandidate(new VocabularyCandidate { Original = "the private sentence", Corrected = "new sentence" })), "Full sentences cannot enter learning records");
                first.Enabled = false; store.Update(first); check(!store.BuildPrompt("原文").IncludedIds.Contains(first.Id), "Disabled terms omitted");
                store.Remove(first.Id); check(!new VocabularyStore(path).Contains("Groq"), "Removal persisted");
                check(Encoding.UTF8.GetByteCount(store.BuildPrompt(string.Concat(Enumerable.Repeat("𠀀", 100))).Text) <= 200, "Oversized base prompt clipped at scalar boundaries");
                check(Throws(() => store.SetCandidateStatus(c.Id, "bogus")), "Unknown candidate status rejected");
                string fullPath = Path.Combine(directory, "full.json");
                var fullEntries = Enumerable.Range(0, 200).Select(i => new VocabularyEntry { Term = "term" + i }).ToList();
                var pending = new VocabularyCandidate { Original = "old", Corrected = "overflow" };
                File.WriteAllText(fullPath, new JavaScriptSerializer().Serialize(new VocabularyStore.Document { Version = 1, Entries = fullEntries, Candidates = new List<VocabularyCandidate> { pending } }));
                var full = new VocabularyStore(fullPath);
                check(full.LoadError == null && Throws(() => full.Add("overflow")), "Two hundred entry capacity enforced");
                check(Throws(() => full.SetCandidateStatus(pending.Id, VocabularyStore.Added)) && full.Candidates.Single().Status == VocabularyStore.Waiting && !full.Contains("overflow"), "Capacity failure keeps candidate pending and does not partially add");
                var bounded = full.BuildPrompt("原文"); check(bounded.IncludedIds.Count + bounded.ExcludedIds.Count == 200 && Encoding.UTF8.GetByteCount(bounded.Text) <= 200, "All enabled entries have truthful prompt inclusion state");
                string historyPath = Path.Combine(directory, "history.json");
                File.WriteAllText(historyPath, new JavaScriptSerializer().Serialize(new VocabularyStore.Document { Version = 1, Entries = new List<VocabularyEntry>(), Candidates = Enumerable.Range(0, 500).Select(i => new VocabularyCandidate { Original = "old" + i, Corrected = "new" + i }).ToList() }));
                var history = new VocabularyStore(historyPath);
                check(history.LoadError == null && Throws(() => history.AddCandidate(new VocabularyCandidate { Original = "foo", Corrected = "bar" })), "Five hundred candidate cap enforced");
                string brokenPath = Path.Combine(directory, "broken.json"); File.WriteAllText(brokenPath, "{broken");
                var corrupt = new VocabularyStore(brokenPath);
                check(corrupt.LoadError != null && Throws(() => corrupt.Add("不可覆蓋")) && File.ReadAllText(brokenPath) == "{broken", "Corrupt JSON preserved and all writes blocked");
                foreach (string invalidSchema in new[] { "{}", "{\"Version\":2,\"Entries\":[],\"Candidates\":[]}", "{\"Version\":1,\"Entries\":null,\"Candidates\":[]}" })
                {
                    string schemaPath = Path.Combine(directory, "schema-" + Guid.NewGuid().ToString("N") + ".json"); File.WriteAllText(schemaPath, invalidSchema);
                    var invalid = new VocabularyStore(schemaPath);
                    check(invalid.LoadError != null && invalid.Entries.Count == 0 && Throws(() => invalid.Add("不可覆蓋")) && File.ReadAllText(schemaPath) == invalidSchema,
                        "Invalid schema is preserved and mutations blocked");
                }
                string duplicatePath = Path.Combine(directory, "duplicate.json");
                string duplicateDocument = new JavaScriptSerializer().Serialize(new VocabularyStore.Document { Version = 1,
                    Entries = new List<VocabularyEntry> { new VocabularyEntry { Id = "same-id", Term = "one" }, new VocabularyEntry { Id = "same-id", Term = "two" } },
                    Candidates = new List<VocabularyCandidate>() });
                File.WriteAllText(duplicatePath, duplicateDocument); var duplicateStore = new VocabularyStore(duplicatePath);
                check(duplicateStore.LoadError != null && Throws(() => duplicateStore.Add("不可覆蓋")) && File.ReadAllText(duplicatePath) == duplicateDocument,
                    "Duplicate record IDs fail closed without overwriting the document");
                string oversizedPath = Path.Combine(directory, "oversized.json");
                using (var oversizedFile = File.Create(oversizedPath)) oversizedFile.SetLength(1024 * 1024 + 1);
                var oversizedStore = new VocabularyStore(oversizedPath);
                check(oversizedStore.LoadError != null && Throws(() => oversizedStore.Add("不可覆蓋")) && new FileInfo(oversizedPath).Length == 1024 * 1024 + 1,
                    "Oversized vocabulary file preserved without parsing or replacing it");
                string collision = Path.Combine(directory, "collision"); File.WriteAllText(collision, "not a directory");
                var failed = new VocabularyStore(Path.Combine(collision, "vocabulary.json"));
                check(Throws(() => failed.Add("valid")) && failed.Entries.Count == 0, "Failed disk write leaves memory unchanged");
                check(Directory.GetFiles(directory, "*.tmp").Length == 0, "Atomic writes leave no temporary files");
            }
            finally { Directory.Delete(directory, true); }
        }
        private static bool Throws(Action action) { try { action(); return false; } catch { return true; } }
        private sealed class CountingNormalizer : ITextNormalizer
        { public int Calls; public string ToTraditional(string text) { Calls++; return text; } }
        private sealed class InvalidSegmenter : IWordSegmenter
        { public IReadOnlyList<TextSpan> GetWords(string text) { return new[] { new TextSpan { Start = 1, Length = 1 } }; } }
        // Deterministic tokenizer fixtures isolate extraction/timing from Windows
        // NLS word-boundary differences, which are tested in the platform suite.
        private sealed class FixtureSegmenter : IWordSegmenter
        {
            private static readonly string[] ChineseWords = { "字典", "語音", "台南", "台北", "輸入", "使用", "工作", "快速", "今天", "想", "出去", "玩", "咖啡", "測試", "模型", "開發", "請", "我", "用", "在", "字", "點", "語", "音" };
            public IReadOnlyList<TextSpan> GetWords(string text)
            {
                var result = new List<TextSpan>();
                for (int i = 0; i < text.Length;)
                {
                    var match = Regex.Match(text.Substring(i), "^[A-Za-z0-9]+(?:[_-][A-Za-z0-9]+)*");
                    if (match.Success) { result.Add(new TextSpan { Start = i, Length = match.Length }); i += match.Length; continue; }
                    string word = ChineseWords.FirstOrDefault(w => i + w.Length <= text.Length && string.CompareOrdinal(text, i, w, 0, w.Length) == 0);
                    if (word != null) { result.Add(new TextSpan { Start = i, Length = word.Length }); i += word.Length; }
                    else i += char.IsHighSurrogate(text[i]) && i + 1 < text.Length && char.IsLowSurrogate(text[i + 1]) ? 2 : 1;
                }
                return result;
            }
        }
    }
}
