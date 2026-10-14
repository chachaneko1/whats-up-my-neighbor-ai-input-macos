using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Shortcut = Neighbor.Core.Shortcut;
using Neighbor.Core;
using Neighbor.Windows.Platform;

namespace Neighbor.Tests
{
    public static class PlatformTests
    {
        private sealed class FakeRegistrar : IHotKeyRegistrar
        {
            public readonly Dictionary<int, Shortcut> Registered = new Dictionary<int, Shortcut>();
            public int RejectKey;
            public event Action<int> Pressed;
            public bool Register(int id, int modifiers, int key)
            {
                if (key == RejectKey || Registered.Values.Any(x => x.Modifiers == modifiers && x.Key == key)) return false;
                Registered.Add(id, new Shortcut { Modifiers = modifiers, Key = key }); return true;
            }
            public void Unregister(int id) { Registered.Remove(id); }
            public void Fire(int id) { Pressed?.Invoke(id); }
            public void Dispose() { }
        }
        public static void Run(Action<bool, string> check)
        {
            var backend = new FakeRegistrar();
            using (var service = new HotKeyService(backend))
            {
                var first = new Shortcut();
                check(service.TryApply(first, null, out _), "primary hotkey registration");
                int oldId = backend.Registered.Keys.Single();
                backend.RejectKey = 0x42;
                check(!service.TryApply(new Shortcut { Key = 0x41 }, new Shortcut { Key = 0x42 }, out _), "second hotkey conflict rejects full update");
                check(backend.Registered.Count == 1 && backend.Registered.ContainsKey(oldId), "conflict rollback preserves original and removes staged key");
                backend.RejectKey = 0;
                check(service.TryApply(first, new Shortcut { Key = 0x41 }, out _), "alternate hotkey registration");
                check(service.TryApply(new Shortcut { Key = 0x41 }, first, out _), "existing hotkeys can swap without registration collision");
                int logical = 0; service.Pressed += id => logical = id; backend.Fire(oldId);
                check(logical == 2, "swapped key dispatches alternate logical id");
                check(!service.TryApply(first, first.Clone(), out _), "duplicate shortcuts rejected");
                check(!service.TryApply(new Shortcut { Modifiers = 0 }, null, out _), "unmodified shortcut rejected");
            }
            check(backend.Registered.Count == 0, "hotkeys released on dispose");
            if (Environment.OSVersion.Platform != PlatformID.Win32NT) return;

            var normalizer = new WindowsTextNormalizer();
            check(normalizer.ToTraditional("头发干了，在里面的软件") == "頭髮乾了，在裡面的軟件", "NLS contextual traditional fixture");
            check(normalizer.ToTraditional("API 日本語 🐈‍⬛ 😀") == "API 日本語 🐈‍⬛ 😀", "NLS preserves other scripts and emoji");
            check(normalizer.ToTraditional("") == "", "NLS handles empty input");
            var segmenter = new WindowsWordSegmenter();
            string mixed = "違約責任 English 日本語 😀";
            var spans = segmenter.GetWords(mixed);
            check(spans.Count > 0 && spans.All(s => s.Start >= 0 && s.Length > 0 && s.Start + s.Length <= mixed.Length), "Windows word spans stay in source bounds");
            check(spans.All(s => !char.IsLowSurrogate(mixed[s.Start]) && (s.Start + s.Length == mixed.Length || !char.IsLowSurrogate(mixed[s.Start + s.Length]))), "Windows word spans preserve surrogate pairs");

            var credentials = new WindowsCredentialStore("WhatsUpMyNeighbor.Tests/" + Guid.NewGuid().ToString("N"));
            try
            {
                check(credentials.Read() == "", "isolated credential starts empty");
                credentials.Write("test-only-not-an-api-key-測試");
                check(credentials.Read() == "test-only-not-an-api-key-測試", "isolated credential unicode roundtrip");
                credentials.Write("replacement-test-only");
                check(credentials.Read() == "replacement-test-only", "credential update");
                credentials.Delete();
                check(credentials.Read() == "", "credential delete");
            }
            finally { credentials.Delete(); }
            using (var delivery = new WindowsTextDelivery())
            {
                var result = delivery.DeliverAsync("fixture-only", new FocusSnapshot { CanPaste = false }, CancellationToken.None).GetAwaiter().GetResult();
                check(result.Copied && !result.PasteSent && !result.PasteVerified, "unknown target copies without injecting keys");
                check(!delivery.RevalidateCorrectionAsync().GetAwaiter().GetResult(), "unverified paste never enables correction learning");
                var canceled = new CancellationToken(true);
                bool canceledCorrectly = false;
                try { delivery.DeliverAsync("must-not-copy", null, canceled).GetAwaiter().GetResult(); }
                catch (OperationCanceledException) { canceledCorrectly = true; }
                check(canceledCorrectly, "cancelled delivery exits before clipboard write");
            }
        }

