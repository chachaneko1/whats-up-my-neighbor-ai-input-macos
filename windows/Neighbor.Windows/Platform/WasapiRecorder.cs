using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Neighbor.Core;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace Neighbor.Windows.Platform
{
    public sealed class WasapiRecorder : IAudioRecorder
    {
        private sealed class Session
        {
            public readonly object Sync = new object();
            public WasapiCapture Capture;
            public MMDevice Device;
            public WaveFileWriter Writer;
            public CancellationTokenRegistration Cancellation;
            public readonly TaskCompletionSource<bool> Stopped = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            public readonly TaskCompletionSource<bool> FirstData = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            public bool StopRequested, Finished;
        }
        private readonly SemaphoreSlim gate = new SemaphoreSlim(1, 1);
        private Session current;
        private bool disposed;
        public event EventHandler<AudioLevelEventArgs> LevelChanged;
        public event EventHandler StoppedUnexpectedly;

        public IReadOnlyList<AudioDevice> GetDevices()
        {
            var result = new List<AudioDevice>();
            using (var enumerator = new MMDeviceEnumerator())
            {
                foreach (var device in enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active))
                    using (device) result.Add(new AudioDevice { Id = device.ID, Name = device.FriendlyName });
            }
            return result;
        }

        public async Task StartAsync(string path, string deviceId, CancellationToken cancellation)
        {
            await gate.WaitAsync(cancellation).ConfigureAwait(false);
            try
            {
                if (disposed) throw new ObjectDisposedException(nameof(WasapiRecorder));
                if (current != null && !current.Stopped.Task.IsCompleted) throw new InvalidOperationException("錄音尚未結束。");
                // Construct on the pool so NAudio does not capture the WinForms sync context.
                // RecordingStopped can then always complete while the UI is shutting down.
                var started = await Task.Run(() =>
                {
                    cancellation.ThrowIfCancellationRequested();
                    var session = new Session();
                    try
                    {
                        using (var enumerator = new MMDeviceEnumerator())
                            session.Device = string.IsNullOrWhiteSpace(deviceId)
                                ? enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Communications)
                                : enumerator.GetDevice(deviceId);
                        session.Capture = new WasapiCapture(session.Device, false, 50) { WaveFormat = new WaveFormat(16000, 16, 1) };
                        session.Writer = new WaveFileWriter(path, session.Capture.WaveFormat);
                        session.Capture.DataAvailable += (sender, args) => DataAvailable(session, args);
                        session.Capture.RecordingStopped += (sender, args) => Finish(session, args.Exception);
                        current = session;
                        session.Capture.StartRecording();
                        var registration = cancellation.Register(() => RequestStop(session));
                        bool alreadyFinished;
                        lock (session.Sync)
                        {
                            alreadyFinished = session.Finished;
                            if (!alreadyFinished) session.Cancellation = registration;
                        }
                        if (alreadyFinished) registration.Dispose();
                        return session;
                    }
                    catch
                    {
                        // StartRecording may fail before its worker exists. Dispose is safe here;
                        // once started, only the stopped callback owns writer/device disposal.
                        if (session.Capture != null) session.Capture.Dispose();
                        session.Writer?.Dispose(); session.Device?.Dispose();
                        session.Stopped.TrySetResult(true);
                        if (ReferenceEquals(current, session)) current = null;
                        throw;
                    }
                }).ConfigureAwait(false);
                // NAudio starts its capture thread asynchronously. Do not report recording
                // ready until a real packet (including digital silence) reached the writer.
                var ready = await Task.WhenAny(started.FirstData.Task, started.Stopped.Task, Task.Delay(3000)).ConfigureAwait(false);
                cancellation.ThrowIfCancellationRequested();
                if (ready != started.FirstData.Task || started.Stopped.Task.IsCompleted)
                {
                    RequestStop(started);
                    await Task.WhenAny(started.Stopped.Task, Task.Delay(5000)).ConfigureAwait(false);
                    throw new InvalidOperationException("麥克風未能開始傳送音訊。請檢查 Windows 麥克風權限與選取的裝置。");
                }
            }
            finally { gate.Release(); }
        }

        private void DataAvailable(Session session, WaveInEventArgs args)
        {
            double squares = 0;
            lock (session.Sync)
            {
                if (session.Finished) return;
                session.Writer.Write(args.Buffer, 0, args.BytesRecorded);
                if (args.BytesRecorded > 0) session.FirstData.TrySetResult(true);
                for (int i = 0; i + 1 < args.BytesRecorded; i += 2)
                {
                    double sample = (short)(args.Buffer[i] | args.Buffer[i + 1] << 8) / 32768d;
                    squares += sample * sample;
                }
            }
            if (args.BytesRecorded > 1)
            {
                double rms = Math.Sqrt(squares / (args.BytesRecorded / 2));
                LevelChanged?.Invoke(this, new AudioLevelEventArgs { Decibels = rms > 0 ? Math.Max(-96, 20 * Math.Log10(rms)) : -96, IsKnown = true });
            }
        }
        private static void RequestStop(Session session)
        {
            lock (session.Sync)
            {
                if (session.Finished || session.StopRequested) return;
                session.StopRequested = true;
                session.Capture.StopRecording();
            }
        }
        private void Finish(Session session, Exception error)
        {
            bool unexpected;
            lock (session.Sync)
            {
                if (session.Finished) return;
                session.Finished = true;
                unexpected = error != null || !session.StopRequested;
            }
            // Cleanup off the callback; cancellation disposal may wait for its callback.
            Task.Run(() =>
            {
                try
                {
                    session.Cancellation.Dispose();
                    session.Writer?.Dispose();
                    session.Capture?.Dispose();
                    session.Device?.Dispose();
                    session.Stopped.TrySetResult(true);
                }
                catch (Exception cleanupError) { session.Stopped.TrySetException(cleanupError); unexpected = true; }
                if (unexpected) StoppedUnexpectedly?.Invoke(this, EventArgs.Empty);
            });
        }

        public async Task StopAsync()
        {
            Session session;
            await gate.WaitAsync().ConfigureAwait(false);
            try { session = current; if (session != null) RequestStop(session); }
            finally { gate.Release(); }
            if (session != null)
            {
                if (await Task.WhenAny(session.Stopped.Task, Task.Delay(5000)).ConfigureAwait(false) != session.Stopped.Task)
                    throw new TimeoutException("麥克風未能正常結束錄音；請關閉程式後重新開啟。");
                await session.Stopped.Task.ConfigureAwait(false);
            }
        }
        public void Dispose()
        {
            gate.Wait();
            try { if (disposed) return; disposed = true; }
            finally { gate.Release(); }
            // Do not dispose native audio objects while callbacks are still active. If
            // a driver never reports RecordingStopped, process exit releases them.
            try { StopAsync().GetAwaiter().GetResult(); } catch (TimeoutException) { }
        }
    }
}
