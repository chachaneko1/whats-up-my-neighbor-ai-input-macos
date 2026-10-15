using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Neighbor.Core
{
    public static class TextRules
    {
        private static readonly HashSet<string> ProtectedParticles = new HashSet<string> {
            "酒吧", "網吧", "吧台", "吧檯", "毛呢", "呢喃", "呢絨", "芝麻", "麻嘛", "哪吒", "剎那", "咖啦", "沙啦", "劈啦", "耶穌", "耶誕", "喇叭" };
        private static readonly string[] DiscourseMarkers = { "然後", "就是說" };
        public static string Process(string text, AppSettings settings, ITextNormalizer normalizer, IEnumerable<string> vocabulary = null)
        {
            settings = settings ?? new AppSettings();
            string output = text ?? "";
            bool chinese = settings.PrimaryLanguage == "zh";
            if (chinese)
            {
                output = normalizer == null ? output : normalizer.ToTraditional(output);
                output = CollapsePunctuation(output);
                output = NormalizePunctuation(output);
                output = CollapsePunctuation(output);
            }
            output = NormalizeSpacing(output);
            foreach (var term in vocabulary ?? Enumerable.Empty<string>())
            {
                if (term == null || !Regex.IsMatch(term, "^[A-Za-z][A-Za-z0-9]*$")) continue;
                string replacement = term;
                output = Regex.Replace(output, "(?<![A-Za-z0-9])" + Regex.Escape(term) + "(?![A-Za-z0-9])",
                    m => replacement, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
            }
            if (chinese && settings.ConvertChineseNumerals) output = ConvertAnchoredNumerals(output);
            if (settings.Mode != OutputMode.Verbatim)
            {
                output = Regex.Replace(output, "^\\s*[呃嗯]+\\s*，?\\s*", "");
                foreach (string marker in DiscourseMarkers)
                    output = Regex.Replace(output, "(^|，)(?:" + marker + "，?\\s*){2,}", "$1");
                output = CollapseRepeatedWords(output);
            }
            if (settings.Mode == OutputMode.Concise) output = RemoveParticles(output);
            return output.Trim();
        }
        private static string CollapsePunctuation(string text)
        { return Regex.Replace(text, "([，。？！、；：,.?!;:])\\1+", "$1"); }
        private static string NormalizePunctuation(string text)
        {
            var source = UnicodeText.Scalars(text); var result = new List<string>();
            for (int i = 0; i < source.Count; i++)
            {
                string scalar = source[i];
                int previous = result.Count - 1;
                while (previous >= 0 && string.IsNullOrWhiteSpace(result[previous])) previous--;
                bool chinesePrevious = previous >= 0 && (UnicodeText.IsHan(result[previous]) || "，。？！、；：".Contains(result[previous]));
                int index = ",.?!;".IndexOf(scalar, StringComparison.Ordinal);
                bool decimalPoint = scalar == "." && i + 1 < source.Count && char.IsDigit(source[i + 1], 0);
                if (chinesePrevious && index >= 0 && !decimalPoint)
                {
                    if (previous + 1 < result.Count) result.RemoveRange(previous + 1, result.Count - previous - 1);
                    result.Add("，。？！；"[index].ToString());
                    while (i + 1 < source.Count && string.IsNullOrWhiteSpace(source[i + 1])) i++;
                }
                else result.Add(scalar);
            }
            return string.Concat(result);
        }
        private static string NormalizeSpacing(string text)
        {
            var b = new StringBuilder(); string previous = null;
            foreach (var scalar in UnicodeText.Scalars(text))
            {
                if (previous != null && ((UnicodeText.IsHan(previous) && UnicodeText.IsAsciiLetter(scalar)) ||
                    (UnicodeText.IsAsciiLetter(previous) && UnicodeText.IsHan(scalar)))) b.Append(' ');
                b.Append(scalar); previous = scalar;
            }
            return Regex.Replace(b.ToString(), "[ \\t]{2,}", " ");
        }
        private static string CollapseRepeatedWords(string text)
        {
            var input = UnicodeText.Scalars(text); var b = new StringBuilder();
            for (int i = 0; i < input.Count;)
            {
                int skip = 0, kept = 0;
                // Match the original greedy 1..4 Han-word policy while never
                // splitting a supplementary-plane character into surrogate halves.
                for (int length = Math.Min(4, input.Count - i); length >= 1; length--)
                {
                    bool han = true; for (int j = 0; j < length; j++) if (!UnicodeText.IsHan(input[i + j])) han = false;
                    if (!han) continue;
                    int second = i + length;
                    if (second < input.Count && input[second] == "，") second++;
                    if (second + length > input.Count) continue;
                    bool equal = true; for (int j = 0; j < length; j++) if (input[i + j] != input[second + j]) equal = false;
                    if (equal) { kept = length; skip = second + length - i; break; }
                }
                if (skip == 0) { b.Append(input[i++]); continue; }
                for (int j = 0; j < kept; j++) b.Append(input[i + j]);
                i += skip;
            }
            return b.ToString();
        }
        private static string RemoveParticles(string text)
        {
            var input = UnicodeText.Scalars(text); var b = new StringBuilder();
            for (int i = 0; i < input.Count; i++)
            {
                bool particle = i > 0 && "啊啦喔耶吧呢嘛囉唷".Contains(input[i]) && UnicodeText.IsHan(input[i - 1]);
                bool ending = i == input.Count - 1 || "，。！？；：".Contains(input[i + 1]);
                if (!(particle && ending && !ProtectedParticles.Contains(input[i - 1] + input[i]))) b.Append(input[i]);
            }
            return b.ToString();
        }
        public static string ConvertAnchoredNumerals(string text)
        {
            const string digits = "零一二三四五六七八九十百千萬兩";
            string output = Regex.Replace(text ?? "", "第([" + digits + "]+)(條|項|款|目|章|節|編)", m => {
                long? value = ChineseNumeralValue(m.Groups[1].Value);
                return value.HasValue ? "第" + value.Value + m.Groups[2].Value : m.Value;
            });
            output = Regex.Replace(output, "([零一二三四五六七八九十百千兩]+)(萬|億)?(元|塊)", m => {
                long? value = ChineseNumeralValue(m.Groups[1].Value);
                return value.HasValue ? value.Value.ToString() + m.Groups[2].Value + m.Groups[3].Value : m.Value;
            });
            return Regex.Replace(output, "百分之([" + digits + "]+)", m => {
                long? value = ChineseNumeralValue(m.Groups[1].Value);
                return value.HasValue ? value.Value + "%" : m.Value;
            });
        }
        public static long? ChineseNumeralValue(string text)
        {
            if (string.IsNullOrEmpty(text)) return null;
            string digits = "零一二三四五六七八九";
            long total = 0, section = 0, current = 0; int previousUnit = 10000;
            bool hasDigit = false, sawWan = false;
            foreach (char c in text)
            {
                int digit = c == '兩' ? 2 : digits.IndexOf(c);
                if (digit >= 0)
                {
                    if (hasDigit && current != 0) return null; // e.g. 一二 is ambiguous.
                    current = digit; hasDigit = true; continue;
                }
                int unit = c == '十' ? 10 : c == '百' ? 100 : c == '千' ? 1000 : c == '萬' ? 10000 : 0;
                if (unit == 0) return null;
                if (unit == 10000)
                {
                    if (sawWan || section + current == 0) return null;
                    total += (section + current) * unit; section = 0; previousUnit = 10000; sawWan = true;
                }
                else
                {
                    if (unit >= previousUnit) return null;
                    section += (current == 0 ? 1 : current) * unit; previousUnit = unit;
                }
                current = 0; hasDigit = false;
            }
            long result = total + section + current;
            return result > 0 || text == "零" ? result : (long?)null;
        }
    }
}
