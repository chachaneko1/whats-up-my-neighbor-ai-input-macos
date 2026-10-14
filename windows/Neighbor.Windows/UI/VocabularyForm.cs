using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using Neighbor.Core;

namespace Neighbor.Windows.UI
{
    public sealed class VocabularyForm : Form
    {
        private readonly VocabularyStore store;
        private readonly TextBox search = new TextBox { Dock = DockStyle.Top, AccessibleName = "搜尋詞典" };
        private readonly ListView entries = List(), candidates = List();
        private readonly Button approveCandidate, rejectCandidate;
        private readonly Label status = Theme.Label("", true), count = Theme.Label("", true);
        private readonly HashSet<string> included = new HashSet<string>(), excluded = new HashSet<string>();
        private bool promptKnown, refreshing, refreshQueued;
        private string learningStatus = "修正已貼入的文字時，支援的輸入欄位可提供詞典候選。";
        public string LearningStatus
        {
            get { return learningStatus; }
            set { learningStatus = value ?? ""; QueueRefresh(); }
        }

        public VocabularyForm(VocabularyStore store)
        {
            this.store = store ?? throw new ArgumentNullException(nameof(store));
            Theme.Style(this, "小黑貓 · 我的詞典", new Size(770, 560));
            MinimumSize = new Size(660, 460);
            var tabs = new TabControl { Dock = DockStyle.Fill, Padding = new Point(16, 8) };
            var wordsPage = new TabPage("我的詞彙") { Padding = new Padding(14), BackColor = Theme.Background };
            var candidatesPage = new TabPage("修正候選") { Padding = new Padding(14), BackColor = Theme.Background };
            tabs.TabPages.AddRange(new[] { wordsPage, candidatesPage });
            entries.Columns.Add("詞彙", 250); entries.Columns.Add("狀態", 170); entries.Columns.Add("釘選", 70);
            entries.CheckBoxes = true;
            candidates.Columns.Add("原文字", 220); candidates.Columns.Add("修正詞彙", 220); candidates.Columns.Add("狀態", 130);
            search.Margin = new Padding(0, 8, 0, 10);
            search.TextChanged += (sender, args) => RefreshLists();
            var searchHeader = new Panel { Dock = DockStyle.Top, Height = 64 };
            var searchLabel = Theme.Label("搜尋詞彙"); searchLabel.Dock = DockStyle.Top;
            searchHeader.Controls.Add(search); searchHeader.Controls.Add(searchLabel);
            entries.ItemChecked += EntryChecked;
            entries.DoubleClick += (sender, args) => EditSelected();
            var add = Theme.Button("新增", (sender, args) => AddTerm(), true);
            var edit = Theme.Button("編輯", (sender, args) => EditSelected());
            var pin = Theme.Button("釘選／取消", (sender, args) => TogglePin());
            var remove = Theme.Button("刪除", (sender, args) => RemoveSelected());
            wordsPage.Controls.Add(entries); wordsPage.Controls.Add(searchHeader);
            wordsPage.Controls.Add(Theme.ButtonRow(add, edit, pin, remove));
            var candidateHelp = Theme.Label("僅從這次確定貼入的文字範圍收集。你也可以在這裡手動加入或拒絕候選。", true);
            candidateHelp.Dock = DockStyle.Top; candidateHelp.MaximumSize = new Size(680, 0);
            candidatesPage.Controls.Add(candidates); candidatesPage.Controls.Add(candidateHelp);
            approveCandidate = Theme.Button("加入詞典", (sender, args) => AcceptCandidate(), true);
            rejectCandidate = Theme.Button("不加入", (sender, args) => RejectCandidate());
            approveCandidate.Enabled = rejectCandidate.Enabled = false;
            candidates.SelectedIndexChanged += (sender, args) => UpdateCandidateActions();
            candidatesPage.Controls.Add(Theme.ButtonRow(
                approveCandidate,
                rejectCandidate,
                Theme.Button("刪除紀錄", (sender, args) => RemoveCandidate())));
            var footer = new FlowLayoutPanel { Dock = DockStyle.Bottom, AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(16, 6, 16, 12) };
            count.MaximumSize = status.MaximumSize = new Size(700, 0);
            footer.Controls.Add(count); footer.Controls.Add(status);
            Controls.Add(tabs); Controls.Add(footer);
            store.Changed += QueueRefresh;
            Shown += (sender, args) => RefreshLists();
            Activated += (sender, args) => RefreshLists();
            RefreshLists();
        }

