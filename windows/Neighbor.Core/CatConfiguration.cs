using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

namespace Neighbor.Core
{
    /// <summary>A bounded, local-only, versioned description of the cat greeting.</summary>
    public sealed class CatConfiguration
    {
        public const int MaximumFileBytes = 16 * 1024;
        private static readonly HashSet<string> KnownFields = new HashSet<string>(StringComparer.Ordinal)
        {
            "version", "image", "triggers", "reply", "fontFamily", "fontSize", "bold",
            "bubblePosition", "tiltDegrees", "cooldownSeconds", "displaySeconds", "animateMouth"
        };
        private HashSet<string> normalizedTriggers;

        public static CatConfiguration Defaults { get; } = CreateDefaults();
        public int Version { get; private set; }
        public string Image { get; private set; }
        public string ResolvedImagePath { get; private set; }
        public IReadOnlyList<string> Triggers { get; private set; }
        public string Reply { get; private set; }
        public string FontFamily { get; private set; }
        public double FontSize { get; private set; }
        public bool Bold { get; private set; }
        public string BubblePosition { get; private set; }
        public double TiltDegrees { get; private set; }
        public double CooldownSeconds { get; private set; }
        public double DisplaySeconds { get; private set; }
        public bool AnimateMouth { get; private set; }
        public string LoadError { get; private set; }

        private CatConfiguration() { }

        private static CatConfiguration CreateDefaults()
        {
            var result = new CatConfiguration
            {
                Version = 1, Reply = "what's up!", FontFamily = "Comic Sans MS", FontSize = 18,
                Bold = true, BubblePosition = "upperRight", TiltDegrees = -10,
                CooldownSeconds = 5, DisplaySeconds = 3, AnimateMouth = true
            };
            result.SetTriggers(new[] { "what's up", "whats up", "what is up" });
            return result;
        }

        /// <summary>Missing files use defaults. Invalid files are preserved and fall back as a whole.</summary>
        public static CatConfiguration Load(string path)
        {
            if (String.IsNullOrWhiteSpace(path)) return Defaults;
            try
            {
                string json = ReadBoundedUtf8(path);
                var serializer = new JavaScriptSerializer { MaxJsonLength = MaximumFileBytes, RecursionLimit = 8 };
                var document = serializer.DeserializeObject(json) as Dictionary<string, object>;
                if (document == null) throw new InvalidDataException();
                foreach (string field in document.Keys)
                    if (!KnownFields.Contains(field)) throw new InvalidDataException();

                var result = CreateDefaults();
                object value;
                if (document.TryGetValue("version", out value))
                {
                    if (!(value is int) || (int)value != 1) throw new InvalidDataException();
                }
                if (document.TryGetValue("image", out value) && value != null)
                {
                    result.Image = ReadText(value, 200);
                    result.ResolvedImagePath = ResolveImagePath(path, result.Image);
                }
                if (document.TryGetValue("triggers", out value))
                {
                    var list = value as IList;
                    if (list == null || list.Count < 1 || list.Count > 32) throw new InvalidDataException();
                    var triggers = new List<string>();
                    foreach (object trigger in list) triggers.Add(ReadText(trigger, 80));
                    result.SetTriggers(triggers);
                }
                if (document.TryGetValue("reply", out value)) result.Reply = ReadText(value, 80);
                if (document.TryGetValue("fontFamily", out value)) result.FontFamily = ReadText(value, 80);
                if (document.TryGetValue("fontSize", out value)) result.FontSize = ReadNumber(value, 12, 28);
                if (document.TryGetValue("bold", out value))
                {
                    if (!(value is bool)) throw new InvalidDataException();
                    result.Bold = (bool)value;
                }
                if (document.TryGetValue("bubblePosition", out value))
                {
                    result.BubblePosition = value as string;
                    if (result.BubblePosition != "upperRight" && result.BubblePosition != "upperLeft") throw new InvalidDataException();
                }
                if (document.TryGetValue("tiltDegrees", out value)) result.TiltDegrees = ReadNumber(value, -15, 15);
                if (document.TryGetValue("cooldownSeconds", out value)) result.CooldownSeconds = ReadNumber(value, 1, 60);
                if (document.TryGetValue("displaySeconds", out value)) result.DisplaySeconds = ReadNumber(value, 1, 10);
                if (document.TryGetValue("animateMouth", out value))
                {
                    if (!(value is bool)) throw new InvalidDataException();
                    result.AnimateMouth = (bool)value;
                }
                return result;
            }
            catch (FileNotFoundException) { return Defaults; }
            catch (DirectoryNotFoundException) { return Defaults; }
            catch
            {
                var fallback = CreateDefaults();
                fallback.LoadError = "貓咪設定檔無法讀取或格式無效；已保留原檔，本次使用預設貓咪設定。";
                return fallback;
            }
        }

