using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using Neighbor.Core;

namespace Neighbor.Windows.UI
{
    public sealed class RecordingHud : NonActivatingForm
    {
        private readonly Image cat = Theme.LoadCatImage();
        private readonly CatActionArea cancel = new CatActionArea(), finish = new CatActionArea();
        private readonly ToolTip tips = new ToolTip();
        private DictationState state;
        private string message = "按快捷鍵開始說話";
        private double level;
        private bool levelKnown, atTop;
        public event Action StartRequested;
        public event Action FinishRequested;
        public event Action CancelRequested;

        public RecordingHud()
        {
            Font = new Font("Microsoft JhengHei UI", 9F);
            AutoScaleDimensions = new SizeF(96F, 96F);
            AutoScaleMode = AutoScaleMode.Dpi;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false; TopMost = true; DoubleBuffered = true;
            BackColor = TransparencyKey = Color.Magenta;
            ClientSize = new Size(340, 220);
            StartPosition = FormStartPosition.Manual;
            AccessibleName = "小黑貓語音輸入";
            cancel.AccessibleName = "取消這次錄音或辨識";
            finish.AccessibleName = "開始或完成錄音";
            cancel.Click += (sender, args) => CancelRequested?.Invoke();
            finish.Click += (sender, args) =>
            {
                if (state == DictationState.Recording) FinishRequested?.Invoke();
                else if (state == DictationState.Idle || state == DictationState.RetainedAudio) StartRequested?.Invoke();
            };
            Controls.Add(cancel); Controls.Add(finish);
            tips.SetToolTip(cancel, "取消"); tips.SetToolTip(finish, "開始錄音");
            Resize += (sender, args) => LayoutHitAreas();
            LayoutHitAreas();
            UpdateState(DictationState.Idle, message);
        }

        public void ApplySettings(AppSettings settings)
        {
            if (settings == null) return;
            atTop = settings.HudAtTop;
            PlaceOnScreen();
        }

        public void UpdateState(DictationState value, string text)
        {
            if (IsDisposed) return;
            if (InvokeRequired) { BeginInvoke(new Action(() => UpdateState(value, text))); return; }
            state = value;
            message = String.IsNullOrWhiteSpace(text) ? StateLabel(value) : text;
            cancel.Enabled = value != DictationState.Idle && value != DictationState.Delivering;
            finish.Enabled = value == DictationState.Idle || value == DictationState.Recording || value == DictationState.RetainedAudio;
            tips.SetToolTip(finish, value == DictationState.Recording ? "完成錄音" : value == DictationState.RetainedAudio ? "重試辨識" : "開始錄音");
            if (value != DictationState.Recording) { level = 0; levelKnown = false; }
            AccessibleDescription = StateLabel(value) + "，" + message;
            Invalidate();
        }

        public void UpdateLevel(double decibels, bool isKnown)
        {
            if (IsDisposed) return;
            if (InvokeRequired) { BeginInvoke(new Action(() => UpdateLevel(decibels, isKnown))); return; }
            levelKnown = state == DictationState.Recording && isKnown && !Double.IsNaN(decibels) && !Double.IsInfinity(decibels);
            level = levelKnown ? Math.Max(0, Math.Min(1, (decibels + 60) / 60)) : 0;
            Invalidate();
        }

        protected override void OnShown(EventArgs args) { base.OnShown(args); PlaceOnScreen(); }
        private void PlaceOnScreen()
        {
            var area = Screen.FromPoint(Cursor.Position).WorkingArea;
            Location = new Point(area.Left + (area.Width - Width) / 2, atTop ? area.Top + 12 : area.Bottom - Height - 12);
        }
        private void LayoutHitAreas()
        {
            int catHeight = (int)(ClientSize.Width * .4978);
            cancel.Bounds = new Rectangle((int)(ClientSize.Width * .14), (int)(catHeight * .53), (int)(ClientSize.Width * .18), (int)(catHeight * .29));
            finish.Bounds = new Rectangle((int)(ClientSize.Width * .67), (int)(catHeight * .53), (int)(ClientSize.Width * .19), (int)(catHeight * .29));
        }
        protected override void OnPaint(PaintEventArgs args)
        {
            base.OnPaint(args);
            var graphics = args.Graphics;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            int catHeight = (int)(ClientSize.Width * .4978);
            graphics.DrawImage(cat, new Rectangle(0, 0, ClientSize.Width, catHeight));
            var plate = new Rectangle(18, catHeight + 2, ClientSize.Width - 36, ClientSize.Height - catHeight - 4);
            using (var shape = Rounded(plate, 12))
            using (var background = new SolidBrush(Color.FromArgb(30, 31, 35))) graphics.FillPath(background, shape);
            var bounds = new Rectangle(plate.Left + 12, plate.Top + 7, plate.Width - 24, plate.Height - 11);
            TextRenderer.DrawText(graphics, message, Font, bounds, Color.FromArgb(241, 242, 245), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
            if (state == DictationState.Recording)
            {
                int meterWidth = (int)(ClientSize.Width * .30);
                var meter = new Rectangle((ClientSize.Width - meterWidth) / 2, (int)(catHeight * .82), meterWidth, Math.Max(4, (int)(ClientSize.Width / 68.0)));
                using (var brush = new SolidBrush(Color.FromArgb(61, 62, 68))) graphics.FillRectangle(brush, meter);
                if (levelKnown && level > 0)
                {
                    var filled = new Rectangle(meter.Left, meter.Top, Math.Max(1, (int)(meterWidth * level)), meter.Height);
                    using (var brush = new SolidBrush(Color.FromArgb(165, 193, 255))) graphics.FillRectangle(brush, filled);
                }
            }
        }

        private static string StateLabel(DictationState value)
        {
            switch (value)
            {
                case DictationState.Starting: return "正在開啟麥克風…";
                case DictationState.Recording: return "正在聽你說話…";
                case DictationState.Finalizing: return "正在整理錄音…";
                case DictationState.Transcribing: return "正在辨識…";
                case DictationState.Delivering: return "正在放入文字…";
                case DictationState.RetainedAudio: return "辨識未完成，可重試或取消";
                default: return "按快捷鍵開始說話";
            }
        }
        internal static GraphicsPath Rounded(Rectangle rectangle, int radius)
        {
            var path = new GraphicsPath(); int diameter = radius * 2;
            path.AddArc(rectangle.Left, rectangle.Top, diameter, diameter, 180, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Top, diameter, diameter, 270, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rectangle.Left, rectangle.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure(); return path;
        }
        protected override void Dispose(bool disposing)
        {
            if (disposing) { cat.Dispose(); tips.Dispose(); }
            base.Dispose(disposing);
        }
    }

    internal sealed class CatActionArea : Control
    {
        private bool hover;
        public CatActionArea()
        {
            SetStyle(ControlStyles.SupportsTransparentBackColor | ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            BackColor = Color.Transparent; Cursor = Cursors.Hand; TabStop = false;
            AccessibleRole = AccessibleRole.PushButton;
        }
        protected override void OnMouseEnter(EventArgs args) { hover = true; Invalidate(); base.OnMouseEnter(args); }
        protected override void OnMouseLeave(EventArgs args) { hover = false; Invalidate(); base.OnMouseLeave(args); }
        protected override void OnPaint(PaintEventArgs args)
        {
            base.OnPaint(args);
            if (!hover || !Enabled) return;
            args.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var pen = new Pen(Color.FromArgb(160, 190, 255), 2)) args.Graphics.DrawEllipse(pen, 2, 2, Width - 5, Height - 5);
        }
    }
}