        public void UpdatePrompt(VocabularyPrompt prompt)
        {
            if (IsDisposed) return;
            if (InvokeRequired) { BeginInvoke(new Action(() => UpdatePrompt(prompt))); return; }
            promptKnown = prompt != null; included.Clear(); excluded.Clear();
            if (prompt != null)
            {
                foreach (var id in prompt.IncludedIds) included.Add(id);
                foreach (var id in prompt.ExcludedIds) excluded.Add(id);
            }
            RefreshLists();
        }

        private void QueueRefresh()
        {
            if (IsDisposed || Disposing || !IsHandleCreated || refreshQueued) return;
            refreshQueued = true;
            try { BeginInvoke(new Action(() => { refreshQueued = false; if (!IsDisposed) RefreshLists(); })); }
            catch (InvalidOperationException) { refreshQueued = false; }
        }

        private void RefreshLists()
        {
            if (IsDisposed || refreshing) return;
            refreshing = true;
            var selectedEntry = SelectedId(entries); var selectedCandidate = SelectedId(candidates);
            entries.BeginUpdate(); candidates.BeginUpdate();
            try
            {
                entries.Items.Clear(); candidates.Items.Clear();
                foreach (var entry in store.Entries.Where(item => String.IsNullOrEmpty(search.Text) || item.Term.IndexOf(search.Text, StringComparison.CurrentCultureIgnoreCase) >= 0).OrderByDescending(item => item.Pinned).ThenBy(item => item.Term))
                {
                    string applied = !entry.Enabled ? "已停用" : !promptKnown ? "下次辨識時套用" : included.Contains(entry.Id) ? "已列入辨識提示" : excluded.Contains(entry.Id) ? "提示已滿，暫未列入" : "下次辨識時套用";
                    var item = new ListViewItem(new[] { entry.Term, applied, entry.Pinned ? "已釘選" : "" }) { Tag = entry.Id, Checked = entry.Enabled, Selected = entry.Id == selectedEntry };
                    entries.Items.Add(item);
                }
                foreach (var candidate in store.Candidates.OrderByDescending(item => item.CreatedUtc))
                    candidates.Items.Add(new ListViewItem(new[] { candidate.Original ?? "", candidate.Corrected ?? "", candidate.Status ?? "" }) { Tag = candidate.Id, Selected = candidate.Id == selectedCandidate });
                count.Text = $"{store.Entries.Count} / 200 個詞彙 · 每詞最多 40 個字 · 勾選啟用，釘選優先列入提示";
                status.Text = String.IsNullOrEmpty(store.LoadError) ? learningStatus : store.LoadError;
                UpdateCandidateActions();
            }
            finally { entries.EndUpdate(); candidates.EndUpdate(); refreshing = false; }
        }

