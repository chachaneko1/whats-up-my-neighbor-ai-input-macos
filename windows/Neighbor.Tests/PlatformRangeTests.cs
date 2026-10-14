using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using Neighbor.Core;
using Neighbor.Windows.Platform;

namespace Neighbor.Tests
{
    /// <summary>A second provider with real live text pointers. WPF is a test-only dependency.</summary>
    internal static class PlatformRangeTests
    {
        public static void Run(Action<bool, string> check)
        {
            string directory = Path.Combine(Path.GetTempPath(), "Neighbor.WpfFixture." + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            Process fixture = null;
            try
            {
                fixture = Process.Start(new ProcessStartInfo(Assembly.GetEntryAssembly().Location,
                    "--platform-wpf-target \"" + directory + "\"") { UseShellExecute = false });
                FixtureStartup.Wait(fixture, directory, "WPF fixture");
                Action activate = () =>
                {
                    fixture.Refresh(); var window = fixture.MainWindowHandle;
                    Wait(() => { if (GetForegroundWindow() == window) return true; SetForegroundWindow(window); return GetForegroundWindow() == window; }, "foreground");
                };
                Action<string> command = value =>
                {
                    activate(); File.WriteAllText(Path.Combine(directory, "command"), value);
                    Wait(() => Read(Path.Combine(directory, "ack")) == value, value); activate();
                };
                using (var delivery = new WindowsTextDelivery())
                {
                    delivery.Diagnostic += detail => Console.WriteLine("WPF UIA diagnostic: " + detail);
                    const string sentence = "the neko sleeps";
                    var scenarios = new[]
                    {
                        new Scenario("sentence same-length", sentence, "correct-word|NEKO", "the NEKO sleeps", true),
                        new Scenario("sentence longer", sentence, "correct-word|neighbor", "the neighbor sleeps", true),
                        new Scenario("sentence shorter", sentence, "correct-word|cat", "the cat sleeps", true),
                        new Scenario("complete same-length", "neko", "correct-all|NEKO", "NEKO", false),
                        new Scenario("complete longer", "neko", "correct-all|neighbor", "neighbor", false),
                        new Scenario("complete shorter", "neko", "correct-all|cat", "cat", false),
                        new Scenario("neighboring prefix", sentence, "edit-prefix", sentence, false, "neighbour " + sentence + " suffix"),
                        new Scenario("neighboring suffix", sentence, "edit-suffix", sentence, false, "prefix " + sentence + " / suffix")
                    };
                    for (int index = 0; index < scenarios.Length; index++)
                    {
                        var scenario = scenarios[index];
                        string label = "WPF " + scenario.Label;
                        command("reset-" + index);
                        if (index == 0) PlatformRangeDiagnostics.Run(fixture.Id, "WPF");
                        FocusSnapshot target = null;
                        for (int attempt = 0; attempt < 3; attempt++)
                        {
                            target = delivery.CaptureAsync().GetAwaiter().GetResult();
                            if (target.CanPaste) break;
                            Thread.Sleep(100);
                        }
                        check(target.CanPaste, label + " editable target captured");
                        if (!target.CanPaste) { Console.WriteLine("WPF capture: " + target.Reason); continue; }
                        var inserted = delivery.DeliverAsync(scenario.Inserted, target, CancellationToken.None).GetAwaiter().GetResult();
                        Console.WriteLine(label + " insertion: sent=" + inserted.PasteSent + "; verified=" + inserted.PasteVerified + "; " + inserted.Message);
                        check(inserted.PasteSent && inserted.PasteVerified, label + " exact insertion range verified");
                        if (!inserted.PasteSent || !inserted.PasteVerified) continue;
                        Wait(() => Read(Path.Combine(directory, "text")) == "prefix " + scenario.Inserted + " suffix", "inserted text");
                        check(delivery.RevalidateCorrectionAsync().GetAwaiter().GetResult(), label + " inserted range is actively tracked");
                        using (var signal = new ManualResetEventSlim())
                        {
                            object gate = new object(); bool listening = true; string observed = null; string invalidReason = null;
                            EventHandler<CorrectionEventArgs> handler = (sender, change) =>
                            {
                                lock (gate)
                                {
                                    if (!listening) return;
                                    if (change.IsValid) observed = change.Corrected;
                                    else if (change.Reason != "組字或選取中，暫停詞彙學習。") invalidReason = change.Reason;
                                    if (observed != null || invalidReason != null) signal.Set();
                                }
                            };
                            delivery.CorrectionObserved += handler;
                            try
                            {
                                // Commands modify only the explicitly selected span,
                                // never replace the whole field to simulate a correction.
                                command(scenario.Command);
                                Wait(() => Read(Path.Combine(directory, "text")) == scenario.ExpectedField, "corrected text");
                                signal.Wait(TimeSpan.FromSeconds(4));
                                string actual, reason; lock (gate) { actual = observed; reason = invalidReason; }
                                if (scenario.ShouldLearn)
                                {
                                    check(actual == scenario.Corrected, label + " correction stays within inserted text");
                                    if (actual != scenario.Corrected) Console.WriteLine(label + " correction status: " + (reason ?? "no matching observation"));
                                    check(delivery.RevalidateCorrectionAsync().GetAwaiter().GetResult(), label + " correction revalidates live endpoints");
                                }
                                else
                                {
                                    check(actual == null && reason != null, label + " unsafe boundary change stops learning without a candidate");
                                    Console.WriteLine(label + " stopped: " + (reason ?? "no stop observation"));
                                    check(!delivery.RevalidateCorrectionAsync().GetAwaiter().GetResult(), label + " stopped range cannot revalidate");
                                }
                            }
                            finally { lock (gate) { listening = false; delivery.CorrectionObserved -= handler; } }
                        }
                        delivery.StopObserving();
                        check(!delivery.RevalidateCorrectionAsync().GetAwaiter().GetResult(), label + " observation can be stopped");
                    }
                }
            }
            finally
            {
                if (fixture != null && !fixture.HasExited) { fixture.CloseMainWindow(); if (!fixture.WaitForExit(2000)) fixture.Kill(); }
                fixture?.Dispose();
                try { Directory.Delete(directory, true); } catch { }
            }
        }

        private sealed class Scenario
        {
            internal readonly string Label, Inserted, Command, Corrected, ExpectedField;
            internal readonly bool ShouldLearn;
            internal Scenario(string label, string inserted, string command, string corrected, bool shouldLearn, string expectedField = null)
            {
                Label = label; Inserted = inserted; Command = command; Corrected = corrected; ShouldLearn = shouldLearn;
                ExpectedField = expectedField ?? "prefix " + corrected + " suffix";
            }
        }

        public static bool TryRunTarget(string[] args)
        {
            if (args.Length < 2 || args[0] != "--platform-wpf-target") return false;
            string directory = args[1];
            var app = new System.Windows.Application();
            var edit = new System.Windows.Controls.TextBox { Text = "prefix  suffix", AcceptsReturn = true,
                Margin = new System.Windows.Thickness(20), FontSize = 20, TextWrapping = System.Windows.TextWrapping.Wrap };
            var window = new System.Windows.Window { Title = "Neighbor isolated WPF range fixture", Width = 520, Height = 250, Topmost = true, Content = edit };
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(40) };
            string previous = null;
            edit.TextChanged += (sender, e) => File.WriteAllText(Path.Combine(directory, "text"), edit.Text);
            window.ContentRendered += (sender, e) => { edit.Focus(); edit.Select(7, 0); File.WriteAllText(Path.Combine(directory, "ready"), "ready"); };
            timer.Tick += (sender, e) =>
            {
                string command = Read(Path.Combine(directory, "command"));
                if (string.IsNullOrEmpty(command) || command == previous) return;
                previous = command; window.Activate(); edit.Focus();
                if (command.StartsWith("reset-", StringComparison.Ordinal)) { edit.Text = "prefix  suffix"; edit.Select(7, 0); }
                else if (command.StartsWith("correct-word|", StringComparison.Ordinal))
                {
                    string replacement = command.Substring(13);
                    edit.Select(11, 4); edit.SelectedText = replacement; edit.Select(11 + replacement.Length, 0);
                }
                else if (command.StartsWith("correct-all|", StringComparison.Ordinal))
                {
                    string replacement = command.Substring(12);
                    edit.Select(7, 4); edit.SelectedText = replacement; edit.Select(7 + replacement.Length, 0);
                }
                else if (command == "edit-prefix")
                { edit.Select(0, 6); edit.SelectedText = "neighbour"; edit.Select(9, 0); }
                else if (command == "edit-suffix")
                { edit.Select(22, 1); edit.SelectedText = " / "; edit.Select(25, 0); }
                File.WriteAllText(Path.Combine(directory, "ack"), command);
            };
            window.Closed += (sender, e) => timer.Stop();
            timer.Start(); app.Run(window); return true;
        }
        private static string Read(string path)
        {
            try { using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) using (var reader = new StreamReader(stream)) return reader.ReadToEnd(); }
            catch (IOException) { return null; }
        }
        private static void Wait(Func<bool> condition, string stage)
        {
            var watch = Stopwatch.StartNew();
            while (!condition()) { if (watch.Elapsed > TimeSpan.FromSeconds(8)) throw new TimeoutException("WPF fixture: " + stage); Thread.Sleep(40); }
        }
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    }
}
