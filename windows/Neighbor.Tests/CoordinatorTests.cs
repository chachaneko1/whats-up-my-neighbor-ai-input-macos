using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Neighbor.Core;

namespace Neighbor.Tests
{
    public static class CoordinatorTests
    {
        private const string Foreign = "สวัสดีครับ ผมชอบกินข้าวผัดกระเพราหมูสับ";
        public static async Task RunAsync(Action<bool, string> check)
        {
            using (var f = new Fixture())
            {
                var settings = new AppSettings { Mode = OutputMode.Verbatim, InputDeviceId = "initial-microphone" };
                f.Transcriber.Results.Enqueue(_ => Task.FromResult("嗯，這個，這個功能"));
                await f.Coordinator.StartAsync(settings);
                string path = f.Recorder.Path;
                settings.Mode = OutputMode.Concise; settings.PrimaryLanguage = "en"; settings.AdditionalLanguages.Clear(); settings.InputDeviceId = "other-microphone";
                check(f.Coordinator.State == DictationState.Recording && f.Recorder.Device == "initial-microphone", "Recording starts using selected microphone");
                await f.Coordinator.StopAsync();
                check(f.Transcriber.Calls.Single().Language == "zh" && f.Delivery.Text == "嗯，這個，這個功能", "Language and text mode are snapshotted for the recording");
                check(ReferenceEquals(f.Delivery.Captured, f.Delivery.Target), "Delivery receives the original focused target snapshot");
                check(f.Coordinator.State == DictationState.Idle && !File.Exists(path) && f.Delivery.Count == 1, "Successful delivery cleans audio and returns idle");
                check(f.States.Contains(DictationState.Finalizing) && f.States.Contains(DictationState.Transcribing) && f.States.Contains(DictationState.Delivering), "Lifecycle includes finalizing transcription and delivery");
            }
            using (var f = new Fixture())
            {
                f.Transcriber.Results.Enqueue(_ => Task.FromResult("嗯，我知道了喔"));
                await f.Coordinator.StartAsync(new AppSettings { Mode = OutputMode.Verbatim, AlternateMode = OutputMode.Concise }, true);
                await f.Coordinator.StopAsync();
                check(f.Delivery.Text == "我知道了", "Alternate shortcut uses alternate output mode");
            }
            using (var f = new Fixture())
            {
                var gate = new TaskCompletionSource<string>(); f.Transcriber.Results.Enqueue(_ => gate.Task);
                await f.Coordinator.StartAsync(new AppSettings()); string oldPath = f.Recorder.Path;
                Task oldStop = f.Coordinator.StopAsync();
                check(f.Coordinator.State == DictationState.Transcribing && f.Transcriber.Calls.Count == 1, "Recognition awaits pending server response");
                await f.Coordinator.ToggleAsync(new AppSettings()); await f.Coordinator.StopAsync();
                check(f.Recorder.StartCount == 1 && f.Transcriber.Calls.Count == 1, "Hotkey and stop during recognition do not start duplicate work");
                await f.Coordinator.CancelAsync();
                check(f.Transcriber.Calls[0].Cancellation.IsCancellationRequested && !File.Exists(oldPath), "Cancel propagates token and removes audio");
                await f.Coordinator.StartAsync(new AppSettings());
                gate.SetResult("late response"); await oldStop;
                check(f.Delivery.Count == 0 && f.Coordinator.State == DictationState.Recording, "Late cancelled response cannot paste or finish a newer recording");
                await f.Coordinator.CancelAsync();
            }
            using (var f = new Fixture())
            {
                var capture = new TaskCompletionSource<FocusSnapshot>(); f.Delivery.CaptureGate = capture.Task;
                Task start = f.Coordinator.StartAsync(new AppSettings()); Task cancel = f.Coordinator.CancelAsync();
                capture.SetResult(new FocusSnapshot()); await start; await cancel;
                check(f.Recorder.StartCount == 0 && f.Transcriber.Calls.Count == 0 && f.Coordinator.State == DictationState.Idle, "Cancel during focus capture never opens recorder");
            }
            using (var f = new Fixture())
            {
                var opening = new TaskCompletionSource<bool>(); f.Recorder.StartGate = opening.Task;
                Task start = f.Coordinator.StartAsync(new AppSettings()); string path = f.Recorder.Path;
                Task cancel = f.Coordinator.CancelAsync();
                await f.Coordinator.StartAsync(new AppSettings());
                check(f.Coordinator.State == DictationState.Finalizing && f.Recorder.StartCount == 1, "Cancelling microphone startup holds state until recorder settles");
                opening.SetResult(true); await start; await cancel;
                check(f.Recorder.StopCount == 1 && f.Transcriber.Calls.Count == 0 && !File.Exists(path) && f.Coordinator.State == DictationState.Idle, "Cancelled startup is stopped once and cleaned after finalization");
            }
            using (var f = new Fixture())
            {
                var closing = new TaskCompletionSource<bool>(); f.Recorder.StopGate = closing.Task;
                await f.Coordinator.StartAsync(new AppSettings()); string path = f.Recorder.Path;
                Task stop = f.Coordinator.StopAsync(); Task cancel = f.Coordinator.CancelAsync();
                check(f.Recorder.StopCount == 1 && f.Transcriber.Calls.Count == 0, "Cancel during finalization shares the existing stop operation");
                closing.SetResult(true); await stop; await cancel;
                check(!File.Exists(path) && f.Transcriber.Calls.Count == 0 && f.Coordinator.State == DictationState.Idle, "Completed cancelled finalization never uploads and deletes final file");
            }
            using (var f = new Fixture())
            {
                await f.Coordinator.StartAsync(new AppSettings { SilenceSeconds = 3 });
                for (int second = 1; second <= 3; second++) { f.Advance(1); f.Recorder.Level(-60, true); await f.Coordinator.TickAsync(); }
                check(f.Coordinator.State == DictationState.Idle && f.Transcriber.Calls.Count == 1, "Three seconds of known low levels ends recording");
            }
            using (var f = new Fixture())
            {
                await f.Coordinator.StartAsync(new AppSettings { SilenceSeconds = 3 });
                f.Advance(10); f.Recorder.Level(-90, false); await f.Coordinator.TickAsync();
                check(f.Coordinator.State == DictationState.Recording, "Unknown meter is not treated as silence");
                f.Recorder.Level(-60, true); f.Advance(5); await f.Coordinator.TickAsync();
                check(f.Coordinator.State == DictationState.Recording, "Stale meter does not truncate speech");
                f.Advance(1); f.Recorder.Level(-60, true); await f.Coordinator.TickAsync();
                check(f.Coordinator.State == DictationState.Recording, "Returning meter starts a fresh silence interval");
                await f.Coordinator.CancelAsync();
            }
            using (var f = new Fixture())
            {
                await f.Coordinator.StartAsync(new AppSettings { SilenceSeconds = 3 });
                for (int i = 0; i < 5; i++) { f.Advance(1); f.Recorder.Level(-20, true); await f.Coordinator.TickAsync(); }
                check(f.Coordinator.State == DictationState.Recording, "Audible samples reset silence deadline");
                await f.Coordinator.CancelAsync();
            }
            using (var f = new Fixture())
            {
                await f.Coordinator.StartAsync(new AppSettings()); f.Advance(299); await f.Coordinator.TickAsync();
                check(f.Coordinator.State == DictationState.Recording, "Default silence stopping remains off");
                f.Advance(1); await f.Coordinator.TickAsync();
                check(f.Coordinator.State == DictationState.Idle && f.Transcriber.Calls.Count == 1, "Five-minute maximum stops even without meter data");
            }
            using (var f = new Fixture())
            {
                f.Transcriber.Results.Enqueue(_ => Task.FromResult(Foreign)); f.Transcriber.Results.Enqueue(_ => Task.FromResult("正常中文結果"));
                await f.Coordinator.StartAsync(new AppSettings()); await f.Coordinator.StopAsync();
                check(f.Transcriber.Calls.Count == 2 && f.Delivery.Count == 1 && f.Delivery.Text == "正常中文結果", "Unsupported script retries once and accepts valid retry");
                check(f.Transcriber.Calls[0].Prompt != f.Transcriber.Calls[1].Prompt && f.Transcriber.Calls.All(c => c.Language == "zh"), "Language retry strengthens prompt without changing primary language");
            }
            using (var f = new Fixture())
            {
                for (int i = 0; i < 3; i++) f.Transcriber.Results.Enqueue(_ => Task.FromResult(Foreign));
                await f.Coordinator.StartAsync(new AppSettings()); await f.Coordinator.StopAsync();
                check(f.Transcriber.Calls.Count == 2 && f.Delivery.Count == 0 && f.Coordinator.State == DictationState.RetainedAudio, "Two wrong-script results retain audio and never paste");
                await f.Coordinator.RetryAsync();
                check(f.Transcriber.Calls.Count == 3 && f.Delivery.Count == 0 && f.Coordinator.State == DictationState.RetainedAudio, "Manual retry is one request and still runs language gate");
                await f.Coordinator.CancelAsync();
            }
            using (var f = new Fixture())
            {
                f.Transcriber.Results.Enqueue(_ => Task.FromResult(Foreign));
                await f.Coordinator.StartAsync(new AppSettings { AutomaticLanguageRetry = false }); await f.Coordinator.StopAsync();
                check(f.Transcriber.Calls.Count == 1 && f.Coordinator.State == DictationState.RetainedAudio, "Disabled automatic retry makes one request");
                string path = f.Recorder.Path; f.Advance(119); await f.Coordinator.TickAsync();
                check(File.Exists(path), "Failed audio remains available before two-minute expiry");
                f.Advance(1); await f.Coordinator.TickAsync();
                check(!File.Exists(path) && f.Coordinator.State == DictationState.Idle, "Failed audio deleted exactly at expiry");
                await f.Coordinator.RetryAsync(); check(f.Transcriber.Calls.Count == 1, "Expired audio cannot be retried");
            }
            using (var f = new Fixture())
            {
                f.Transcriber.Results.Enqueue(_ => Task.FromException<string>(new InvalidOperationException("test failure")));
                await f.Coordinator.StartAsync(new AppSettings()); await f.Coordinator.StopAsync(); string path = f.Recorder.Path;
                await f.Coordinator.StartAsync(new AppSettings());
                check(!File.Exists(path) && f.Recorder.Path != path && f.Coordinator.State == DictationState.Recording, "Starting a new recording discards retained audio");
                await f.Coordinator.CancelAsync();
            }
            using (var f = new Fixture())
            {
                f.Transcriber.Results.Enqueue(_ => Task.FromResult(""));
                await f.Coordinator.StartAsync(new AppSettings()); await f.Coordinator.StopAsync();
                check(f.Delivery.Count == 0 && f.Coordinator.State == DictationState.RetainedAudio, "Empty transcription is retained without delivery");
                f.Advance(120); await f.Coordinator.RetryAsync();
                check(f.Coordinator.State == DictationState.Idle && !File.Exists(f.Recorder.Path) && f.Transcriber.Calls.Count == 1, "Retry checks expiry without waiting for timer tick");
            }
            using (var f = new Fixture())
            {
                f.Delivery.Result = new InsertionResult { Copied = false };
                await f.Coordinator.StartAsync(new AppSettings()); await f.Coordinator.StopAsync(); string path = f.Recorder.Path;
                check(File.Exists(path) && f.Coordinator.State == DictationState.RetainedAudio, "Clipboard failure retains audio for retry");
                f.Delivery.Result = new InsertionResult { Copied = true, PasteSent = false, Message = "請手動貼上" };
                await f.Coordinator.RetryAsync();
                check(f.Coordinator.State == DictationState.Idle && !File.Exists(path) && f.Coordinator.Status == "請手動貼上", "Copy-only delivery is successful and removes audio");
            }
            using (var f = new Fixture())
            {
                f.Recorder.Usable = false; await f.Coordinator.StartAsync(new AppSettings()); await f.Coordinator.StopAsync();
                check(f.Coordinator.State == DictationState.Idle && f.Transcriber.Calls.Count == 0 && !File.Exists(f.Recorder.Path), "Empty finalized recording never uploads");
            }
            using (var f = new Fixture())
            {
                f.Recorder.StartFailure = new IOException("simulated start failure"); await f.Coordinator.StartAsync(new AppSettings());
                check(f.Coordinator.State == DictationState.Idle && f.Recorder.StopCount == 1 && !File.Exists(f.Recorder.Path), "Recorder startup failure stops and cleans up");
            }
            using (var f = new Fixture())
            {
                f.Recorder.StopFailure = new IOException("simulated stop failure"); await f.Coordinator.StartAsync(new AppSettings()); await f.Coordinator.StopAsync();
                check(f.Coordinator.State == DictationState.Idle && f.Transcriber.Calls.Count == 0, "Finalization failure restores idle without upload");
            }
            using (var f = new Fixture())
            {
                f.Transcriber.Results.Enqueue(_ => Task.FromResult("嗯")); await f.Coordinator.StartAsync(new AppSettings { Mode = OutputMode.Standard }); await f.Coordinator.StopAsync();
                check(f.Delivery.Text == "嗯", "Cleanup that removes all content falls back to original utterance");
            }
            await CancellationReentrancyChecks(check);
            QueuedRecorderChecks(check);
        }

