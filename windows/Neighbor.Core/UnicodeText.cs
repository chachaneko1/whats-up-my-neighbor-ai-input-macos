using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Neighbor.Core
{
    // .NET Framework regex works in UTF-16 code units and has no Unicode Script
    // properties. Keep script decisions and diff boundaries on whole scalars.
    internal static class UnicodeText
    {
        internal static List<string> Scalars(string value)
        {
            var result = new List<string>();
            value = value ?? "";
            for (int i = 0; i < value.Length; i++)
            {
                int length = char.IsHighSurrogate(value[i]) && i + 1 < value.Length && char.IsLowSurrogate(value[i + 1]) ? 2 : 1;
                result.Add(value.Substring(i, length));
                i += length - 1;
            }
            return result;
        }
        internal static int Count(string text) { return Scalars(text).Count; }
        internal static int CodePoint(string scalar) { return scalar.Length == 2 ? char.ConvertToUtf32(scalar, 0) : scalar[0]; }
        internal static bool IsLetter(string scalar)
        {
            var c = CharUnicodeInfo.GetUnicodeCategory(scalar, 0);
            // Newer Han extensions may be absent from Windows' older Unicode table.
            return IsHan(scalar) || c == UnicodeCategory.UppercaseLetter || c == UnicodeCategory.LowercaseLetter ||
                c == UnicodeCategory.TitlecaseLetter || c == UnicodeCategory.ModifierLetter || c == UnicodeCategory.OtherLetter;
        }
        internal static bool IsLetterOrNumber(string scalar)
        {
            return IsLetter(scalar) || CharUnicodeInfo.GetUnicodeCategory(scalar, 0) == UnicodeCategory.DecimalDigitNumber;
        }
        internal static bool IsHan(string scalar)
        {
            int n = CodePoint(scalar);
            return Between(n, 0x3400, 0x4DBF) || Between(n, 0x4E00, 0x9FFF) || Between(n, 0xF900, 0xFAFF) ||
                Between(n, 0x20000, 0x2A6DF) || Between(n, 0x2A700, 0x2B73F) || Between(n, 0x2B740, 0x2B81F) ||
                Between(n, 0x2B820, 0x2CEAF) || Between(n, 0x2CEB0, 0x2EBEF) || Between(n, 0x2EBF0, 0x2EE5F) ||
                Between(n, 0x2F800, 0x2FA1F) || Between(n, 0x30000, 0x3134F) || Between(n, 0x31350, 0x323AF) || n == 0x3007;
        }
        internal static bool IsLatin(string scalar)
        {
            int n = CodePoint(scalar);
            return Between(n, 0x41, 0x5A) || Between(n, 0x61, 0x7A) || Between(n, 0xC0, 0x2E4) ||
                Between(n, 0x1D00, 0x1D7F) || Between(n, 0x1D80, 0x1DBF) || Between(n, 0x1E00, 0x1EFF) ||
                Between(n, 0x2C60, 0x2C7F) || Between(n, 0xA720, 0xA7FF) || Between(n, 0xAB30, 0xAB6F) ||
                Between(n, 0xFF21, 0xFF3A) || Between(n, 0xFF41, 0xFF5A) || Between(n, 0x10780, 0x107BF) || Between(n, 0x1DF00, 0x1DFFF);
        }
        internal static bool Between(int n, int low, int high) { return n >= low && n <= high; }
        internal static bool IsAsciiLetter(string value)
        { return value.Length == 1 && (Between(value[0], 'A', 'Z') || Between(value[0], 'a', 'z')); }
        internal static bool IsAsciiWord(char c)
        { return Between(c, 'A', 'Z') || Between(c, 'a', 'z') || Between(c, '0', '9') || c == '_' || c == '-'; }
        internal static bool IsBoundary(string text, int offset)
        { return offset >= 0 && offset <= text.Length && !(offset > 0 && offset < text.Length && char.IsHighSurrogate(text[offset - 1]) && char.IsLowSurrogate(text[offset])); }
        internal static string Fold(string text)
        {
            var b = new StringBuilder();
            foreach (var s in Scalars((text ?? "").Trim().Normalize(NormalizationForm.FormKD)))
            {
                var c = CharUnicodeInfo.GetUnicodeCategory(s, 0);
                if (c != UnicodeCategory.NonSpacingMark && c != UnicodeCategory.SpacingCombiningMark && c != UnicodeCategory.EnclosingMark) b.Append(s);
            }
            return b.ToString().ToUpperInvariant();
        }
        internal static string TruncateUtf8(string value, int bytes)
        {
            var b = new StringBuilder(); int used = 0;
            foreach (string scalar in Scalars(value))
            { int size = Encoding.UTF8.GetByteCount(scalar); if (used + size > bytes) break; b.Append(scalar); used += size; }
            return b.ToString();
        }
    }
}
