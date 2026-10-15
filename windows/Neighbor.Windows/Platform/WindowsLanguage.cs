using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Neighbor.Core;

namespace Neighbor.Windows.Platform
{
    public sealed class WindowsTextNormalizer : ITextNormalizer
    {
        public string ToTraditional(string text)
        {
            if (string.IsNullOrEmpty(text)) return text ?? "";
            // NLS is intentionally the converter. These narrow, contextual corrections
            // preserve the Mac fixtures without shipping a second conversion dictionary.
            text = text.Replace("头发", "頭髮").Replace("頭發", "頭髮")
                .Replace("里面", "裡面").Replace("裏面", "裡面");
            text = Regex.Replace(text, "(頭髮|衣服|衣物|毛巾)(已經|已经|都|也|快|已|全)?干了", "$1$2乾了");
            int size = LCMapStringEx("zh-TW", 0x04000000, text, text.Length, null, 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (size == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "Windows 繁體中文轉換失敗。");
            var result = new StringBuilder(size);
            if (LCMapStringEx("zh-TW", 0x04000000, text, text.Length, result, size, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero) == 0)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Windows 繁體中文轉換失敗。");
            return result.ToString();
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int LCMapStringEx(string locale, uint flags, string source, int sourceLength,
            StringBuilder destination, int destinationLength, IntPtr version, IntPtr reserved, IntPtr sortHandle);
    }

    public sealed class WindowsWordSegmenter : IWordSegmenter
    {
        public IReadOnlyList<TextSpan> GetWords(string text)
        {
            var spans = new List<TextSpan>();
            if (string.IsNullOrEmpty(text)) return spans;
            var segmenter = new global::Windows.Data.Text.WordsSegmenter("zh-Hant");
            foreach (var word in segmenter.GetTokens(text))
            {
                int start = checked((int)word.SourceTextSegment.StartPosition);
                int length = checked((int)word.SourceTextSegment.Length);
                if (start >= 0 && length > 0 && start + length <= text.Length &&
                    !(start > 0 && char.IsLowSurrogate(text[start])) &&
                    !(start + length < text.Length && char.IsLowSurrogate(text[start + length])))
                    spans.Add(new TextSpan { Start = start, Length = length });
            }
            return spans;
        }
    }
}
