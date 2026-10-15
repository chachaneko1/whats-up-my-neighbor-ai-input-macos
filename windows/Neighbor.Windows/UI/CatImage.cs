using System;
using System.Drawing;
using System.IO;
using Neighbor.Core;

namespace Neighbor.Windows.UI
{
    public static class CatImage
    {
        public static Image Load(CatConfiguration configuration)
        {
            string path = configuration?.ResolvedImagePath;
            if (String.IsNullOrEmpty(path)) return Theme.LoadCatImage();
            try
            {
                var info = new FileInfo(path);
                if (!info.Exists || info.Length < 33 || info.Length > 4 * 1024 * 1024 || (info.Attributes & FileAttributes.ReparsePoint) != 0)
                    return Theme.LoadCatImage();
                // Read a bounded immutable snapshot, validate dimensions before GDI+
                // can allocate pixel storage, and never retain the file handle.
                byte[] data;
                using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                {
                    if (stream.Length < 33 || stream.Length > 4 * 1024 * 1024) return Theme.LoadCatImage();
                    data = new byte[(int)stream.Length];
                    int read = 0, count;
                    while (read < data.Length && (count = stream.Read(data, read, data.Length - read)) > 0) read += count;
                    if (read != data.Length) return Theme.LoadCatImage();
                }
                byte[] signature = { 137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82 };
                for (int i = 0; i < signature.Length; i++) if (data[i] != signature[i]) return Theme.LoadCatImage();
                uint width = ReadBigEndian(data, 16), height = ReadBigEndian(data, 20);
                if (width == 0 || height == 0 || width > 2048 || height > 2048) return Theme.LoadCatImage();
                using (var stream = new MemoryStream(data, false))
                using (var decoded = Image.FromStream(stream, false, true))
                {
                    if (decoded.Width != width || decoded.Height != height) return Theme.LoadCatImage();
                    return new Bitmap(decoded);
                }
            }
            catch (Exception error) when (error is IOException || error is UnauthorizedAccessException || error is ArgumentException || error is System.Runtime.InteropServices.ExternalException || error is OutOfMemoryException)
            { return Theme.LoadCatImage(); }
        }
        private static uint ReadBigEndian(byte[] data, int offset)
        { return ((uint)data[offset] << 24) | ((uint)data[offset + 1] << 16) | ((uint)data[offset + 2] << 8) | data[offset + 3]; }
    }
}