        private static async Task CancellationReentrancyChecks(Action<bool, string> check)
        {
            using (var f = new Fixture())
            {
                var opening = new TaskCompletionSource<bool>(); f.Recorder.StartGate = opening.Task;
                Task start = f.Coordinator.StartAsync(new AppSettings()); string path = f.Recorder.Path;
                Task first = f.Coordinator.CancelAsync(), second = f.Coordinator.CancelAsync();
                check(ReferenceEquals(first, second) && !first.IsCompleted && f.Coordinator.State == DictationState.Finalizing,
                    "Repeated cancellation shares pending microphone startup cleanup and stays busy");
                Task prematureStart = f.Coordinator.StartAsync(new AppSettings());
                check(f.Recorder.StartCount == 1, "Repeated cancellation cannot admit a new recording before startup settles");
                opening.SetResult(true); await start; await prematureStart; await first; await second;
                check(f.Recorder.StopCount == 1 && !File.Exists(path) && f.Coordinator.State == DictationState.Idle,
                    "Repeated startup cancellation stops once and deletes audio before returning idle");
                f.Recorder.StartGate = null; await f.Coordinator.StartAsync(new AppSettings());
                check(f.Recorder.StartCount == 2 && f.Coordinator.State == DictationState.Recording,
                    "A new recording starts normally after all cancellation callers complete");
                await f.Coordinator.CancelAsync();
            }
            using (var f = new Fixture())
            {
                await f.Coordinator.StartAsync(new AppSettings()); string path = f.Recorder.Path;
                var closing = new TaskCompletionSource<bool>(); f.Recorder.StopGate = closing.Task;
                Task stop = f.Coordinator.StopAsync();
                Task first = f.Coordinator.CancelAsync(), second = f.Coordinator.CancelAsync();
                Task prematureStart = f.Coordinator.StartAsync(new AppSettings());
                check(ReferenceEquals(first, second) && !second.IsCompleted && f.Coordinator.State == DictationState.Finalizing && f.Recorder.StartCount == 1,
                    "Repeated cancellation during finalization cannot release the busy state");
                closing.SetResult(true); await stop; await prematureStart; await first; await second;
                check(f.Recorder.StopCount == 1 && f.Transcriber.Calls.Count == 0 && !File.Exists(path),
                    "Repeated finalization cancellation shares stop and never uploads the canceled recording");
            }
            using (var f = new Fixture())
            {
                await f.Coordinator.StartAsync(new AppSettings());
                Task nested = null; int idleEvents = 0;
                f.Coordinator.StatusChanged += (_, e) =>
                {
                    if (e.State == DictationState.Finalizing && nested == null) nested = f.Coordinator.CancelAsync();
                    if (e.State == DictationState.Idle) idleEvents++;
                };
                Task first = f.Coordinator.CancelAsync(); await first;
                check(ReferenceEquals(first, nested) && idleEvents == 1 && f.Recorder.StopCount == 1,
                    "Cancellation is already shared when synchronous status listeners reenter it");
            }
            using (var f = new Fixture())
            {
                f.Recorder.ThrowOnCancellation = true;
                await f.Coordinator.StartAsync(new AppSettings()); string path = f.Recorder.Path;
                bool threw = false;
                try { await f.Coordinator.CancelAsync(); } catch { threw = true; }
                check(!threw && f.Recorder.StopCount == 1 && !File.Exists(path) && f.Coordinator.State == DictationState.Idle,
                    "A device cancellation callback error cannot skip stop and temporary-file cleanup");
            }
        }

