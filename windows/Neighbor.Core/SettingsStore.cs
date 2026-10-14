using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;

namespace Neighbor.Core
{
    public sealed class SettingsStore
    {
        private readonly string path;
        public string LoadError { get; private set; }
        public SettingsStore(string path) { this.path = path; }
        public AppSettings Load()
        {
            if (!File.Exists(path)) return new AppSettings();
            try
            {
                if (new FileInfo(path).Length > 1024 * 1024) throw new InvalidDataException();
                var settings = new JavaScriptSerializer().Deserialize<AppSettings>(File.ReadAllText(path, Encoding.UTF8));
                Validate(settings);
                return settings;
            }
            catch { LoadError = "設定檔無法讀取，已保留原檔；本次使用預設設定。請備份並移走損壞的設定檔後再儲存。"; return new AppSettings(); }
        }
        public void Save(AppSettings settings)
        {
            if (LoadError != null) throw new InvalidOperationException(LoadError);
            Validate(settings);
            AtomicFile.Write(path, new JavaScriptSerializer().Serialize(settings));
        }
        public static void Validate(AppSettings s)
        {
            if (s == null || !LanguagePolicy.IsSupported(s.PrimaryLanguage)) throw new ArgumentException("請選擇支援的主要語言。");
            if (s.AdditionalLanguages == null || s.AdditionalLanguages.Count > 2 || s.AdditionalLanguages.Any(x => !LanguagePolicy.IsSupported(x)) || s.AdditionalLanguages.Distinct().Count() != s.AdditionalLanguages.Count || s.AdditionalLanguages.Contains(s.PrimaryLanguage)) throw new ArgumentException("最多選擇兩種不同的混用語言，且不得重複主要語言。");
            if (!Enum.IsDefined(typeof(OutputMode), s.Mode) || !Enum.IsDefined(typeof(OutputMode), s.AlternateMode)) throw new ArgumentException("文字模式無效。");
            if (s.SilenceSeconds != 0 && s.SilenceSeconds != 3 && s.SilenceSeconds != 5 && s.SilenceSeconds != 10) throw new ArgumentException("靜音停止秒數無效。");
            ValidateShortcut(s.PrimaryShortcut);
            if (s.AlternateShortcut != null)
            {
                ValidateShortcut(s.AlternateShortcut);
                if (s.AlternateShortcut.Key == s.PrimaryShortcut.Key && s.AlternateShortcut.Modifiers == s.PrimaryShortcut.Modifiers) throw new ArgumentException("兩個快捷鍵不能相同。");
            }
        }
        private static void ValidateShortcut(Shortcut s)
        {
            if (s == null || (s.Modifiers & 11) == 0 || (s.Modifiers & ~15) != 0 || s.Key < 1 || s.Key > 254 || s.Key == 16 || s.Key == 17 || s.Key == 18 || s.Key == 91 || s.Key == 92 || s.Key == 123) throw new ArgumentException("請使用含修飾鍵的有效組合；F12 保留給系統。");
        }
    }
    public static class AtomicFile
    {
        public static void Write(string path, string contents)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)));
            string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                File.WriteAllText(temp, contents, new UTF8Encoding(false));
                if (File.Exists(path)) File.Replace(temp, path, null); else File.Move(temp, path);
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
    }
    public sealed class TemporaryAudioStore
    {
        public string DirectoryPath { get; }
        public TemporaryAudioStore(string directory) { DirectoryPath = Path.GetFullPath(directory); Directory.CreateDirectory(DirectoryPath); }
        public string CreatePath() { return Path.Combine(DirectoryPath, "dictation-" + Guid.NewGuid().ToString("N") + ".wav"); }
        public bool IsUsable(string path) { return File.Exists(path) && new FileInfo(path).Length > 44 && new FileInfo(path).Length <= 20000000; }
        public void Remove(string path)
        {
            if (string.IsNullOrEmpty(path)) return;
            if (!string.Equals(Path.GetDirectoryName(Path.GetFullPath(path)), DirectoryPath, StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("錄音路徑不屬於本 App。");
            try { File.Delete(path); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
        public void Cleanup()
        {
            foreach (var file in Directory.GetFiles(DirectoryPath, "dictation-*.wav")) Remove(file);
        }
    }
}
