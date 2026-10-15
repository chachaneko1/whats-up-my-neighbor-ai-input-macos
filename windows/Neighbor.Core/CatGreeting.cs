using System;
using System.Text.RegularExpressions;

namespace Neighbor.Core
{
    /// <summary>Exact utterance matching, before dictation cleanup or vocabulary changes.</summary>
    public static class CatGreeting
    {
        // Only surrounding punctuation is ignored. Do not erase punctuation inside
        // words: e.g. "what-s up" is ordinary dictation, not a greeting.
        private static readonly Regex Phrase = new Regex(
            @"\A[\s\p{P}]*(?:what['’‘ʼ＇]?s\s+up|what\s+is\s+up)[\s\p{P}]*\z",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        public static bool IsMatch(string text)
        {
            return text != null && Phrase.IsMatch(text);
        }
    }
}
