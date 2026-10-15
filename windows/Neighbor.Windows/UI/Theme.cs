using System;
using System.Drawing;
using System.Windows.Forms;

namespace Neighbor.Windows.UI
{
    public static class Theme
    {
        public static readonly Color Background = Color.FromArgb(247, 246, 243);
        public static readonly Color Ink = Color.FromArgb(32, 34, 39);
        public static readonly Color Muted = Color.FromArgb(96, 99, 107);
        public static readonly Color Accent = Color.FromArgb(83, 91, 216);

        public static Icon LoadIcon()
        {
            using (var stream = typeof(Theme).Assembly.GetManifestResourceStream("Neighbor.cat.ico"))
            {
                if (stream == null) return (Icon)SystemIcons.Application.Clone();
                using (var icon = new Icon(stream)) return (Icon)icon.Clone();
            }
        }

        public static Image LoadCatImage()
        {
            using (var stream = typeof(Theme).Assembly.GetManifestResourceStream("Neighbor.cat.png"))
            {
                if (stream == null) return new Bitmap(1, 1);
                using (var image = Image.FromStream(stream)) return new Bitmap(image);
            }
        }

        public static void Style(Form form, string title, Size size)
        {
            form.Text = title;
            form.Icon = LoadIcon();
            form.Font = new Font("Microsoft JhengHei UI", 10F);
            form.BackColor = Background;
            form.ForeColor = Ink;
            form.AutoScaleDimensions = new SizeF(96F, 96F);
            form.AutoScaleMode = AutoScaleMode.Dpi;
            form.ClientSize = size;
            form.StartPosition = FormStartPosition.CenterScreen;
            form.MinimumSize = new Size(size.Width, Math.Min(size.Height, 480));
            form.Shown += (sender, args) =>
            {
                var area = Screen.FromControl(form).WorkingArea;
                var available = new Size(Math.Max(320, area.Width - 24), Math.Max(300, area.Height - 24));
                form.MinimumSize = new Size(Math.Min(form.MinimumSize.Width, available.Width), Math.Min(form.MinimumSize.Height, available.Height));
                form.Size = new Size(Math.Min(form.Width, available.Width), Math.Min(form.Height, available.Height));
                form.Location = new Point(Math.Max(area.Left + 12, Math.Min(form.Left, area.Right - form.Width - 12)), Math.Max(area.Top + 12, Math.Min(form.Top, area.Bottom - form.Height - 12)));
            };
        }

        public static Button Button(string text, EventHandler clicked, bool primary = false)
        {
            var button = new Button { Text = text, AutoSize = true, MinimumSize = new Size(88, 34), Padding = new Padding(9, 3, 9, 3), FlatStyle = FlatStyle.Flat, Cursor = Cursors.Hand };
            button.FlatAppearance.BorderColor = primary ? Accent : Color.FromArgb(210, 211, 218);
            button.BackColor = primary ? Accent : Color.White;
            button.ForeColor = primary ? Color.White : Ink;
            if (clicked != null) button.Click += clicked;
            return button;
        }

        public static Label Label(string text, bool muted = false)
        {
            return new Label { Text = text, AutoSize = true, MaximumSize = new Size(540, 0), ForeColor = muted ? Muted : Ink, Margin = new Padding(0, 6, 0, 8) };
        }

        public static FlowLayoutPanel ButtonRow(params Control[] controls)
        {
            var row = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Bottom, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(14, 10, 14, 10), WrapContents = false };
            row.Controls.AddRange(controls);
            return row;
        }

        public static void Error(IWin32Window owner, string message)
        {
            MessageBox.Show(owner, message, "請稍後再試", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    public class NonActivatingForm : Form
    {
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams
        {
            get
            {
                var parameters = base.CreateParams;
                parameters.ExStyle |= 0x08000000 | 0x00000080; // WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW
                return parameters;
            }
        }
        protected override void WndProc(ref Message message)
        {
            if (message.Msg == 0x0021) { message.Result = (IntPtr)3; return; } // MA_NOACTIVATE
            base.WndProc(ref message);
        }
    }
}
