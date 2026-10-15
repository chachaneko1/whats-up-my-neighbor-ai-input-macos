using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace Neighbor.Windows.UI
{
    /// <summary>Greeting-only feline mouth; the packaged neutral cat stays unchanged.</summary>
    internal static class CatMouthAnimation
    {
        public static Bitmap WithoutNeutralMouth(Image original)
        {
            var result = new Bitmap(original);
            int left = (int)(result.Width * .448), right = (int)(result.Width * .552);
            int top = (int)(result.Height * .755), bottom = (int)(result.Height * .84);
            // Reconstruct only the tiny neutral-mouth patch from the same cat's
            // neighboring dark pixels. No custom artwork is passed to this helper.
            for (int x = left; x <= right; x++)
            {
                Color upper = result.GetPixel(x, top), lower = result.GetPixel(x, bottom);
                for (int y = top + 1; y < bottom; y++)
                {
                    double ratio = (double)(y - top) / (bottom - top);
                    result.SetPixel(x, y, Color.FromArgb(255,
                        (int)(upper.R + (lower.R - upper.R) * ratio),
                        (int)(upper.G + (lower.G - upper.G) * ratio),
                        (int)(upper.B + (lower.B - upper.B) * ratio)));
                }
            }
            return result;
        }

        public static void Paint(Graphics graphics, Rectangle cat, int frame)
        {
            var saved = graphics.Save();
            try
            {
                float scale = cat.Width / 340F;
                graphics.TranslateTransform(cat.Left + cat.Width * .5F, cat.Top + cat.Height * .798F);
                graphics.ScaleTransform(scale, scale);
                // Short, irregular syllables rather than a human jaw or lip shape.
                float[] openings = { 0, 3, 7, 4, 0, 0, 5, 7, 2, 0, 4, 0 };
                float opening = openings[frame % openings.Length];
                using (var white = new Pen(Color.FromArgb(247, 247, 249), 2.6F) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
                {
                    if (opening > 0)
                    {
                        using (var openingShape = new GraphicsPath())
                        using (var dark = new SolidBrush(Color.FromArgb(24, 23, 29)))
                        using (var tongue = new SolidBrush(Color.FromArgb(233, 151, 172)))
                        using (var outline = new Pen(Color.FromArgb(247, 247, 249), 1.5F))
                        {
                            openingShape.AddBezier(-5, 1, -5, opening + 4, 5, opening + 4, 5, 1);
                            openingShape.CloseFigure();
                            graphics.FillPath(dark, openingShape);
                            var clip = graphics.Save();
                            graphics.SetClip(openingShape, CombineMode.Intersect);
                            graphics.FillEllipse(tongue, -3.5F, opening, 7, 4);
                            graphics.Restore(clip);
                            graphics.DrawPath(outline, openingShape);
                        }
                    }
                    using (var muzzle = new GraphicsPath())
                    {
                        muzzle.AddBezier(-11, -2, -10, 4, -3, 4, 0, -1);
                        muzzle.AddBezier(0, -1, 3, 4, 10, 4, 11, -2);
                        graphics.DrawPath(white, muzzle);
                    }
                }
            }
            finally { graphics.Restore(saved); }
        }
    }
}
