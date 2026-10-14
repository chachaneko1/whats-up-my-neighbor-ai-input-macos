using System;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using Neighbor.Core;

namespace Neighbor.Windows.UI
{
    public sealed class ApiKeyForm : Form
    {
        private readonly ICredentialStore store;
        private readonly TextBox key = new TextBox { UseSystemPasswordChar = true, Width = 450, MaxLength = 512, AccessibleName = "Groq API 金鑰" };
        private readonly Label status = Theme.Label("", true);
        public ApiKeyForm(ICredentialStore store)
        {
            this.store = store ?? throw new ArgumentNullException(nameof(store));
            Theme.Style(this, "小黑貓 · Groq 金鑰", new Size(520, 340));
            MaximizeBox = false;
            var content = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(24) };
            var help = Theme.Label("使用你自己的 Groq API 金鑰。金鑰會保存在此 Windows 帳號的認證管理員。", true);
            help.MaximumSize = new Size(450, 0);
            var cloud = Theme.Label("錄音會送至 Groq 進行辨識。使用量與費用依你的 Groq 帳號方案計算。", true);
            cloud.MaximumSize = new Size(450, 0);
            var link = new LinkLabel { Text = "開啟 Groq 金鑰管理頁面 ↗", AutoSize = true, LinkColor = Theme.Accent, Margin = new Padding(0, 10, 0, 14) };
            link.LinkClicked += (sender, args) =>
            {
                try { Process.Start(new ProcessStartInfo("https://console.groq.com/keys") { UseShellExecute = true }); }
                catch { Theme.Error(this, "無法開啟瀏覽器，請前往 console.groq.com/keys。"); }
            };
            content.Controls.AddRange(new Control[] { help, status, key, link, cloud });
            var save = Theme.Button("儲存金鑰", Save, true);
            var close = Theme.Button("關閉", (sender, args) => Close());
            var remove = Theme.Button("移除金鑰", Remove);
            Controls.Add(content); Controls.Add(Theme.ButtonRow(save, close, remove));
            AcceptButton = save; CancelButton = close;
            RefreshStatus();
            FormClosed += (sender, args) => key.Clear();
        }
        private void RefreshStatus()
        {
            try { status.Text = String.IsNullOrWhiteSpace(store.Read()) ? "尚未設定金鑰" : "已儲存金鑰。輸入新金鑰可取代現有設定。"; }
            catch { status.Text = "目前無法讀取 Windows 認證管理員。"; }
        }
        private void Save(object sender, EventArgs args)
        {
            var value = key.Text.Trim();
            if (String.IsNullOrWhiteSpace(value)) { Theme.Error(this, "請先輸入 Groq API 金鑰。"); return; }
            if (value.IndexOfAny(new[] { '\r', '\n', ' ', '\t' }) >= 0) { Theme.Error(this, "金鑰不能包含空格或換行。"); return; }
            try { store.Write(value); key.Clear(); DialogResult = DialogResult.OK; Close(); }
            catch { Theme.Error(this, "無法儲存金鑰，請確認 Windows 認證管理員可用。"); }
        }
        private void Remove(object sender, EventArgs args)
        {
            try { store.Delete(); key.Clear(); RefreshStatus(); }
            catch { Theme.Error(this, "無法移除金鑰，請稍後再試。"); }
        }
    }
}
