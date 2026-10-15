using System;

namespace Neighbor.Tests
{
    internal static class FixtureStartupTests
    {
        internal static void Run(Action<bool, string> check)
        {
            var elapsed = TimeSpan.Zero;
            FixtureStartup.Wait("delayed fixture",
                () => new FixtureStartup.State(elapsed >= TimeSpan.FromSeconds(10), elapsed >= TimeSpan.FromSeconds(12)),
                () => elapsed, delay => elapsed += delay);
            check(elapsed == TimeSpan.FromSeconds(12), "fixture startup allows cold readiness beyond the action timeout and requires both signals");

            foreach (var state in new[] { new FixtureStartup.State(false, false),
                new FixtureStartup.State(true, false), new FixtureStartup.State(false, true) })
            {
                elapsed = TimeSpan.Zero;
                Exception failure = null;
                try { FixtureStartup.Wait("incomplete fixture", () => state, () => elapsed, delay => elapsed += delay); }
                catch (Exception error) { failure = error; }
                check(failure is TimeoutException && elapsed == FixtureStartup.Deadline,
                    "fixture startup has a bounded deadline (ready=" + state.Ready + ", window=" + state.HasWindow + ")");
                check(failure != null && failure.Message.Contains("ready=" + state.Ready) &&
                    failure.Message.Contains("window=" + state.HasWindow) && failure.Message.Contains("process=running") &&
                    failure.Message.Contains("elapsed=30.000s"), "fixture timeout identifies the missing readiness signal");
            }

            elapsed = TimeSpan.Zero;
            Exception exited = null;
            // Already-exited children must never be accepted even if a ready file and window were observed.
            try { FixtureStartup.Wait("exited fixture", () => new FixtureStartup.State(true, true, 17), () => elapsed, _ => elapsed += TimeSpan.FromSeconds(1)); }
            catch (Exception error) { exited = error; }
            check(exited is InvalidOperationException && elapsed == TimeSpan.Zero && exited.Message.Contains("exitCode=17"),
                "fixture startup fails immediately for an exited process despite readiness signals");

            elapsed = TimeSpan.Zero;
            exited = null;
            try
            {
                FixtureStartup.Wait("exiting fixture", () => new FixtureStartup.State(false, false,
                    elapsed >= TimeSpan.FromSeconds(1) ? (int?)23 : null), () => elapsed, delay => elapsed += delay);
            }
            catch (Exception error) { exited = error; }
            check(exited is InvalidOperationException && elapsed == TimeSpan.FromSeconds(1) && exited.Message.Contains("exitCode=23"),
                "fixture startup detects an early exit without waiting for the deadline");

            Exception late = null;
            try { FixtureStartup.Wait("late fixture", () => new FixtureStartup.State(true, true), () => FixtureStartup.Deadline + TimeSpan.FromMilliseconds(1), _ => { }); }
            catch (Exception error) { late = error; }
            check(late is TimeoutException, "fixture readiness after the deadline cannot pass");
        }
    }
}