        private static void QueuedRecorderChecks(Action<bool, string> check)
        {
            var previous = SynchronizationContext.Current;
            var ui = new PumpContext();
            SynchronizationContext.SetSynchronizationContext(ui);
            try
            {
                using (var f = new Fixture())
                {
                    int readings = 0;
                    f.Coordinator.LevelChanged += (_, e) => readings++;
                    f.Coordinator.StartAsync(new AppSettings { SilenceSeconds = 3 }).GetAwaiter().GetResult();
                    ui.FromWorker(() => f.Recorder.Level(-60, true));
                    check(ui.Count == 1 && readings == 0, "Recorder levels wait for the captured UI synchronization context");
                    f.Coordinator.CancelAsync().GetAwaiter().GetResult();
                    f.Coordinator.StartAsync(new AppSettings { SilenceSeconds = 3 }).GetAwaiter().GetResult();
                    f.Advance(4); ui.Pump();
                    f.Coordinator.TickAsync().GetAwaiter().GetResult();
                    check(readings == 0 && f.Coordinator.State == DictationState.Recording && f.Transcriber.Calls.Count == 0,
                        "Queued old recording level cannot update the meter or silence-stop a newer recording");
                    f.Coordinator.CancelAsync().GetAwaiter().GetResult();
                }
                using (var f = new Fixture())
                {
                    f.Coordinator.StartAsync(new AppSettings()).GetAwaiter().GetResult();
                    ui.FromWorker(f.Recorder.Interrupt);
                    check(ui.Count == 1, "Recorder failures are queued for the captured UI context");
                    f.Coordinator.CancelAsync().GetAwaiter().GetResult();
                    f.Coordinator.StartAsync(new AppSettings()).GetAwaiter().GetResult();
                    int stops = f.Recorder.StopCount;
                    ui.Pump();
                    check(f.Coordinator.State == DictationState.Recording && f.Recorder.StopCount == stops && f.Transcriber.Calls.Count == 0,
                        "Queued old recorder failure cannot cancel a newer recording");
                    f.Coordinator.CancelAsync().GetAwaiter().GetResult();
                }
                using (var f = new Fixture())
                {
                    ui.FromWorker(() => { f.Recorder.Level(-20, true); f.Recorder.Interrupt(); });
                    f.Coordinator.StartAsync(new AppSettings()).GetAwaiter().GetResult();
                    ui.Pump();
                    check(f.Coordinator.State == DictationState.Recording && f.Recorder.StopCount == 0,
                        "Recorder callbacks received without a job cannot attach to a later recording");
                    f.Coordinator.CancelAsync().GetAwaiter().GetResult();
                }
                using (var f = new Fixture())
                {
                    int readings = 0;
                    f.Coordinator.LevelChanged += (_, e) => { if (e.IsKnown && e.Decibels == -60) readings++; };
                    f.Coordinator.StartAsync(new AppSettings { SilenceSeconds = 3 }).GetAwaiter().GetResult();
                    f.Advance(3); ui.FromWorker(() => f.Recorder.Level(-60, true));
                    ui.Pump(); f.Coordinator.TickAsync().GetAwaiter().GetResult();
                    check(readings == 1 && f.Coordinator.State == DictationState.Idle && f.Transcriber.Calls.Count == 1,
                        "Current queued recorder level still updates the meter and silence timer");
                }
                using (var f = new Fixture())
                {
                    f.Coordinator.StartAsync(new AppSettings { SilenceSeconds = 3 }).GetAwaiter().GetResult();
                    f.Advance(3); ui.FromWorker(() => f.Recorder.Level(-60, true));
                    f.Advance(2); ui.Pump(); f.Coordinator.TickAsync().GetAwaiter().GetResult();
                    check(f.Coordinator.State == DictationState.Recording && f.Transcriber.Calls.Count == 0,
                        "Delayed queued meter data keeps its arrival time and cannot masquerade as a fresh silent sample");
                    f.Coordinator.CancelAsync().GetAwaiter().GetResult();
                }
                using (var f = new Fixture())
                {
                    f.Coordinator.StartAsync(new AppSettings()).GetAwaiter().GetResult();
                    ui.FromWorker(f.Recorder.Interrupt); ui.Pump();
                    check(f.Coordinator.State == DictationState.Idle && f.Recorder.StopCount == 1 && f.Coordinator.Status.Contains("麥克風中斷"),
                        "Current queued recorder failure still stops its recording and reports the interruption");
                }
                using (var f = new Fixture())
                {
                    f.Coordinator.StartAsync(new AppSettings()).GetAwaiter().GetResult();
                    bool restarted = false;
                    f.Coordinator.StatusChanged += (_, e) =>
                    {
                        if (e.State != DictationState.Idle || restarted) return;
                        restarted = true;
                        f.Coordinator.StartAsync(new AppSettings()).GetAwaiter().GetResult();
                    };
                    ui.FromWorker(f.Recorder.Interrupt); ui.Pump();
                    check(restarted && f.Coordinator.State == DictationState.Recording && f.Recorder.StartCount == 2,
                        "Recorder failure completion cannot overwrite a recording started from the idle notification");
                    f.Coordinator.CancelAsync().GetAwaiter().GetResult();
                }
            }
            finally { SynchronizationContext.SetSynchronizationContext(previous); }
        }