        /// <summary>Run only in the disposable Windows CI desktop, never against user documents.</summary>
        public static void RunInteractive(Action<bool, string> check)
        {
            string directory = Path.Combine(Path.GetTempPath(), "Neighbor.UiFixture." + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            Process fixture = null;
            try
            {
                fixture = Process.Start(new ProcessStartInfo(Assembly.GetEntryAssembly().Location, "--platform-ui-target \"" + directory + "\"") { UseShellExecute = false });
                Wait(() => File.Exists(Path.Combine(directory, "ready")), "fixture startup");
                Action<string> command = value =>
                {
                    File.WriteAllText(Path.Combine(directory, "command"), value);
                    Wait(() => Read(Path.Combine(directory, "ack")) == value, "fixture command " + value);
                    fixture.Refresh(); SetForegroundWindow(fixture.MainWindowHandle); Thread.Sleep(150);
                };
                using (var delivery = new WindowsTextDelivery())
                {
                    command("edit-1");
                    var target = delivery.CaptureAsync().GetAwaiter().GetResult();
                    check(target.CanPaste, "controlled editable window captured");
                    target.CapturedAtUtc = DateTime.UtcNow.AddMinutes(-11);
                    var expired = delivery.DeliverAsync("must-not-paste", target, CancellationToken.None).GetAwaiter().GetResult();
                    check(expired.Copied && !expired.PasteSent, "expired target snapshot prevents paste");
                    target.CapturedAtUtc = DateTime.UtcNow;
                    command("password-before-paste");
                    command("return-edit");
                    var inserted = delivery.DeliverAsync("neko", target, CancellationToken.None).GetAwaiter().GetResult();
                    Wait(() => Read(Path.Combine(directory, "text")) == "prefix neko suffix", "controlled paste");
                    check(inserted.PasteSent, "same field restored before delivery receives text without Enter");
                    if (!inserted.PasteVerified)
                    {
                        check(!delivery.RevalidateCorrectionAsync().GetAwaiter().GetResult(), "provider without stable insertion range disables learning");
                        Console.WriteLine("LIMITATION: fixture provider did not preserve exact insertion range; correction integration unverified.");
                    }
                    else
                    {
                        bool observed = false;
                        delivery.CorrectionObserved += (sender, change) => { if (change.IsValid && change.Corrected == "neighbor") observed = true; };
                        command("correct");
                        Thread.Sleep(500);
                        if (observed) check(delivery.RevalidateCorrectionAsync().GetAwaiter().GetResult(), "observed correction revalidates exact range");
                        else check(!delivery.RevalidateCorrectionAsync().GetAwaiter().GetResult(), "invalidated correction range fails closed");
                    }
                    command("edit-2");
                    var remembered = delivery.CaptureAsync().GetAwaiter().GetResult();
                    command("password-1");
                    var wrongTarget = delivery.DeliverAsync("must-not-paste", remembered, CancellationToken.None).GetAwaiter().GetResult();
                    check(wrongTarget.Copied && !wrongTarget.PasteSent, "focus switch prevents key injection");
                    var secret = delivery.CaptureAsync().GetAwaiter().GetResult();
                    check(!secret.CanPaste, "password target rejected");
                    delivery.StopObserving();
                    check(!delivery.RevalidateCorrectionAsync().GetAwaiter().GetResult(), "stopping observation invalidates pending candidate");
                    Console.WriteLine("LIMITATION: real Chinese/Japanese/Korean IME composition requires a desktop with that input method; not simulated as a passing hardware test.");
                }
            }
            finally
            {
                if (fixture != null && !fixture.HasExited) { fixture.CloseMainWindow(); if (!fixture.WaitForExit(2000)) fixture.Kill(); }
                fixture?.Dispose();
                try { Directory.Delete(directory, true); } catch { }
            }
        }
        public static bool TryRunTarget(string[] args)
        {
            if (args.Length < 2 || args[0] != "--platform-ui-target") return false;
            string directory = args[1];
            Application.EnableVisualStyles();
            using (var form = new Form { Text = "Neighbor isolated UI fixture", Width = 500, Height = 250, TopMost = true })
            using (var edit = new RichTextBox { Left = 20, Top = 20, Width = 440, Height = 100, Text = "prefix  suffix" })
            using (var password = new TextBox { Left = 20, Top = 140, Width = 440, UseSystemPasswordChar = true })
            using (var timer = new System.Windows.Forms.Timer { Interval = 40 })
            {
                form.Controls.Add(edit); form.Controls.Add(password);
                string previous = null;
                edit.TextChanged += (sender, e) => File.WriteAllText(Path.Combine(directory, "text"), edit.Text);
                form.Shown += (sender, e) => { edit.Focus(); edit.Select(7, 0); File.WriteAllText(Path.Combine(directory, "ready"), "ready"); };
                timer.Tick += (sender, e) =>
                {
                    string command = Read(Path.Combine(directory, "command"));
                    if (string.IsNullOrEmpty(command) || command == previous) return;
                    previous = command;
                    if (command.StartsWith("edit", StringComparison.Ordinal)) { edit.Text = "prefix  suffix"; edit.Focus(); edit.Select(7, 0); }
                    else if (command.StartsWith("password", StringComparison.Ordinal)) password.Focus();
                    else if (command == "return-edit") edit.Focus();
                    else if (command == "correct") { edit.Focus(); edit.Select(7, 4); edit.SelectedText = "neighbor"; }
                    File.WriteAllText(Path.Combine(directory, "ack"), command);
                };
                timer.Start(); Application.Run(form);
            }
            return true;
        }
        private static string Read(string path) { try { return File.ReadAllText(path); } catch (IOException) { return null; } }
        private static void Wait(Func<bool> condition, string stage)
        {
            var timeout = Stopwatch.StartNew();
            while (!condition()) { if (timeout.Elapsed > TimeSpan.FromSeconds(8)) throw new Exception("UI fixture timeout: " + stage); Thread.Sleep(50); }
        }
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    }
}
