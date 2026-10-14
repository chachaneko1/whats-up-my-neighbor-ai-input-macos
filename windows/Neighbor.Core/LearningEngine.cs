using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

namespace Neighbor.Core
{
    // Pure, clock-driven model. The UI must revalidate the same focused paste
    // range at the deadline before calling Complete and approving the candidate.
    // Only bounded word fragments are exposed; full sentences are never stored.
    public sealed class LearningEngine
    {
        private readonly IWordSegmenter segmenter;
        private VocabularyCandidate pending;
        private string signature;
        private DateTime changedUtc;
        private DateTime? startedUtc;
        private bool expired, announced, ready;
        public VocabularyCandidate Pending { get { return Copy(pending); } }
        public DateTime? CountdownUntilUtc { get; private set; }
        public LearningEngine(IWordSegmenter segmenter)
        { this.segmenter = segmenter ?? throw new ArgumentNullException(nameof(segmenter)); }

        public VocabularyCandidate Observe(string original, string corrected, DateTime nowUtc)
        {
            if (expired) return null;
            if (!startedUtc.HasValue) startedUtc = nowUtc;
            if (HasExpired(nowUtc)) return null;
            original = original ?? ""; corrected = corrected ?? "";
            if (original.Length > 32768 || corrected.Length > 32768) { Invalidate(); return null; }
            string currentSignature;
            using (var hash = SHA256.Create())
                currentSignature = Convert.ToBase64String(hash.ComputeHash(Encoding.UTF8.GetBytes(original.Length + ":" + original + corrected)));
            if (signature == currentSignature) return Copy(pending);
            signature = currentSignature; Invalidate();
            pending = Extract(original, corrected, nowUtc);
            changedUtc = nowUtc;
            return Copy(pending);
        }
        public VocabularyCandidate Poll(DateTime nowUtc)
        {
            if (HasExpired(nowUtc) || pending == null || announced || nowUtc < changedUtc.AddMilliseconds(1100)) return null;
            announced = true; CountdownUntilUtc = nowUtc.AddSeconds(2);
            return Copy(pending);
        }
        public bool IsReadyToCommit(DateTime nowUtc)
        {
            if (HasExpired(nowUtc)) return false;
            ready = pending != null && announced && CountdownUntilUtc.HasValue && nowUtc >= CountdownUntilUtc.Value;
            return ready;
        }
        public VocabularyCandidate Complete()
        {
            if (!ready || pending == null) return null;
            var candidate = Copy(pending); Invalidate(); return candidate;
        }
        // Cancel deliberately retains the signature: repeated UIA notifications
        // cannot re-propose a correction that the user just declined.
        public void Cancel() { Invalidate(); }
        public void Reset()
        { Invalidate(); signature = null; startedUtc = null; expired = false; }
        private void Invalidate() { pending = null; announced = false; ready = false; CountdownUntilUtc = null; }
        private bool HasExpired(DateTime nowUtc)
        {
            if (startedUtc.HasValue && nowUtc >= startedUtc.Value.AddMinutes(2)) { expired = true; Invalidate(); }
            return expired;
        }
        private VocabularyCandidate Extract(string original, string corrected, DateTime nowUtc)
        {
            if (original == corrected) return null;
            var before = UnicodeText.Scalars(original); var after = UnicodeText.Scalars(corrected);
            int prefix = 0, suffix = 0;
            while (prefix < Math.Min(before.Count, after.Count) && before[prefix] == after[prefix]) prefix++;
            while (suffix < before.Count - prefix && suffix < after.Count - prefix && before[before.Count - suffix - 1] == after[after.Count - suffix - 1]) suffix++;
            int removedCount = before.Count - prefix - suffix, insertedCount = after.Count - prefix - suffix;
            string removed = string.Concat(before.Skip(prefix).Take(removedCount));
            string inserted = string.Concat(after.Skip(prefix).Take(insertedCount));
            if (!UnicodeText.Scalars(removed + inserted).Any(UnicodeText.IsLetterOrNumber)) return null;
            int changeStart = before.Take(prefix).Sum(s => s.Length);
            int originalEnd = changeStart + removed.Length, correctedEnd = changeStart + inserted.Length;
            var originalWords = Words(original); var editedWords = Words(corrected);
            if (inserted.Length == 0)
            {
                var affected = originalWords.Where(w => w.Start < originalEnd && changeStart < w.Start + w.Length).ToList();
                if (affected.Count > 0 && affected.All(w => changeStart <= w.Start && originalEnd >= w.Start + w.Length)) return null;
            }
            var destinations = editedWords.Where(w => w.Start <= changeStart && w.Start + w.Length >= correctedEnd).ToList();
            if (inserted.Length == 0)
            {
                var interior = destinations.Where(w => w.Start < changeStart && changeStart < w.Start + w.Length).ToList();
                if (interior.Count > 0) destinations = interior;
            }
            var matches = new List<VocabularyCandidate>();
            foreach (var destination in destinations)
            {
                int sourceEnd = destination.Start + destination.Length + removed.Length - inserted.Length;
                if (sourceEnd <= destination.Start || sourceEnd > original.Length || !UnicodeText.IsBoundary(original, destination.Start) || !UnicodeText.IsBoundary(original, sourceEnd)) continue;
                string originalTerm = original.Substring(destination.Start, sourceEnd - destination.Start);
                string correctedTerm = corrected.Substring(destination.Start, destination.Length);
                if (!IsTerm(originalTerm) || !IsTerm(correctedTerm)) continue;
                int sourceWordCount = originalWords.Count(w => w.Start < sourceEnd && destination.Start < w.Start + w.Length);
                if (sourceWordCount == 0) continue;
                if (sourceWordCount > 1)
                {
                    int unchanged = UnicodeText.Count(correctedTerm) - insertedCount;
                    if (unchanged <= 0 || removedCount > 2 || insertedCount > 2) continue;
                }
                if (!matches.Any(c => c.Original == originalTerm && c.Corrected == correctedTerm))
                    matches.Add(new VocabularyCandidate { Original = originalTerm, Corrected = correctedTerm, CreatedUtc = nowUtc });
            }
            return matches.Count == 1 ? matches[0] : null;
        }
        private List<TextSpan> Words(string text)
        {
            var result = new List<TextSpan>();
            IReadOnlyList<TextSpan> raw;
            try { raw = segmenter.GetWords(text); } catch { return result; }
            foreach (var span in raw ?? new List<TextSpan>())
            {
                if (span == null || span.Start < 0 || span.Length <= 0 || span.Start > text.Length - span.Length ||
                    !UnicodeText.IsBoundary(text, span.Start) || !UnicodeText.IsBoundary(text, span.Start + span.Length)) continue;
                int start = span.Start, end = start + span.Length;
                string word = text.Substring(start, span.Length);
                if (!UnicodeText.Scalars(word).Any(UnicodeText.IsLetterOrNumber)) continue;
                if (word.All(UnicodeText.IsAsciiWord))
                {
                    while (start > 0 && UnicodeText.IsAsciiWord(text[start - 1])) start--;
                    while (end < text.Length && UnicodeText.IsAsciiWord(text[end])) end++;
                }
                if (!result.Any(w => w.Start == start && w.Length == end - start)) result.Add(new TextSpan { Start = start, Length = end - start });
            }
            return result;
        }
        private static bool IsTerm(string term)
        {
            return term.Length > 0 && UnicodeText.Count(term) <= VocabularyStore.MaximumTermLength &&
                UnicodeText.Scalars(term).Any(UnicodeText.IsLetterOrNumber) && !term.Any(char.IsWhiteSpace) &&
                term.IndexOfAny("。！？；.!?;\r\n".ToCharArray()) < 0;
        }
        private static VocabularyCandidate Copy(VocabularyCandidate c)
        { return c == null ? null : new VocabularyCandidate { Id = c.Id, Original = c.Original, Corrected = c.Corrected, Status = c.Status, CreatedUtc = c.CreatedUtc }; }
    }
}
