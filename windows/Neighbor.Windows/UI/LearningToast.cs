using System;
using System.Drawing;
using System.Windows.Forms;
using Neighbor.Core;

namespace Neighbor.Windows.UI
{
    public sealed class LearningToast : NonActivatingForm
    {
        private readonly Label message = new Label { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true, Padding = new Padding(16, 8, 8, 8) };
        private readonly Button reject;
        public event Action Rejected;
        public LearningToast()
        {
            Font = new Font("Microsoft JhengHei UI", 10F);
            AutoScaleDimensions = new SizeF(96F, 96F);
            AutoScaleMode = AutoScaleMode.Dpi;
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
            BackColor = Color.FromArgb(36, 38, 44); ForeColor = Color.White;
            ClientSize = new Size(460, 104);
            StartPosition = FormStartPosition.Manual;
            AccessibleName = "詞典學習候選";
            reject = Theme.Button("不加入", (sender, args) => { Hide(); Rejected?.Invoke(); });
            reject.Dock = DockStyle.Right; reject.Width = 100; reject.TabStop = false;
            Controls.Add(message); Controls.Add(reject);
        }

        public void ShowCandidate(VocabularyCandidate candidate, int remainingSeconds)
        {
            if (candidate == null || IsDisposed) return;
            if (InvokeRequired) { BeginInvoke(new Action(() => ShowCandidate(candidate, remainingSeconds))); return; }
            var seconds = Math.Max(0, remainingSeconds);
            message.Text = $"學到「{candidate.Corrected}」\r\n{seconds} 秒後加入詞典，可按「不加入」取消。";
            AccessibleDescription = message.Text;
            if (!Visible)
            {
                var area = Screen.FromPoint(Cursor.Position).WorkingArea;
                Location = new Point(area.Right - Width - 18, area.Bottom - Height - 18);
                Show();
            }
        }
    }
}