        private void EntryChecked(object sender, ItemCheckedEventArgs args)
        {
            if (refreshing) return;
            var entry = store.Entries.FirstOrDefault(item => item.Id == (string)args.Item.Tag);
            if (entry == null) return;
            entry.Enabled = args.Item.Checked;
            try { store.Update(entry); }
            catch (InvalidOperationException exception) { Theme.Error(this, exception.Message); }
            catch { Theme.Error(this, "無法儲存詞典，請確認個人資料夾可寫入。"); }
            QueueRefresh();
        }
        private void AddTerm()
        {
            using (var editor = new TermForm("新增詞彙", ""))
                if (editor.ShowDialog(this) == DialogResult.OK) Try(() => store.Add(editor.Term));
        }
        private void EditSelected()
        {
            var entry = store.Entries.FirstOrDefault(item => item.Id == SelectedId(entries));
            if (entry == null) return;
            using (var editor = new TermForm("編輯詞彙", entry.Term))
                if (editor.ShowDialog(this) == DialogResult.OK) { entry.Term = editor.Term; Try(() => store.Update(entry)); }
        }
        private void TogglePin()
        {
            var entry = store.Entries.FirstOrDefault(item => item.Id == SelectedId(entries));
            if (entry == null) return;
            entry.Pinned = !entry.Pinned; Try(() => store.Update(entry));
        }
        private void RemoveSelected()
        {
            var id = SelectedId(entries); if (id == null) return;
            Try(() => store.Remove(id));
        }
        private void AcceptCandidate()
        {
            var candidate = store.Candidates.FirstOrDefault(item => item.Id == SelectedId(candidates));
            if (candidate == null || candidate.Status == "已加入") return;
            Try(() => store.SetCandidateStatus(candidate.Id, VocabularyStore.Added));
        }
        private void RejectCandidate()
        {
            var candidate = store.Candidates.FirstOrDefault(item => item.Id == SelectedId(candidates));
            if (candidate == null || candidate.Status == VocabularyStore.Added) return;
            Try(() => store.SetCandidateStatus(candidate.Id, VocabularyStore.Rejected));
        }
        private void UpdateCandidateActions()
        {
            var candidate = store.Candidates.FirstOrDefault(item => item.Id == SelectedId(candidates));
            approveCandidate.Enabled = candidate != null && candidate.Status != VocabularyStore.Added;
            rejectCandidate.Enabled = candidate != null && candidate.Status != VocabularyStore.Added && candidate.Status != VocabularyStore.Rejected;
        }
        private void RemoveCandidate()
        {
            var id = SelectedId(candidates); if (id == null) return;
            Try(() => store.RemoveCandidate(id));
        }
        private void Try(Action action)
        {
            try { action(); RefreshLists(); }
            catch (InvalidOperationException exception) { Theme.Error(this, exception.Message); RefreshLists(); }
            catch { Theme.Error(this, "無法儲存詞典，請確認個人資料夾可寫入。"); RefreshLists(); }
        }
        private static string SelectedId(ListView list) { return list.SelectedItems.Count == 0 ? null : (string)list.SelectedItems[0].Tag; }
        private static ListView List() { return new ListView { Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true, HideSelection = false, MultiSelect = false, BorderStyle = BorderStyle.FixedSingle }; }
        protected override void Dispose(bool disposing)
        {
            if (disposing) store.Changed -= QueueRefresh;
            base.Dispose(disposing);
        }
    }

    internal sealed class TermForm : Form
    {
        private readonly TextBox term = new TextBox { Dock = DockStyle.Top, MaxLength = 80, AccessibleName = "詞彙" };
        public string Term { get { return term.Text.Trim(); } }
        public TermForm(string title, string value)
        {
            Theme.Style(this, title, new Size(440, 164));
            FormBorderStyle = FormBorderStyle.FixedDialog; MaximizeBox = MinimizeBox = false;
            StartPosition = FormStartPosition.CenterParent;
            var content = new Panel { Dock = DockStyle.Fill, Padding = new Padding(18) };
            var help = Theme.Label("每個詞彙最多 40 個字，建議加入姓名或專有名詞。", true); help.Dock = DockStyle.Top; help.MaximumSize = new Size(390, 0);
            term.Text = value; content.Controls.Add(term); content.Controls.Add(help);
            var save = Theme.Button("儲存", (sender, args) => { if (Term.Length == 0) { Theme.Error(this, "請輸入詞彙。"); return; } DialogResult = DialogResult.OK; Close(); }, true);
            var cancel = Theme.Button("取消", (sender, args) => { DialogResult = DialogResult.Cancel; Close(); });
            Controls.Add(content); Controls.Add(Theme.ButtonRow(save, cancel));
            AcceptButton = save; CancelButton = cancel;
        }
    }
}
