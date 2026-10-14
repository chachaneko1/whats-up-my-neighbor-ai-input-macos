using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Neighbor.Core
{
    /// <summary>Call public operations on one synchronization context (the UI thread).
    /// Each job captures settings and owns its cancellation token. Adapters own I/O.</summary>
    public sealed class DictationCoordinator
    {
        private sealed class Job
        {
            public string Path;
            public AppSettings Settings;
            public FocusSnapshot Target;
            public CancellationTokenSource Cancellation = new CancellationTokenSource();
            public Task Startup = Task.CompletedTask;
            public Task Finalization;
            public DateTime StartedUtc, LastLoudUtc, LastLevelUtc, RetainUntilUtc;
            public bool LevelKnown;
        }
        private readonly IAudioRecorder recorder;
        private readonly ITranscriber transcriber;
        private readonly ITextDelivery delivery;
        private readonly ITextNormalizer normalizer;
        private readonly TemporaryAudioStore storage;
        private readonly VocabularyStore vocabulary;
        private readonly Func<DateTime> now;
        private readonly SynchronizationContext context;
        private Job job;
        public DictationState State { get; private set; } = DictationState.Idle;
        public string Status { get; private set; } = "準備好了";
        public event EventHandler<StatusEventArgs> StatusChanged;
        public event EventHandler<AudioLevelEventArgs> LevelChanged;
        public event Action<VocabularyPrompt> PromptChanged;
        public event Action<InsertionResult> Delivered;
        public DictationCoordinator(IAudioRecorder recorder, ITranscriber transcriber, ITextDelivery delivery,
            ITextNormalizer normalizer, TemporaryAudioStore storage, VocabularyStore vocabulary, Func<DateTime> now = null)
        {
            this.recorder = recorder; this.transcriber = transcriber; this.delivery = delivery;
            this.normalizer = normalizer; this.storage = storage; this.vocabulary = vocabulary;
            this.now = now ?? (() => DateTime.UtcNow); context = SynchronizationContext.Current;
            recorder.LevelChanged += OnLevel;
            recorder.StoppedUnexpectedly += OnRecorderFailure;
        }
        public Task ToggleAsync(AppSettings settings, bool alternate = false)
        {
            if (State == DictationState.Recording) return StopAsync();
            if (State == DictationState.Idle || State == DictationState.RetainedAudio) return StartAsync(settings, alternate);
            return Task.CompletedTask;
        }
        public Task StartAsync(AppSettings settings, bool alternate = false)
        {
            if (State != DictationState.Idle && State != DictationState.RetainedAudio) return Task.CompletedTask;
            SettingsStore.Validate(settings);
            if (job != null) { job.Cancellation.Cancel(); storage.Remove(job.Path); }
            delivery.StopObserving();
            var current = new Job { Path = storage.CreatePath(), Settings = settings.Clone() };
            if (alternate) current.Settings.Mode = settings.AlternateMode;
            job = current;
            SetState(DictationState.Starting, "正在準備麥克風…");
            current.Startup = BeginAsync(current);
            return current.Startup;
        }
        private async Task BeginAsync(Job current)
        {
            try
            {
                current.Target = await delivery.CaptureAsync();
                if (!IsCurrent(current)) return;
                await recorder.StartAsync(current.Path, current.Settings.InputDeviceId, current.Cancellation.Token);
                if (!IsCurrent(current)) return;
                current.StartedUtc = current.LastLoudUtc = current.LastLevelUtc = now();
                SetState(DictationState.Recording, "錄音中，再按快捷鍵完成");
            }
            catch (Exception) when (!IsCurrent(current)) { }
            catch (Exception)
            {
                try { await recorder.StopAsync(); } catch { }
                if (IsCurrent(current)) Finish(current, "無法開始錄音。請檢查麥克風連線、選擇及 Windows 麥克風隱私設定。");
            }
        }
        public async Task StopAsync()
        {
            if (State != DictationState.Recording || job == null) return;
            var current = job;
            SetState(DictationState.Finalizing, "正在完成錄音…");
            try
            {
                current.Finalization = recorder.StopAsync();
                await current.Finalization;
                if (!IsCurrent(current)) return;
                if (!storage.IsUsable(current.Path)) { Finish(current, "錄音沒有有效資料，請確認麥克風後重錄。"); return; }
                await RecognizeAsync(current, false);
            }
            catch (Exception) when (!IsCurrent(current)) { }
            catch (Exception) { Finish(current, "錄音未能正常完成，請確認麥克風後重錄。"); }
        }
        private async Task RecognizeAsync(Job current, bool manualRetry)
        {
            SetState(DictationState.Transcribing, "正在辨識…");
            try
            {
                int attempts = current.Settings.AutomaticLanguageRetry && !manualRetry ? 2 : 1;
                for (int attempt = 0; attempt < attempts; attempt++)
                {
                    if (!IsCurrent(current)) return;
                    var prompt = vocabulary.BuildPrompt(LanguagePolicy.BasePrompt(current.Settings.PrimaryLanguage, manualRetry || attempt > 0));
                    PromptChanged?.Invoke(prompt);
                    var text = await transcriber.TranscribeAsync(current.Path, current.Settings.PrimaryLanguage, prompt.Text, current.Cancellation.Token);
                    if (!IsCurrent(current)) return;
                    if (string.IsNullOrWhiteSpace(text)) { Retain(current, "未清楚辨識到語音。可重試或重新錄音。"); return; }
                    if (LanguagePolicy.ShouldIntercept(text, current.Settings))
                    {
                        if (attempt + 1 < attempts) { SetState(DictationState.Transcribing, "語言不符，正在重試一次…"); continue; }
                        Retain(current, "辨識文字不符合允許的語言，已攔截貼上。可重試或重新錄音。"); return;
                    }
                    string processed = TextRules.Process(text.Trim(), current.Settings, normalizer, vocabulary.Entries.Where(e => e.Enabled).Select(e => e.Term));
                    if (string.IsNullOrWhiteSpace(processed)) processed = text.Trim();
                    SetState(DictationState.Delivering, "正在複製文字…");
                    var result = await delivery.DeliverAsync(processed, current.Target, current.Cancellation.Token);
                    if (!IsCurrent(current)) return;
                    if (!result.Copied) { Retain(current, "剪貼簿暫時無法使用，錄音保留兩分鐘，可稍後重試。"); return; }
                    Finish(current, result.Message ?? (result.PasteSent ? "已送出貼上操作" : "已複製，請手動貼上"));
                    Delivered?.Invoke(result);
                    return;
                }
            }
            catch (OperationCanceledException) when (!IsCurrent(current)) { }
            catch (Exception) when (!IsCurrent(current)) { }
            catch (InvalidOperationException error) { Retain(current, error.Message); }
            catch (Exception) { Retain(current, "辨識未完成，請檢查網路與金鑰後重試。"); }
        }
        public Task RetryAsync()
        {
            if (State != DictationState.RetainedAudio || job == null) return Task.CompletedTask;
            if (now() >= job.RetainUntilUtc || !storage.IsUsable(job.Path)) { Finish(job, "暫存錄音已過期，請重新錄音。"); return Task.CompletedTask; }
            return RecognizeAsync(job, true);
        }
        public async Task CancelAsync()
        {
            var old = job;
            delivery.StopObserving();
            if (old == null) { SetState(DictationState.Idle, "已取消"); return; }
            job = null; old.Cancellation.Cancel();
            SetState(DictationState.Finalizing, "正在取消…");
            try { await old.Startup; } catch { }
            try { if (old.Finalization != null) await old.Finalization; else await recorder.StopAsync(); } catch { }
            storage.Remove(old.Path);
            SetState(DictationState.Idle, "已取消");
        }
        public Task TickAsync()
        {
            if (job == null) return Task.CompletedTask;
            var current = job;
            if (State == DictationState.RetainedAudio && now() >= current.RetainUntilUtc) { Finish(current, "暫存錄音已清除"); return Task.CompletedTask; }
            if (State != DictationState.Recording) return Task.CompletedTask;
            if ((now() - current.StartedUtc).TotalSeconds >= 300) return StopAsync();
            // Unknown/missing metering is not silence; reset the timer instead of truncating speech.
            if (!current.LevelKnown || (now() - current.LastLevelUtc).TotalSeconds > 1) { current.LastLoudUtc = now(); return Task.CompletedTask; }
            if (current.Settings.SilenceSeconds > 0 && (now() - current.LastLoudUtc).TotalSeconds >= current.Settings.SilenceSeconds) return StopAsync();
            return Task.CompletedTask;
        }
        private void OnLevel(object sender, AudioLevelEventArgs e)
        {
            Dispatch(() => {
                if (State != DictationState.Recording || job == null) return;
                job.LevelKnown = e.IsKnown; job.LastLevelUtc = now();
                if (!e.IsKnown || e.Decibels > -45) job.LastLoudUtc = now();
                LevelChanged?.Invoke(this, e);
            });
        }
        private void OnRecorderFailure(object sender, EventArgs e)
        {
            Dispatch(async () => {
                if (job == null || (State != DictationState.Recording && State != DictationState.Starting)) return;
                await CancelAsync(); SetState(DictationState.Idle, "麥克風中斷，請重新選擇裝置後錄音。");
            });
        }
        private void Dispatch(Action action) { if (context == null || SynchronizationContext.Current == context) action(); else context.Post(_ => action(), null); }
        private bool IsCurrent(Job current) { return ReferenceEquals(job, current) && !current.Cancellation.IsCancellationRequested; }
        private void Retain(Job current, string message)
        {
            if (!IsCurrent(current)) return;
            if (!storage.IsUsable(current.Path)) { Finish(current, message); return; }
            current.RetainUntilUtc = now().AddMinutes(2);
            SetState(DictationState.RetainedAudio, message + "（錄音暫留兩分鐘）");
        }
        private void Finish(Job current, string message)
        {
            if (!ReferenceEquals(job, current)) return;
            job = null; storage.Remove(current.Path); SetState(DictationState.Idle, message);
        }
        private void SetState(DictationState state, string message)
        {
            State = state; Status = message;
            StatusChanged?.Invoke(this, new StatusEventArgs { State = state, Message = message });
        }
    }
}
