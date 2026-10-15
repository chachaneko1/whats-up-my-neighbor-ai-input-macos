using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using Neighbor.Core;

namespace Neighbor.Windows.UI
{
    public sealed class RecordingHud : NonActivatingForm
    {
        private readonly Image cat;
        private readonly Image greetingCat;
        private readonly Timer mouthTimer = new Timer { Interval = 100 };
        private readonly System.Diagnostics.Stopwatch mouthClock = new System.Diagnostics.Stopwatch();
        private int mouthFrame;
        private bool mouthFinished;
        public bool IsMouthAnimating { get { return mouthTimer.Enabled; } }
        private readonly CatConfiguration configuration;
        private readonly CatActionArea cancel = new CatActionArea(), finish = new CatActionArea();
        private readonly ToolTip tips = new ToolTip();
        private readonly Font greetingFont;
        private DictationState state;
        private string message = "按快捷鍵開始說話";
        private double level;
        private bool levelKnown, atTop, greeting;
        private Point normalLocation;
        public event Action StartRequested;
        public event Action FinishRequested;
        public event Action CancelRequested;

        public RecordingHud(CatConfiguration configuration = null)
        {
            this.configuration = configuration ?? CatConfiguration.Defaults;
            cat = CatImage.Load(this.configuration);
            if (this.configuration.AnimateMouth && String.IsNullOrEmpty(this.configuration.Image))
                greetingCat = CatMouthAnimation.WithoutNeutralMouth(cat);
            mouthTimer.Tick += (_, e) =>
            {
                if (!Visible || !greeting || IsDisposed || mouthClock.Elapsed.TotalSeconds >= this.configuration.DisplaySeconds)
                { StopMouthAnimation(); return; }
                mouthFrame = (int)(mouthClock.ElapsedMilliseconds / 100);
                Invalidate(CatBounds);
            };
            greetingFont = CreateGreetingFont(this.configuration);
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

        public void UpdateState(DictationState value, string text, bool isGreeting = false)
        {
            if (IsDisposed) return;
            if (InvokeRequired) { BeginInvoke(new Action(() => UpdateState(value, text, isGreeting))); return; }
            state = value;
            bool nextGreeting = isGreeting && value == DictationState.Idle;
            if (greeting != nextGreeting)
            {
                // Keep the cat and its eye targets in place while reserving room
                // above/right for the reply. All geometry scales with the canvas.
                var oldCat = CatBounds;
                if (nextGreeting) normalLocation = Location;
                float scale = ClientSize.Width / (greeting ? 440F : 340F);
                greeting = nextGreeting;
                mouthFinished = false;
                ClientSize = new Size((int)Math.Round((greeting ? 440 : 340) * scale), (int)Math.Round((greeting ? 260 : 220) * scale));
                var newCat = CatBounds;
                Location = greeting ? new Point(Left + oldCat.Left - newCat.Left, Top + oldCat.Top - newCat.Top) : normalLocation;
                LayoutHitAreas();
                if (Visible) ClampToScreen();
            }
            message = String.IsNullOrWhiteSpace(text) ? StateLabel(value) : text;
            cancel.Enabled = value != DictationState.Idle && value != DictationState.Delivering;
            finish.Enabled = value == DictationState.Idle || value == DictationState.Recording || value == DictationState.RetainedAudio;
            tips.SetToolTip(finish, value == DictationState.Recording ? "完成錄音" : value == DictationState.RetainedAudio ? "重試辨識" : "開始錄音");
            if (value != DictationState.Recording) { level = 0; levelKnown = false; }
            AccessibleDescription = StateLabel(value) + "，" + message;
            if (greeting) StartMouthAnimation(); else StopMouthAnimation();
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

        private void StartMouthAnimation()
        {
            if (!Visible || !greeting || greetingCat == null || mouthFinished || mouthTimer.Enabled) return;
            mouthFrame = 0; mouthClock.Restart(); mouthTimer.Start();
        }
        private void StopMouthAnimation()
        {
            mouthTimer.Stop(); mouthClock.Stop(); mouthFrame = 0; mouthFinished = true;
            if (!IsDisposed) Invalidate();
        }
        protected override void OnVisibleChanged(EventArgs args)
        {
            base.OnVisibleChanged(args);
            if (Visible) StartMouthAnimation(); else StopMouthAnimation();
        }

        protected override void OnShown(EventArgs args) { base.OnShown(args); PlaceOnScreen(); }
        private void PlaceOnScreen()
        {
            var area = Screen.FromPoint(Cursor.Position).WorkingArea;
            Location = new Point(area.Left + (area.Width - Width) / 2, atTop ? area.Top + 12 : area.Bottom - Height - 12);
            float scale = ClientSize.Width / (greeting ? 440F : 340F);
            normalLocation = new Point(area.Left + (area.Width - (int)Math.Round(340 * scale)) / 2,
                atTop ? area.Top + 12 : area.Bottom - (int)Math.Round(220 * scale) - 12);
        }
        private Rectangle CatBounds
        {
            get
            {
                float scale = ClientSize.Width / (greeting ? 440F : 340F);
                return new Rectangle(greeting && configuration.BubblePosition == "upperLeft" ? (int)(100 * scale) : 0, greeting ? (int)(80 * scale) : 0, (int)(340 * scale), (int)(340 * .4978 * scale));
            }
        }
        private void ClampToScreen()
        {
            var area = Screen.FromControl(this).WorkingArea;
            Location = new Point(Math.Max(area.Left, Math.Min(Left, area.Right - Width)), Math.Max(area.Top, Math.Min(Top, area.Bottom - Height)));
        }
        private void LayoutHitAreas()
        {
            var bounds = CatBounds;
            cancel.Bounds = new Rectangle(bounds.Left + (int)(bounds.Width * .14), bounds.Top + (int)(bounds.Height * .53), (int)(bounds.Width * .18), (int)(bounds.Height * .29));
            finish.Bounds = new Rectangle(bounds.Left + (int)(bounds.Width * .67), bounds.Top + (int)(bounds.Height * .53), (int)(bounds.Width * .19), (int)(bounds.Height * .29));
        }
        private static Font CreateGreetingFont(CatConfiguration configuration)
        {
            foreach (string name in new[] { configuration.FontFamily, "Comic Sans MS", "Segoe UI", "Arial" })
            {
                try
                {
                    using (var family = new FontFamily(name))
                        if (family.IsStyleAvailable(configuration.Bold ? FontStyle.Bold : FontStyle.Regular)) return new Font(family, (float)configuration.FontSize, configuration.Bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Pixel);
                }
                catch (ArgumentException) { }
            }
            return new Font(FontFamily.GenericSansSerif, (float)configuration.FontSize, configuration.Bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Pixel);
        }
        private void PaintGreeting(Graphics graphics)
        {
            var saved = graphics.Save();
            try
            {
                float scale = ClientSize.Width / 440F;
                graphics.ScaleTransform(scale, scale);
                bool left = configuration.BubblePosition == "upperLeft";
                graphics.TranslateTransform(left ? 120 : 320, 54);
                graphics.RotateTransform((float)configuration.TiltDegrees);
                var bubble = new Rectangle(-90, -28, 180, 56);
                using (var shape = Rounded(bubble, 18))
                using (var background = new SolidBrush(Color.FromArgb(51, 65, 87)))
                using (var ink = new SolidBrush(Color.FromArgb(241, 242, 245)))
                using (var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                {
                    graphics.FillPath(background, shape);
                    int direction = left ? -1 : 1;
                    graphics.FillPolygon(background, new[] { new Point(direction * -66, 25), new Point(direction * -72, 43), new Point(direction * -42, 25) });
                    graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                    var textBounds = new RectangleF(-80, -23, 160, 46);
                    format.Trimming = StringTrimming.EllipsisCharacter;
                    float size = greetingFont.Size;
                    while (size > 10)
                    {
                        using (var candidate = new Font(greetingFont.FontFamily, size, greetingFont.Style, GraphicsUnit.Pixel))
                            if (graphics.MeasureString(message, candidate, (int)textBounds.Width, format).Height <= textBounds.Height) break;
                        size -= 1;
                    }
                    using (var fitted = new Font(greetingFont.FontFamily, size, greetingFont.Style, GraphicsUnit.Pixel))
                        graphics.DrawString(message, fitted, ink, textBounds, format);
                }
            }
            finally { graphics.Restore(saved); }
        }
        protected override void OnPaint(PaintEventArgs args)
        {
            base.OnPaint(args);
            var graphics = args.Graphics;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            var catBounds = CatBounds;
            int catHeight = catBounds.Height;
            bool animateMouth = greeting && greetingCat != null && !mouthFinished;
            graphics.DrawImage(animateMouth ? greetingCat : cat, catBounds);
            if (animateMouth) CatMouthAnimation.Paint(graphics, catBounds, mouthFrame);
            if (greeting) { PaintGreeting(graphics); return; }
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
            if (disposing) { mouthTimer.Stop(); mouthTimer.Dispose(); mouthClock.Stop(); greetingCat?.Dispose(); cat.Dispose(); tips.Dispose(); greetingFont.Dispose(); }
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
