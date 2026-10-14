using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;

namespace Neighbor.Core
{
    public sealed class VocabularyStore
    {
        public const int MaximumEntries = 200, MaximumTermLength = 40, MaximumCandidates = 500, MaximumPromptBytes = 200;
        public const string Waiting = "等待確認", Added = "已加入", Rejected = "不加入", Cancelled = "已取消";
        public sealed class Document
        {
            public int Version { get; set; }
            public List<VocabularyEntry> Entries { get; set; }
            public List<VocabularyCandidate> Candidates { get; set; }
        }
        private readonly string path;
        private List<VocabularyEntry> entries = new List<VocabularyEntry>();
        private List<VocabularyCandidate> candidates = new List<VocabularyCandidate>();
        public event Action Changed;
        public string LoadError { get; private set; }
        public IReadOnlyList<VocabularyEntry> Entries { get { return entries.Select(Clone).ToList().AsReadOnly(); } }
        public IReadOnlyList<VocabularyCandidate> Candidates { get { return candidates.Select(Clone).ToList().AsReadOnly(); } }

        public VocabularyStore(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) throw new ArgumentException("詞典路徑不可空白。", nameof(path));
            this.path = Path.GetFullPath(path);
            if (!File.Exists(this.path)) return;
            try
            {
                if (new FileInfo(this.path).Length > 1024 * 1024) throw new InvalidDataException();
                var doc = Serializer().Deserialize<Document>(File.ReadAllText(this.path, Encoding.UTF8));
                ValidateDocument(doc);
                entries = doc.Entries.Select(Clone).ToList(); candidates = doc.Candidates.Select(Clone).ToList();
            }
            // InvalidDataException derives directly from SystemException on
            // .NET Framework, so it must not rely on the IOException branch.
            catch (Exception ex) when (ex is InvalidDataException || ex is IOException || ex is UnauthorizedAccessException || ex is ArgumentException || ex is InvalidOperationException)
            { LoadError = "詞典資料無法讀取，暫停修改以保留原資料。請先備份詞典檔案。"; }
        }
        public VocabularyEntry Add(string term)
        {
            EnsureWritable(); term = ValidateTerm(term);
            if (Contains(term)) throw new InvalidOperationException("詞典裡已經有相同的常用詞。");
            if (entries.Count >= MaximumEntries) throw new InvalidOperationException("常用詞典最多可儲存 200 筆。");
            var entry = new VocabularyEntry { Term = term };
            var next = entries.Select(Clone).ToList(); next.Add(entry);
            Save(next, candidates); return Clone(entry);
        }
        public bool Contains(string term) { return entries.Any(e => UnicodeText.Fold(e.Term) == UnicodeText.Fold(term)); }
        public void Update(VocabularyEntry entry)
        {
            EnsureWritable();
            if (entry == null) throw new ArgumentNullException(nameof(entry));
            int index = entries.FindIndex(e => e.Id == entry.Id);
            if (index < 0) throw new InvalidOperationException("找不到這筆常用詞，請重新開啟詞典。");
            string term = ValidateTerm(entry.Term);
            if (entries.Any(e => e.Id != entry.Id && UnicodeText.Fold(e.Term) == UnicodeText.Fold(term)))
                throw new InvalidOperationException("詞典裡已經有相同的常用詞。");
            var next = entries.Select(Clone).ToList(); next[index] = Clone(entry); next[index].Term = term; next[index].UpdatedUtc = DateTime.UtcNow;
            Save(next, candidates);
        }
        public void Remove(string id)
        {
            EnsureWritable(); if (!entries.Any(e => e.Id == id)) return;
            Save(entries.Where(e => e.Id != id).Select(Clone).ToList(), candidates);
        }
        public VocabularyCandidate AddCandidate(VocabularyCandidate candidate)
        {
            EnsureWritable(); ValidateCandidate(candidate);
            if (Contains(candidate.Corrected)) return null;
            string folded = UnicodeText.Fold(candidate.Corrected);
            var existing = candidates.FirstOrDefault(c => UnicodeText.Fold(c.Corrected) == folded && c.Status == Rejected);
            if (existing != null) return null;
            existing = candidates.FirstOrDefault(c => UnicodeText.Fold(c.Corrected) == folded && c.Status == Waiting);
            if (existing != null) return Clone(existing);
            if (candidates.Count >= MaximumCandidates) throw new InvalidOperationException("學習紀錄已達 500 筆，請先刪除不需要的紀錄。");
            var added = Clone(candidate); added.Status = Waiting;
            if (candidates.Any(c => c.Id == added.Id)) added.Id = Guid.NewGuid().ToString("N");
            var next = candidates.Select(Clone).ToList(); next.Insert(0, added);
            Save(entries, next); return Clone(added);
        }
        public void SetCandidateStatus(string id, string status)
        {
            EnsureWritable(); ValidateStatus(status);
            int index = candidates.FindIndex(c => c.Id == id);
            if (index < 0) throw new InvalidOperationException("找不到這筆學習紀錄。");
            var nextEntries = entries.Select(Clone).ToList();
            // Approval and insertion are one atomic document update. Capacity or
            // disk failures leave the candidate pending and the dictionary intact.
            if (status == Added && !Contains(candidates[index].Corrected))
            {
                if (entries.Count >= MaximumEntries) throw new InvalidOperationException("常用詞典最多可儲存 200 筆。");
                nextEntries.Add(new VocabularyEntry { Term = candidates[index].Corrected });
            }
            var next = candidates.Select(Clone).ToList(); next[index].Status = status;
            Save(nextEntries, next);
        }
        public void RemoveCandidate(string id)
        {
            EnsureWritable(); if (!candidates.Any(c => c.Id == id)) return;
            Save(entries, candidates.Where(c => c.Id != id).Select(Clone).ToList());
        }
        public VocabularyPrompt BuildPrompt(string basePrompt)
        {
            string baseText = UnicodeText.TruncateUtf8((basePrompt ?? "").Trim(), MaximumPromptBytes);
            var result = new VocabularyPrompt { Text = baseText };
            var includedTerms = new List<string>();
            foreach (var entry in entries.Where(e => e.Enabled).OrderByDescending(e => e.Pinned).ThenByDescending(e => e.UpdatedUtc).ThenBy(e => e.Id, StringComparer.Ordinal))
            {
                var proposed = includedTerms.Concat(new[] { entry.Term });
                string prompt = baseText + " 常用詞：" + string.Join("、", proposed) + "。";
                if (Encoding.UTF8.GetByteCount(prompt) > MaximumPromptBytes) { result.ExcludedIds.Add(entry.Id); continue; }
                includedTerms.Add(entry.Term); result.IncludedIds.Add(entry.Id); result.Text = prompt;
            }
            return result;
        }
        private void EnsureWritable()
        { if (LoadError != null) throw new InvalidOperationException(LoadError); }
        private static string ValidateTerm(string raw)
        {
            string term = (raw ?? "").Trim();
            if (term.Length == 0) throw new InvalidOperationException("常用詞不能是空白。");
            if (UnicodeText.Count(term) > MaximumTermLength) throw new InvalidOperationException("每個常用詞最多 40 個字。");
            foreach (var scalar in UnicodeText.Scalars(term))
                if (char.IsControl(scalar, 0) || (scalar.Length == 1 && char.IsSurrogate(scalar[0])))
                    throw new InvalidOperationException("常用詞不能包含換行、控制字元或無效字元。");
            return term;
        }
        private static void ValidateCandidate(VocabularyCandidate candidate)
        {
            if (candidate == null || string.IsNullOrWhiteSpace(candidate.Id)) throw new InvalidOperationException("學習紀錄無效。");
            foreach (var term in new[] { candidate.Original, candidate.Corrected })
            {
                ValidateTerm(term);
                if (term.Any(char.IsWhiteSpace) || term.IndexOfAny("。！？；.!?;\r\n".ToCharArray()) >= 0 ||
                    !UnicodeText.Scalars(term).Any(UnicodeText.IsLetterOrNumber))
                    throw new InvalidOperationException("這次變更不像單一詞彙修正，請手動新增常用詞。");
            }
            ValidateStatus(candidate.Status);
        }
        private static void ValidateStatus(string status)
        { if (status != Waiting && status != Added && status != Rejected && status != Cancelled) throw new InvalidOperationException("學習紀錄狀態無效。"); }
        private static void ValidateDocument(Document document)
        {
            if (document == null || document.Version != 1 || document.Entries == null || document.Candidates == null ||
                document.Entries.Count > MaximumEntries || document.Candidates.Count > MaximumCandidates) throw new InvalidDataException();
            var ids = new HashSet<string>(); var terms = new HashSet<string>();
            foreach (var entry in document.Entries)
            {
                if (entry == null || string.IsNullOrWhiteSpace(entry.Id) || !ids.Add(entry.Id)) throw new InvalidDataException();
                ValidateTerm(entry.Term); if (!terms.Add(UnicodeText.Fold(entry.Term))) throw new InvalidDataException();
            }
            ids.Clear();
            foreach (var candidate in document.Candidates)
            { ValidateCandidate(candidate); if (!ids.Add(candidate.Id)) throw new InvalidDataException(); }
        }
        private static JavaScriptSerializer Serializer() { return new JavaScriptSerializer { MaxJsonLength = 1024 * 1024, RecursionLimit = 16 }; }
        private void Save(List<VocabularyEntry> nextEntries, List<VocabularyCandidate> nextCandidates)
        {
            var doc = new Document { Version = 1, Entries = nextEntries.Select(Clone).ToList(), Candidates = nextCandidates.Select(Clone).ToList() };
            ValidateDocument(doc);
            string directory = Path.GetDirectoryName(path); Directory.CreateDirectory(directory);
            string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                byte[] bytes = new UTF8Encoding(false).GetBytes(Serializer().Serialize(doc));
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                { stream.Write(bytes, 0, bytes.Length); stream.Flush(true); }
                if (File.Exists(path)) File.Replace(temporary, path, null);
                else File.Move(temporary, path);
                entries = doc.Entries; candidates = doc.Candidates;
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
            Changed?.Invoke();
        }
        private static VocabularyEntry Clone(VocabularyEntry e)
        { return new VocabularyEntry { Id = e.Id, Term = e.Term, Enabled = e.Enabled, Pinned = e.Pinned, UpdatedUtc = e.UpdatedUtc }; }
        private static VocabularyCandidate Clone(VocabularyCandidate c)
        { return new VocabularyCandidate { Id = c.Id, Original = c.Original, Corrected = c.Corrected, Status = c.Status, CreatedUtc = c.CreatedUtc }; }
    }
}
