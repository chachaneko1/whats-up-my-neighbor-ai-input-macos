using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;

namespace Neighbor.Core
{
    public static class LanguagePolicy
    {
        public static IReadOnlyDictionary<string, string> Languages { get; } = new ReadOnlyDictionary<string, string>(
            new Dictionary<string, string> { { "zh", "繁體中文" }, { "en", "英文" }, { "ja", "日文" }, { "ko", "韓文" },
                { "th", "泰文" }, { "vi", "越南文" }, { "es", "西班牙文" }, { "fr", "法文" }, { "de", "德文" } });
        public static bool IsSupported(string code) { return code != null && Languages.ContainsKey(code); }
        public static string BasePrompt(string primary, bool strengthened = false)
        {
            string result;
            switch (primary)
            {
                case "zh": result = "繁體中文口述，使用台灣繁體字形與自然標點。保留原話、法律用語與英文專有名詞。"; break;
                case "ja": result = "日本語の音声入力。自然な句読点。英語の固有名詞を保持。"; break;
                case "ko": result = "한국어 음성 입력. 자연스러운 문장 부호. 영어 고유명사 유지."; break;
                case "th": result = "Thai dictation with natural punctuation. Preserve English proper nouns."; break;
                case "vi": result = "Vietnamese dictation with natural punctuation. Preserve English proper nouns."; break;
                case "es": result = "Spanish dictation with natural punctuation. Preserve English proper nouns."; break;
                case "fr": result = "French dictation with natural punctuation. Preserve English proper nouns."; break;
                case "de": result = "German dictation with natural punctuation. Preserve English proper nouns."; break;
                default: result = "English dictation with natural punctuation. Preserve proper nouns."; break;
            }
            return strengthened ? result + " Transcribe only the spoken language; do not translate." : result;
        }
        // This is a permissive script gate, not language identification. English,
        // Vietnamese, Spanish, French and German share the same Latin allowance.
        public static bool ShouldIntercept(string text, AppSettings settings)
        {
            settings = settings ?? new AppSettings();
            var allowed = new HashSet<string> { IsSupported(settings.PrimaryLanguage) ? settings.PrimaryLanguage : "zh" };
            int count = 0;
            foreach (var code in settings.AdditionalLanguages ?? new List<string>())
            { if (count++ >= 2) break; if (IsSupported(code)) allowed.Add(code); }
            int letters = 0, disallowed = 0;
            foreach (var scalar in UnicodeText.Scalars(text))
            {
                if (!UnicodeText.IsLetter(scalar)) continue;
                letters++;
                bool accepted = false;
                foreach (var code in allowed) if (Allows(code, scalar)) { accepted = true; break; }
                if (!accepted) disallowed++;
            }
            return letters >= 6 && (double)disallowed / letters >= 0.5;
        }
        private static bool Allows(string language, string scalar)
        {
            int c = UnicodeText.CodePoint(scalar);
            switch (language)
            {
                case "zh": return UnicodeText.IsHan(scalar);
                case "ja": return UnicodeText.IsHan(scalar) || UnicodeText.Between(c, 0x3040, 0x30FF) || UnicodeText.Between(c, 0x31F0, 0x31FF) ||
                    UnicodeText.Between(c, 0xFF66, 0xFF9D) || UnicodeText.Between(c, 0x1B000, 0x1B16F);
                case "ko": return UnicodeText.IsHan(scalar) || UnicodeText.Between(c, 0x1100, 0x11FF) || UnicodeText.Between(c, 0x3130, 0x318F) ||
                    UnicodeText.Between(c, 0xA960, 0xA97F) || UnicodeText.Between(c, 0xAC00, 0xD7AF) || UnicodeText.Between(c, 0xD7B0, 0xD7FF) || UnicodeText.Between(c, 0xFFA0, 0xFFDC);
                case "th": return UnicodeText.Between(c, 0x0E00, 0x0E7F);
                default: return UnicodeText.IsLatin(scalar);
            }
        }
    }
}