        /// <summary>Matches the complete utterance; never searches for a phrase inside dictation.</summary>
        public bool Matches(string text)
        {
            return text != null && normalizedTriggers.Contains(NormalizePhrase(text));
        }

        private void SetTriggers(IEnumerable<string> values)
        {
            var copy = new List<string>(values);
            var normalized = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string phrase in copy)
            {
                string key = NormalizePhrase(phrase);
                if (key.Length == 0 || !normalized.Add(key)) throw new InvalidDataException();
            }
            Triggers = new ReadOnlyCollection<string>(copy);
            normalizedTriggers = normalized;
        }

        private static string NormalizePhrase(string value)
        {
            int first = 0, end = value.Length;
            while (first < end && IsSurrounding(value[first])) first++;
            while (end > first && IsSurrounding(value[end - 1])) end--;
            var normalized = new StringBuilder(end - first);
            bool whitespace = false;
            for (int i = first; i < end; i++)
            {
                char c = value[i];
                if (Char.IsWhiteSpace(c)) { whitespace = true; continue; }
                if (whitespace && normalized.Length != 0) normalized.Append(' ');
                whitespace = false;
                normalized.Append(c == '\u2019' || c == '\u2018' || c == '\u02bc' || c == '\uff07' ? '\'' : c);
            }
            return normalized.ToString();
        }

        private static bool IsSurrounding(char c) { return Char.IsWhiteSpace(c) || Char.IsPunctuation(c); }

        private static string ReadText(object value, int maximumCharacters)
        {
            var text = value as string;
            if (String.IsNullOrWhiteSpace(text) || UnicodeText.Count(text) > maximumCharacters) throw new InvalidDataException();
            for (int i = 0; i < text.Length; i++)
            {
                char c = text[i];
                if (Char.IsControl(c) || c == '\u2028' || c == '\u2029') throw new InvalidDataException();
                if (Char.IsHighSurrogate(c))
                {
                    if (i + 1 >= text.Length || !Char.IsLowSurrogate(text[++i])) throw new InvalidDataException();
                }
                else if (Char.IsLowSurrogate(c)) throw new InvalidDataException();
            }
            return text.Trim();
        }

        private static double ReadNumber(object value, double minimum, double maximum)
        {
            if (!(value is int) && !(value is long) && !(value is decimal) && !(value is double)) throw new InvalidDataException();
            double number = Convert.ToDouble(value, CultureInfo.InvariantCulture);
            if (Double.IsNaN(number) || Double.IsInfinity(number) || number < minimum || number > maximum) throw new InvalidDataException();
            return number;
        }

        private static string ResolveImagePath(string configPath, string image)
        {
            // Check Windows filename rules explicitly, including when tests run on another OS.
            if (image.IndexOfAny(new[] { '<', '>', ':', '"', '/', '\\', '|', '?', '*' }) >= 0 ||
                image == "." || image == ".." || image.EndsWith(".", StringComparison.Ordinal) ||
                image.EndsWith(" ", StringComparison.Ordinal) || Path.IsPathRooted(image)) throw new InvalidDataException();
            string extension = Path.GetExtension(image);
            if (!String.Equals(extension, ".png", StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException();
            string stem = image.Split('.')[0].TrimEnd(' ').ToUpperInvariant();
            if (stem == "CON" || stem == "PRN" || stem == "AUX" || stem == "NUL" ||
                (stem.Length == 4 && (stem.StartsWith("COM", StringComparison.Ordinal) || stem.StartsWith("LPT", StringComparison.Ordinal)) && stem[3] >= '1' && stem[3] <= '9'))
                throw new InvalidDataException();
            string directory = Path.GetDirectoryName(Path.GetFullPath(configPath));
            string resolved = Path.GetFullPath(Path.Combine(directory, image));
            if (!String.Equals(Path.GetDirectoryName(resolved), directory, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException();
            if (File.Exists(resolved) && (File.GetAttributes(resolved) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException();
            return resolved;
        }

        private static string ReadBoundedUtf8(string path)
        {
            var bytes = new byte[MaximumFileBytes + 1];
            int length = 0;
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                if (stream.Length > MaximumFileBytes) throw new InvalidDataException();
                int count;
                while (length < bytes.Length && (count = stream.Read(bytes, length, bytes.Length - length)) > 0) length += count;
            }
            if (length > MaximumFileBytes) throw new InvalidDataException();
            string text = new UTF8Encoding(false, true).GetString(bytes, 0, length);
            return text.Length > 0 && text[0] == '\ufeff' ? text.Substring(1) : text;
        }
    }
}