        private sealed class PumpContext : SynchronizationContext
        {
            private readonly Queue<Action> queue = new Queue<Action>();
            public int Count { get { return queue.Count; } }
            public override void Post(SendOrPostCallback callback, object state) { queue.Enqueue(() => callback(state)); }
            public void FromWorker(Action action)
            {
                var previous = Current;
                try { SetSynchronizationContext(null); action(); }
                finally { SetSynchronizationContext(previous); }
            }
            public void Pump()
            {
                var previous = Current;
                try { SetSynchronizationContext(this); while (queue.Count > 0) queue.Dequeue()(); }
                finally { SetSynchronizationContext(previous); }
            }
        }

        private sealed class Fixture : IDisposable
        {
            private readonly string directory = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "NeighborCoordinatorTests-" + Guid.NewGuid().ToString("N"));
            public readonly Recorder Recorder = new Recorder(); public readonly Transcriber Transcriber = new Transcriber(); public readonly Delivery Delivery = new Delivery();
            public readonly DictationCoordinator Coordinator; public readonly List<DictationState> States = new List<DictationState>();
            private DateTime now = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            public Fixture()
            {
                Directory.CreateDirectory(directory);
                Coordinator = new DictationCoordinator(Recorder, Transcriber, Delivery, new Normalizer(), new TemporaryAudioStore(System.IO.Path.Combine(directory, "audio")), new VocabularyStore(System.IO.Path.Combine(directory, "vocabulary.json")), () => now);
                Coordinator.StatusChanged += (_, e) => States.Add(e.State);
            }
            public void Advance(double seconds) { now = now.AddSeconds(seconds); }
            public void Dispose() { Directory.Delete(directory, true); }
        }
        private sealed class Normalizer : ITextNormalizer { public string ToTraditional(string text) { return text; } }
        private sealed class Recorder : IAudioRecorder
        {
            public event EventHandler<AudioLevelEventArgs> LevelChanged;
            public event EventHandler StoppedUnexpectedly;
            public string Path, Device; public int StartCount, StopCount; public bool Usable = true, ThrowOnCancellation;
            public Task StartGate, StopGate; public Exception StartFailure, StopFailure;
            public IReadOnlyList<AudioDevice> GetDevices() { return new List<AudioDevice>(); }
            public async Task StartAsync(string path, string deviceId, CancellationToken cancellation)
            {
                Path = path; Device = deviceId; StartCount++;
                if (ThrowOnCancellation) cancellation.Register(() => { throw new IOException("synthetic device cancellation failure"); });
                if (StartGate != null) await StartGate;
                if (StartFailure != null) throw StartFailure;
            }
            public async Task StopAsync()
            {
                StopCount++; if (StopGate != null) await StopGate;
                if (StopFailure != null) throw StopFailure;
                if (Path != null) File.WriteAllBytes(Path, new byte[Usable ? 100 : 44]);
            }
            public void Level(double db, bool known) { LevelChanged?.Invoke(this, new AudioLevelEventArgs { Decibels = db, IsKnown = known }); }
            public void Interrupt() { StoppedUnexpectedly?.Invoke(this, EventArgs.Empty); }
            public void Dispose() { }
        }
        private sealed class Call { public string Language, Prompt; public CancellationToken Cancellation; }
        private sealed class Transcriber : ITranscriber
        {
            public readonly Queue<Func<CancellationToken, Task<string>>> Results = new Queue<Func<CancellationToken, Task<string>>>();
            public readonly List<Call> Calls = new List<Call>();
            public Task<string> TranscribeAsync(string path, string language, string prompt, CancellationToken cancellation)
            {
                Calls.Add(new Call { Language = language, Prompt = prompt, Cancellation = cancellation });
                return Results.Count > 0 ? Results.Dequeue()(cancellation) : Task.FromResult("測試文字");
            }
        }
        private sealed class Delivery : ITextDelivery
        {
            public event EventHandler<CorrectionEventArgs> CorrectionObserved { add { } remove { } }
            public FocusSnapshot Captured = new FocusSnapshot { CanPaste = true }, Target;
            public Task<FocusSnapshot> CaptureGate; public string Text; public int Count;
            public InsertionResult Result = new InsertionResult { Copied = true, PasteSent = true, PasteVerified = true };
            public Task<FocusSnapshot> CaptureAsync() { return CaptureGate ?? Task.FromResult(Captured); }
            public Task<InsertionResult> DeliverAsync(string text, FocusSnapshot target, CancellationToken cancellation)
            { Count++; Text = text; Target = target; return Task.FromResult(Result); }
            public Task<bool> RevalidateCorrectionAsync() { return Task.FromResult(true); }
            public void StopObserving() { }
            public void Dispose() { }
        }
    }
}
