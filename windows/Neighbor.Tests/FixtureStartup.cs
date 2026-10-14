using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Threading;

namespace Neighbor.Tests
{
    /// <summary>Cold process startup has its own budget; UI action assertions keep their shorter waits.</summary>
    internal static class FixtureStartup
    {
        internal static readonly TimeSpan Deadline = TimeSpan.FromSeconds(30);
        private static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(50);

        internal readonly struct State
        {
            internal readonly bool Ready, HasWindow;
            internal readonly int? ExitCode;
            internal State(bool ready, bool hasWindow, int? exitCode = null)
            { Ready = ready; HasWindow = hasWindow; ExitCode = exitCode; }
        }

        internal static void Wait(Process process, string directory, string label)
        {
            if (process == null) throw new InvalidOperationException(label + ": fixture process did not start.");
            var watch = Stopwatch.StartNew();
            Wait(label, () =>
            {
                process.Refresh();
                bool ready = File.Exists(Path.Combine(directory, "ready"));
                if (process.HasExited) return new State(ready, false, process.ExitCode);
                bool hasWindow = process.MainWindowHandle != IntPtr.Zero;
                // A child may exit between reading its window and accepting readiness.
                return new State(ready, hasWindow, process.HasExited ? (int?)process.ExitCode : null);
            }, () => watch.Elapsed, delay => Thread.Sleep(delay));
            Console.WriteLine(label + ": startup ready after " + watch.Elapsed.TotalSeconds.ToString("0.000", CultureInfo.InvariantCulture) + "s.");
        }

        internal static void Wait(string label, Func<State> readState, Func<TimeSpan> elapsed, Action<TimeSpan> sleep)
        {
            while (true)
            {
                var state = readState();
                var duration = elapsed();
                string detail = string.Format(CultureInfo.InvariantCulture,
                    "{0}: startup elapsed={1:0.000}s; ready={2}; window={3}; process={4}",
                    label, duration.TotalSeconds, state.Ready, state.HasWindow,
                    state.ExitCode.HasValue ? "exited; exitCode=" + state.ExitCode.Value : "running");
                if (state.ExitCode.HasValue)
                    throw new InvalidOperationException("Fixture exited before startup completed. " + detail);
                if (duration >= Deadline)
                    throw new TimeoutException("Fixture startup deadline (30s) exceeded. " + detail);
                if (state.Ready && state.HasWindow) return;
                var remaining = Deadline - duration;
                sleep(remaining < PollInterval ? remaining : PollInterval);
            }
        }
    }
}
