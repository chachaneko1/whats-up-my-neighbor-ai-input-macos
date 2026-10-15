using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;
using Neighbor.Core;

namespace Neighbor.Tests
{
    public static class CatConfigurationTests
    {
        public static void Run(Action<bool, string> check)
        {
            string directory = Path.Combine(Path.GetTempPath(), "Neighbor.CatConfiguration." + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            string path = Path.Combine(directory, "cat.config.json");
            try
            {
                var missing = CatConfiguration.Load(path);
                check(IsDefault(missing) && missing.LoadError == null, "Missing cat config uses defaults without an error");
                check(IsDefault(CatConfiguration.Load(Path.Combine(directory, "missing", "cat.config.json"))), "Missing cat config directory uses defaults");
                File.WriteAllText(path, "{}", new UTF8Encoding(false));
                check(IsDefault(CatConfiguration.Load(path)) && CatConfiguration.Load(path).LoadError == null, "Omitted cat fields use stable version one defaults");

                string customJson = "{\"version\":1,\"image\":\"my-cat.PNG\",\"triggers\":[\"Hello cat!\",\"貓咪你好\",\"what’s new\"],\"reply\":\"喵，今天也加油！\",\"fontFamily\":\"Segoe UI\",\"fontSize\":22.5,\"bold\":false,\"bubblePosition\":\"upperLeft\",\"tiltDegrees\":7.5,\"cooldownSeconds\":8.5,\"displaySeconds\":4.5}";
                File.WriteAllText(path, customJson, new UTF8Encoding(true));
                var custom = CatConfiguration.Load(path);
                check(custom.LoadError == null && custom.Version == 1 && custom.Image == "my-cat.PNG" && custom.ResolvedImagePath == Path.Combine(directory, "my-cat.PNG"), "Custom config accepts a same-directory PNG filename and UTF-8 BOM");
                check(custom.Triggers.Count == 3 && custom.Reply == "喵，今天也加油！" && custom.FontFamily == "Segoe UI" && custom.FontSize == 22.5 && !custom.Bold, "Cat text and font settings load with exact types");
                check(custom.BubblePosition == "upperLeft" && custom.TiltDegrees == 7.5 && custom.CooldownSeconds == 8.5 && custom.DisplaySeconds == 4.5, "Cat position, tilt, and duration settings load");
                check(custom.AnimateMouth, "Legacy version one config without animateMouth keeps the true default");
                check(custom.Matches(" “HELLO\t CAT?” ") && custom.Matches("貓咪你好。") && custom.Matches("what's new") && custom.Matches("WHAT＇S NEW?!"), "Custom trigger normalization handles case, whitespace, apostrophes and surrounding punctuation");
                check(!custom.Matches("please hello cat") && !custom.Matches("hello cat tomorrow") && !custom.Matches("hello-cat") && !custom.Matches("hello cat🙂") && !custom.Matches("what's up"), "Custom triggers are exact and replace the default trigger set");
                check(!custom.Matches(null) && !custom.Matches("") && !custom.Matches("?!"), "Null and empty utterances do not trigger the cat");
                var exposed = custom.Triggers as IList<string>; bool immutable = false;
                try { exposed[0] = "mutated"; } catch (NotSupportedException) { immutable = true; }
                check(immutable && custom.Matches("hello cat") && !custom.Matches("mutated"), "Caller cannot mutate the cat trigger snapshot");
                check(IsDefault(CatConfiguration.Defaults), "Loading customized values cannot mutate shared cat defaults");

                File.WriteAllText(path, "{\"animateMouth\":false}");
                var reducedMotion = CatConfiguration.Load(path);
                check(reducedMotion.LoadError == null && !reducedMotion.AnimateMouth && reducedMotion.Image == null && reducedMotion.Reply == "what's up!", "Explicit false opts out of mouth animation while preserving greeting defaults");
                File.WriteAllText(path, "{\"animateMouth\":true}");
                check(IsDefault(CatConfiguration.Load(path)) && CatConfiguration.Load(path).LoadError == null, "Explicit true enables default built-in cat mouth animation");
                foreach (bool animate in new[] { true, false })
                {
                    File.WriteAllText(path, "{\"image\":\"missing-cat.png\",\"animateMouth\":" + (animate ? "true" : "false") + "}");
                    var artwork = CatConfiguration.Load(path);
                    check(artwork.LoadError == null && artwork.AnimateMouth == animate && artwork.Image == "missing-cat.png" && artwork.ResolvedImagePath == Path.Combine(directory, "missing-cat.png"),
                        "Custom image selection remains explicit so the HUD can suppress mouth overlays even when the image is missing: " + animate);
                }

                foreach (string utterance in new[] { "what's up", "whats up", "what is up", " WHAT’S UP?! ", "“What's up?”", "WHAT‘S UP", "whatʼs up", "what＇s up", "what\tis\nup", "what's up。" })
                    check(CatConfiguration.Defaults.Matches(utterance), "Default config accepts approved greeting: " + utterance);
                foreach (string utterance in new[] { null, "", "?!", "translate what's up", "what's up my neighbor", "say whats up", "what is up today", "whatsup", "what-s up", "w.h.a.t.s up", "what's up 2", "what's up🙂", "what's up what's up" })
                    check(!CatConfiguration.Defaults.Matches(utterance), "Default config rejects ordinary dictation: " + utterance);

                foreach (string invalid in new[] {
                    "", "{broken", "null", "[]", "true", "42", "\"text\"", "{\"version\":2}", "{\"version\":\"1\"}", "{\"version\":null}",
                    "{\"reply\":\"custom\",\"fontSize\":11}", "{\"fontSize\":29}", "{\"fontSize\":\"18\"}", "{\"fontSize\":null}", "{\"fontSize\":true}",
                    "{\"bold\":1}", "{\"bold\":\"true\"}", "{\"bold\":null}", "{\"bubblePosition\":\"center\"}", "{\"bubblePosition\":null}",
                    "{\"animateMouth\":1}", "{\"animateMouth\":0}", "{\"animateMouth\":\"true\"}", "{\"animateMouth\":\"false\"}",
                    "{\"animateMouth\":null}", "{\"animateMouth\":[]}", "{\"animateMouth\":{}}", "{\"reply\":\"custom\",\"animateMouth\":\"false\"}",
                    "{\"tiltDegrees\":-15.1}", "{\"tiltDegrees\":15.1}", "{\"cooldownSeconds\":0}", "{\"cooldownSeconds\":61}",
                    "{\"displaySeconds\":0}", "{\"displaySeconds\":11}", "{\"reply\":null}", "{\"reply\":\"\"}", "{\"reply\":\"   \"}",
                    "{\"reply\":\"two\\nlines\"}", "{\"reply\":[\"text\"]}", "{\"fontFamily\":false}", "{\"fontFamily\":\"\"}",
                    "{\"triggers\":null}", "{\"triggers\":[]}", "{\"triggers\":\"hello\"}", "{\"triggers\":{\"text\":\"hello\"}}", "{\"triggers\":[1]}",
                    "{\"triggers\":[null]}", "{\"triggers\":[\" \" ]}", "{\"triggers\":[\"?!\"]}", "{\"triggers\":[\"two\\nlines\"]}",
                    "{\"triggers\":[\"HELLO!\",\"hello\"]}", "{\"triggers\":[\"what’s up\",\"what's up\"]}",
                    "{\"image\":false}", "{\"image\":\"\"}", "{\"command\":\"run.exe\"}", "{\"Reply\":\"wrong casing\"}"
                })
                    Reject(check, path, invalid, "Invalid cat JSON/schema falls back as a whole");

                var serializer = new JavaScriptSerializer();
                foreach (string image in new[] { "../cat.png", "..\\cat.png", "/cat.png", "\\cat.png", "C:\\cat.png", "C:cat.png", "\\\\server\\cat.png", "https://example.test/cat.png", "file:///cat.png", "folder/cat.png", "folder\\cat.png", "cat.jpg", "cat.jpeg", "cat.gif", "cat.svg", "cat.exe", "cat.png:payload", "cat?.png", "cat*.png", "CON.png", "NUL.png", "LPT1.png", "COM9.png", "cat.png." })
                    Reject(check, path, serializer.Serialize(new { image }), "Unsafe or unsupported cat image rejected: " + image);

                foreach (string key in new[] { "reply", "fontFamily" })
                    Reject(check, path, serializer.Serialize(new Dictionary<string, object> { { key, new string('a', 81) } }), "Overlong " + key + " rejected");
                Reject(check, path, serializer.Serialize(new { triggers = new[] { new string('a', 81) } }), "Overlong cat trigger rejected");
                Reject(check, path, serializer.Serialize(new { triggers = Enumerable.Range(0, 33).Select(i => "hello " + i).ToArray() }), "More than 32 cat triggers rejected");

                File.WriteAllText(path, serializer.Serialize(new { triggers = Enumerable.Range(0, 32).Select(i => "hello " + i).ToArray(), reply = new string('a', 80), fontFamily = new string('a', 80), fontSize = 12, tiltDegrees = -15, cooldownSeconds = 1, displaySeconds = 1 }));
                var lower = CatConfiguration.Load(path);
                check(lower.LoadError == null && lower.Triggers.Count == 32 && lower.Reply.Length == 80 && lower.FontSize == 12 && lower.TiltDegrees == -15 && lower.CooldownSeconds == 1 && lower.DisplaySeconds == 1, "Cat configuration lower limits and maximum text/list sizes are accepted");
                File.WriteAllText(path, "{\"fontSize\":28,\"tiltDegrees\":15,\"cooldownSeconds\":60,\"displaySeconds\":10,\"image\":null}");
                var upper = CatConfiguration.Load(path);
                check(upper.LoadError == null && upper.FontSize == 28 && upper.TiltDegrees == 15 && upper.CooldownSeconds == 60 && upper.DisplaySeconds == 10 && upper.ResolvedImagePath == null, "Cat configuration upper limits and explicit built-in image are accepted");

                string emoji80 = String.Concat(Enumerable.Repeat("🐱", 80));
                File.WriteAllText(path, serializer.Serialize(new { reply = emoji80 }));
                check(CatConfiguration.Load(path).LoadError == null && CatConfiguration.Load(path).Reply == emoji80, "Cat reply length counts Unicode scalars");
                Reject(check, path, serializer.Serialize(new { reply = emoji80 + "🐱" }), "Eighty-one Unicode scalar reply rejected");

                File.WriteAllText(path, "{}" + new string(' ', CatConfiguration.MaximumFileBytes - 2), new UTF8Encoding(false));
                check(CatConfiguration.Load(path).LoadError == null, "Exactly 16 KiB cat config is accepted");
                Reject(check, path, "{}" + new string(' ', CatConfiguration.MaximumFileBytes - 1), "Cat config beyond 16 KiB rejected without partial loading");
                File.WriteAllBytes(path, new byte[] { 0xff, 0xfe, 0x7b, 0x00, 0x7d, 0x00 });
                check(IsDefault(CatConfiguration.Load(path)) && CatConfiguration.Load(path).LoadError != null, "Cat config requires valid UTF-8");
                check(IsDefault(CatConfiguration.Load(directory)) && CatConfiguration.Load(directory).LoadError != null, "Unreadable cat config falls back without crashing");
            }
            finally { Directory.Delete(directory, true); }
        }

        private static void Reject(Action<bool, string> check, string path, string json, string name)
        {
            File.WriteAllText(path, json, new UTF8Encoding(false));
            var config = CatConfiguration.Load(path);
            check(config.LoadError != null && IsDefault(config) && File.ReadAllText(path) == json, name + ": " + json.Substring(0, Math.Min(80, json.Length)));
        }

        private static bool IsDefault(CatConfiguration config)
        {
            return config.Version == 1 && config.Image == null && config.ResolvedImagePath == null &&
                config.Triggers.SequenceEqual(new[] { "what's up", "whats up", "what is up" }) &&
                config.Reply == "what's up!" && config.FontFamily == "Comic Sans MS" && config.FontSize == 18 &&
                config.Bold && config.BubblePosition == "upperRight" && config.TiltDegrees == -10 &&
                config.CooldownSeconds == 5 && config.DisplaySeconds == 3 && config.AnimateMouth;
        }
    }
}
