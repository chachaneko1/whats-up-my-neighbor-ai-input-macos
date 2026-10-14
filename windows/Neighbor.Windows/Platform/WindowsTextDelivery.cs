using System;
using System.Collections.Concurrent;
using System.Globalization;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Automation;
using System.Windows.Automation.Text;
using System.Windows.Forms;
using Neighbor.Core;

namespace Neighbor.Windows.Platform
{
    /// <summary>UI Automation objects stay on one MTA worker; clipboard calls stay on a separate STA.</summary>
    public sealed class WindowsTextDelivery : ITextDelivery
    {
        private sealed class Target
        {
            public IntPtr Window, FocusWindow;
            public uint ProcessId, ThreadId;
            public AutomationElement Element;
            public int[] RuntimeId;
            public TextPattern TextPattern;
            public TextPatternRange Selection;
        }
        private sealed class Observation
        {
            public Target Target;
            public TextPatternRange Range, Start, End;
            public string Original, Latest;
            public DateTime ExpiresUtc;
            public int Generation, PrefixUnits, SuffixUnits;
        }
        private sealed class InsertionAnchor
        {
            public TextPatternRange PreviousCharacter;
            public bool AtDocumentStart;
        }
        private readonly Worker automation = new Worker(ApartmentState.MTA, "Neighbor.Accessibility");
        private readonly Worker clipboard = new Worker(ApartmentState.STA, "Neighbor.Clipboard");
        private readonly object sendGate = new object();
        private readonly System.Threading.Timer timer;
        private Observation observation;
        private int generation, pollQueued;
        private volatile bool disposed;
        public event EventHandler<CorrectionEventArgs> CorrectionObserved;
        // No message, stack, field value, or text is emitted. The test harness subscribes
        // to identify a failing Windows API stage without logging private content.
        public event Action<string> Diagnostic;
        public WindowsTextDelivery()
        {
            timer = new System.Threading.Timer(_ => QueuePoll(), null, 250, 250);
        }

        public Task<FocusSnapshot> CaptureAsync()
        {
            return Within(automation.Run(() =>
            {
                var snapshot = new FocusSnapshot { CapturedAtUtc = DateTime.UtcNow };
                string stage = "foreground";
                try
                {
                    var window = Native.GetForegroundWindow();
                    uint thread = Native.GetWindowThreadProcessId(window, out uint pid);
                    stage = "focused-element";
                    var element = AutomationElement.FocusedElement;
                    if (window == IntPtr.Zero || element == null || pid == Native.GetCurrentProcessId())
                    { snapshot.Reason = "請先點選要輸入文字的其他程式。"; return snapshot; }
                    stage = "runtime-id";
                    var target = new Target { Window = window, ProcessId = pid, ThreadId = thread, Element = element, RuntimeId = element.GetRuntimeId() };
                    stage = "gui-thread-info";
                    var info = new Native.GuiThreadInfo { Size = Marshal.SizeOf(typeof(Native.GuiThreadInfo)) };
                    if (Native.GetGUIThreadInfo(thread, ref info)) target.FocusWindow = info.Focus;
                    stage = "editable-properties";
                    bool editable = Editable(target);
                    stage = "integrity-level";
                    if (!editable || !Native.HasCompatibleIntegrity(pid))
                    { snapshot.Reason = "無法確認一般文字欄位或輸入權限；完成後請手動貼上。"; return snapshot; }
                    stage = "text-pattern";
                    if (element.TryGetCurrentPattern(TextPattern.Pattern, out var pattern))
                    {
                        try
                        {
                            target.TextPattern = (TextPattern)pattern;
                            stage = "text-selection-read";
                            var selections = target.TextPattern.GetSelection();
                            stage = "text-selection-clone";
                            if (selections.Length == 1) target.Selection = selections[0].Clone();
                        }
                        catch (Exception error)
                        {
                            // Some native controls expose TextPattern but cannot supply
                            // live ranges. Writable ValuePattern is sufficient for paste;
                            // exact range access is mandatory only for verification/learning.
                            ReportFailure("capture.optional-" + stage, error);
                            target.TextPattern = null; target.Selection = null;
                        }
                    }
                    stage = "final-focus-check";
                    if (!SameFocus(target)) { snapshot.Reason = "輸入欄位已變更；完成後請手動貼上。"; return snapshot; }
                    snapshot.Native = target; snapshot.CanPaste = true;
                    snapshot.Reason = target.Selection == null ? "已記住輸入欄位；此程式不提供可靠修字範圍。" : "已記住輸入欄位。";
                }
                catch (Exception error)
                {
                    ReportFailure("capture." + stage, error);
                    snapshot.Reason = "無法驗證目前的輸入欄位；完成後請手動貼上。";
                }
                return snapshot;
            }), 2500, new FocusSnapshot { CapturedAtUtc = DateTime.UtcNow, CanPaste = false, Reason = "輸入欄位未及時回應；完成後請手動貼上。" });
        }

        public async Task<InsertionResult> DeliverAsync(string text, FocusSnapshot target, CancellationToken cancellation)
        {
            StopObserving();
            int ownGeneration = Volatile.Read(ref generation);
            cancellation.ThrowIfCancellationRequested();
            var result = new InsertionResult();
            uint clipboardSequence = 0;
            if (string.IsNullOrEmpty(text)) { result.Message = "沒有可貼上的文字。"; return result; }
            try
            {
                await clipboard.Run(() =>
                {
                    cancellation.ThrowIfCancellationRequested();
                    Clipboard.SetDataObject(new DataObject(DataFormats.UnicodeText, text), true, 5, 50);
                    clipboardSequence = Native.GetClipboardSequenceNumber();
                    return true;
                }).ConfigureAwait(false);
                result.Copied = true;
            }
            catch (OperationCanceledException) { throw; }
            catch { result.Message = "剪貼簿正被其他程式使用，請重試。"; return result; }
            var delivery = automation.Run(() =>
            {
                cancellation.ThrowIfCancellationRequested();
                result.Message = "文字已複製，請在需要的欄位手動貼上。";
                var native = target?.Native as Target;
                if (native == null || target.CanPaste != true || DateTime.UtcNow - target.CapturedAtUtc > TimeSpan.FromMinutes(10) || disposed || ownGeneration != Volatile.Read(ref generation)) return result;
                try
                {
                    if (!SameFocus(native) || !Native.HasCompatibleIntegrity(native.ProcessId) || Native.ModifierHeld()) return result;
                    InsertionAnchor anchor = null;
                    if (native.TextPattern != null && native.Selection != null)
                    {
                        var selected = native.TextPattern.GetSelection();
                        if (selected.Length != 1 || !selected[0].Compare(native.Selection)) return result;
                        anchor = MakeInsertionAnchor(native.TextPattern, selected[0]);
                    }
                    var composition = Native.CompositionState(native);
                    if (composition != Composition.Clear)
                    {
                        result.Message = composition == Composition.Active
                            ? "文字已複製；輸入法仍在組字，請完成組字後手動貼上。"
                            : "文字已複製；無法確認這個程式的輸入法組字狀態，請手動貼上。";
                        return result;
                    }
                    // Recheck immediately before SendInput. We never focus/activate another window.
                    if (!SameFocus(native) || ownGeneration != Volatile.Read(ref generation) || Native.GetClipboardSequenceNumber() != clipboardSequence) return result;
                    lock (sendGate)
                    {
                        cancellation.ThrowIfCancellationRequested();
                        if (ownGeneration != Volatile.Read(ref generation) || Native.GetForegroundWindow() != native.Window) return result;
                        result.PasteSent = Native.Paste();
                    }
                    if (!result.PasteSent) return result;
                    result.Message = "已送出貼上；此程式無法驗證文字範圍，詞典可手動新增。";
                    if (native.TextPattern == null || anchor == null || text.Length > 4096) return result;
                    // Read only the candidate insertion span, never full control text.
                    for (int attempt = 0; attempt < 8; attempt++)
                    {
                        Thread.Sleep(50);
                        cancellation.ThrowIfCancellationRequested();
                        if (!SameFocus(native) || ownGeneration != Volatile.Read(ref generation)) return result;
                        var selected = native.TextPattern.GetSelection();
                        if (selected.Length != 1 || !Collapsed(selected[0])) return result;
                        // A degenerate caret often moves to the end of pasted text. Keep
                        // an anchor at the preceding character instead, without reading it.
                        TextPatternRange inserted;
                        if (anchor.AtDocumentStart)
                        {
                            inserted = native.TextPattern.DocumentRange;
                            inserted.MoveEndpointByRange(TextPatternRangeEndpoint.End, inserted, TextPatternRangeEndpoint.Start);
                        }
                        else
                        {
                            inserted = anchor.PreviousCharacter.Clone();
                            inserted.MoveEndpointByRange(TextPatternRangeEndpoint.End, inserted, TextPatternRangeEndpoint.Start);
                            if (inserted.Move(TextUnit.Character, 1) != 1) return result;
                        }
                        inserted.MoveEndpointByRange(TextPatternRangeEndpoint.End, selected[0], TextPatternRangeEndpoint.Start);
                        if (!Equivalent(inserted.GetText(text.Length + 2), text)) continue;
                        var start = inserted.Clone();
                        start.MoveEndpointByRange(TextPatternRangeEndpoint.End, inserted, TextPatternRangeEndpoint.Start);
                        var end = inserted.Clone();
                        end.MoveEndpointByRange(TextPatternRangeEndpoint.Start, inserted, TextPatternRangeEndpoint.End);
                        result.PasteVerified = true;
                        if (!TryBoundaryCounts(inserted, out int prefixUnits, out int suffixUnits))
                        { result.Message = "已確認貼上；此欄位範圍無法可靠追蹤，詞典可手動新增。"; return result; }
                        observation = new Observation { Target = native, Range = inserted, Start = start, End = end,
                            Original = text, Latest = text, ExpiresUtc = DateTime.UtcNow.AddSeconds(120), Generation = ownGeneration,
                            PrefixUnits = prefixUnits, SuffixUnits = suffixUnits };
                        result.Message = "已確認貼上；兩分鐘內可從這段文字的修正學習詞彙。";
                        break;
                    }
                    return result;
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception error) { ReportFailure("delivery", error); return result; }
            });
            if (await Task.WhenAny(delivery, Task.Delay(3000)).ConfigureAwait(false) == delivery)
                return await delivery.ConfigureAwait(false);
            lock (sendGate) Interlocked.CompareExchange(ref generation, ownGeneration + 1, ownGeneration);
            ObserveFailure(delivery);
            return new InsertionResult { Copied = true, PasteSent = result.PasteSent, PasteVerified = false,
                Message = "文字已複製；輸入欄位未及時回應，請確認內容後再手動貼上。" };
        }

        private static bool Equivalent(string a, string b)
        { return (a ?? "").Replace("\r\n", "\n").Replace('\r', '\n') == (b ?? "").Replace("\r\n", "\n").Replace('\r', '\n'); }
        private static bool Collapsed(TextPatternRange range)
        { return range.CompareEndpoints(TextPatternRangeEndpoint.Start, range, TextPatternRangeEndpoint.End) == 0; }

        private static InsertionAnchor MakeInsertionAnchor(TextPattern pattern, TextPatternRange selection)
        {
            try
            {
                var previous = selection.Clone();
                previous.MoveEndpointByRange(TextPatternRangeEndpoint.End, selection, TextPatternRangeEndpoint.Start);
                if (previous.MoveEndpointByUnit(TextPatternRangeEndpoint.Start, TextUnit.Character, -1) == -1)
                    return new InsertionAnchor { PreviousCharacter = previous };
                // DocumentRange is used only for endpoint metadata; its text is never read.
                if (selection.CompareEndpoints(TextPatternRangeEndpoint.Start, pattern.DocumentRange, TextPatternRangeEndpoint.Start) == 0)
                    return new InsertionAnchor { AtDocumentStart = true };
                return null;
            }
            catch { return null; }
        }
        private static bool TryBoundaryCounts(TextPatternRange range, out int prefixUnits, out int suffixUnits)
        {
            // Endpoint movement obtains only lengths, never surrounding text. It also
            // detects providers that keep stale absolute offsets after a shorter edit,
            // which would otherwise let the tracked range include neighboring text.
            var before = range.Clone();
            before.MoveEndpointByRange(TextPatternRangeEndpoint.End, before, TextPatternRangeEndpoint.Start);
            prefixUnits = -before.MoveEndpointByUnit(TextPatternRangeEndpoint.Start, TextUnit.Character, -8193);
            var after = range.Clone();
            after.MoveEndpointByRange(TextPatternRangeEndpoint.Start, after, TextPatternRangeEndpoint.End);
            suffixUnits = after.MoveEndpointByUnit(TextPatternRangeEndpoint.End, TextUnit.Character, 8193);
            return prefixUnits >= 0 && suffixUnits >= 0 && prefixUnits <= 8192 && suffixUnits <= 8192;
        }

        private static bool Editable(Target target)
        {
            var state = target.Element.Current;
            if (state.IsPassword || !state.IsEnabled || !state.HasKeyboardFocus || (uint)state.ProcessId != target.ProcessId) return false;
            if (state.ControlType != ControlType.Edit && state.ControlType != ControlType.Document) return false;
            if (target.Element.TryGetCurrentPattern(ValuePattern.Pattern, out var value)) return !((ValuePattern)value).Current.IsReadOnly;
            if (target.Element.TryGetCurrentPattern(TextPattern.Pattern, out var text))
            {
                var selections = ((TextPattern)text).GetSelection();
                if (selections.Length != 1) return false;
                var readOnly = selections[0].GetAttributeValue(TextPattern.IsReadOnlyAttribute);
                return readOnly is bool && !(bool)readOnly;
            }
            return false;
        }
        private static bool SameFocus(Target target)
        {
            if (Native.GetForegroundWindow() != target.Window) return false;
            Native.GetWindowThreadProcessId(target.Window, out uint pid);
            if (pid != target.ProcessId) return false;
            var focused = AutomationElement.FocusedElement;
            return focused != null && focused.GetRuntimeId().SequenceEqual(target.RuntimeId) && Editable(target);
        }
        private void QueuePoll()
        {
            if (disposed || Interlocked.CompareExchange(ref pollQueued, 1, 0) != 0) return;
            automation.Run(() =>
            {
                try { Poll(); } finally { Volatile.Write(ref pollQueued, 0); }
                return true;
            });
        }
        private void Poll()
        {
            var current = observation;
            if (current == null) return;
            if (current.Generation != Volatile.Read(ref generation)) { observation = null; return; }
            try
            {
                if (!TryReadObservation(current, out string text, out string reason))
                {
                    if (current.Generation != Volatile.Read(ref generation)) { observation = null; return; }
                    CorrectionObserved?.Invoke(this, new CorrectionEventArgs { IsValid = false, Reason = reason });
                    if (reason != "組字或選取中，暫停詞彙學習。") observation = null;
                    return;
                }
                if (text == current.Latest) return;
                current.Latest = text;
                if (current.Generation == Volatile.Read(ref generation))
                    CorrectionObserved?.Invoke(this, new CorrectionEventArgs { IsValid = true, Original = current.Original, Corrected = text });
            }
            catch
            {
                observation = null;
                CorrectionObserved?.Invoke(this, new CorrectionEventArgs { IsValid = false, Reason = "文字範圍已失效；可手動新增詞彙。" });
            }
        }
        private bool TryReadObservation(Observation current, out string text, out string reason)
        {
            text = null; reason = "已離開原欄位或超過兩分鐘，詞彙學習已停止。";
            if (DateTime.UtcNow > current.ExpiresUtc || !SameFocus(current.Target)) return false;
            var selection = current.Target.TextPattern.GetSelection();
            if (selection.Length != 1) return false;
            if (selection[0].CompareEndpoints(TextPatternRangeEndpoint.Start, current.Range, TextPatternRangeEndpoint.Start) < 0 ||
                selection[0].CompareEndpoints(TextPatternRangeEndpoint.End, current.Range, TextPatternRangeEndpoint.End) > 0) return false;
            if (!Collapsed(selection[0]) || Native.CompositionState(current.Target) != Composition.Clear)
            { reason = "組字或選取中，暫停詞彙學習。"; return false; }
            if (current.Range.CompareEndpoints(TextPatternRangeEndpoint.Start, current.Start, TextPatternRangeEndpoint.Start) != 0 ||
                current.Range.CompareEndpoints(TextPatternRangeEndpoint.End, current.End, TextPatternRangeEndpoint.Start) != 0)
            { reason = "文字範圍邊界無法驗證，詞彙學習已停止。"; return false; }
            if (!TryBoundaryCounts(current.Range, out int prefixUnits, out int suffixUnits) ||
                prefixUnits != current.PrefixUnits || suffixUnits != current.SuffixUnits)
            { reason = "文字範圍邊界已變動，詞彙學習已停止。"; return false; }
            if (!SameFocus(current.Target) || current.Generation != Volatile.Read(ref generation) || DateTime.UtcNow > current.ExpiresUtc)
                return false;
            int limit = Math.Min(4224, current.Original.Length + 128);
            text = current.Range.GetText(limit + 1);
            if (text.Length > limit || text.Length == 0)
            { reason = "文字範圍變更過大，詞彙學習已停止。"; return false; }
            return true;
        }
        public Task<bool> RevalidateCorrectionAsync()
        {
            return Within(automation.Run(() =>
            {
                var current = observation;
                if (current == null || current.Generation != Volatile.Read(ref generation) || disposed) return false;
                try { return TryReadObservation(current, out string text, out _) && text == current.Latest; }
                catch { return false; }
            }), 2000, false);
        }
        public void StopObserving() { lock (sendGate) Interlocked.Increment(ref generation); }
        public void Dispose()
        {
            if (disposed) return;
            disposed = true; StopObserving(); timer.Dispose(); automation.Dispose(); clipboard.Dispose();
        }

        private static async Task<T> Within<T>(Task<T> work, int milliseconds, T fallback)
        {
            if (await Task.WhenAny(work, Task.Delay(milliseconds)).ConfigureAwait(false) == work)
                return await work.ConfigureAwait(false);
            ObserveFailure(work);
            return fallback;
        }
        private static void ObserveFailure(Task task)
        { task.ContinueWith(t => { var ignored = t.Exception; }, TaskContinuationOptions.OnlyOnFaulted); }
        private void ReportFailure(string stage, Exception error)
        {
            try
            {
                string detail = stage;
                for (int depth = 0; error != null && depth < 3; depth++, error = error.InnerException)
                    detail += ": " + error.GetType().FullName + " (0x" + error.HResult.ToString("X8", CultureInfo.InvariantCulture) + ")";
                Diagnostic?.Invoke(detail);
            }
            catch { }
        }

        private sealed class Worker : IDisposable
        {
            private readonly BlockingCollection<Action> queue = new BlockingCollection<Action>();
            public Worker(ApartmentState apartment, string name)
            {
                var thread = new Thread(() => { foreach (var action in queue.GetConsumingEnumerable()) action(); }) { IsBackground = true, Name = name };
                thread.SetApartmentState(apartment); thread.Start();
            }
            public Task<T> Run<T>(Func<T> work)
            {
                var source = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
                try
                {
                    queue.Add(() =>
                    {
                        try { source.TrySetResult(work()); }
                        catch (OperationCanceledException) { source.TrySetCanceled(); }
                        catch (Exception error) { source.TrySetException(error); }
                    });
                }
                catch (InvalidOperationException) { source.TrySetException(new ObjectDisposedException(nameof(WindowsTextDelivery))); }
                return source.Task;
            }
            public void Dispose() { queue.CompleteAdding(); }
        }

        private enum Composition { Clear, Active, Unknown }
        private static class Native
        {
            [StructLayout(LayoutKind.Sequential)] internal struct GuiThreadInfo
            { public int Size, Flags; public IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret; public int Left, Top, Right, Bottom; }
            [StructLayout(LayoutKind.Sequential)] private struct KeyboardInput
            { public ushort Key, Scan; public uint Flags, Time; public UIntPtr ExtraInfo; }
            [StructLayout(LayoutKind.Sequential)] private struct MouseInput
            { public int X, Y; public uint Data, Flags, Time; public UIntPtr ExtraInfo; }
            [StructLayout(LayoutKind.Explicit)] private struct InputUnion
            { [FieldOffset(0)] public KeyboardInput Keyboard; [FieldOffset(0)] public MouseInput Mouse; }
            [StructLayout(LayoutKind.Sequential)] private struct Input { public uint Type; public InputUnion Data; }
            internal static bool ModifierHeld()
            { return new[] { 0x10, 0x11, 0x12, 0x5B, 0x5C }.Any(k => (GetAsyncKeyState(k) & 0x8000) != 0); }
            internal static bool Paste()
            {
                var inputs = new[] { Key(0x11, false), Key(0x56, false), Key(0x56, true), Key(0x11, true) };
                uint sent = SendInput(4, inputs, Marshal.SizeOf(typeof(Input)));
                if (sent > 0 && sent < 4)
                    SendInput(2, new[] { Key(0x56, true), Key(0x11, true) }, Marshal.SizeOf(typeof(Input)));
                return sent == 4;
            }
            private static Input Key(ushort key, bool up)
            { return new Input { Type = 1, Data = new InputUnion { Keyboard = new KeyboardInput { Key = key, Flags = up ? 2u : 0u } } }; }
            internal static Composition CompositionState(Target target)
            {
                int primary = unchecked((int)GetKeyboardLayout(target.ThreadId).ToInt64()) & 0x3FF;
                if (primary != 4 && primary != 17 && primary != 18) return Composition.Clear;
                if (NativeImeProbe.TryRead(target.RuntimeId, out bool active)) return active ? Composition.Active : Composition.Clear;
                var window = target.FocusWindow;
                if (window == IntPtr.Zero) return Composition.Unknown;
                var context = ImmGetContext(window);
                if (context == IntPtr.Zero) return Composition.Unknown;
                try
                {
                    int count = ImmGetCompositionString(context, 8, IntPtr.Zero, 0);
                    return count == 0 ? Composition.Clear : count > 0 ? Composition.Active : Composition.Unknown;
                }
                finally { ImmReleaseContext(window, context); }
            }
            internal static bool HasCompatibleIntegrity(uint pid)
            {
                int own = Integrity(GetCurrentProcessId()), other = Integrity(pid);
                return own >= 0 && other >= 0 && other <= own;
            }
            private static int Integrity(uint pid)
            {
                var process = OpenProcess(0x1000, false, pid);
                if (process == IntPtr.Zero) return -1;
                IntPtr token = IntPtr.Zero, buffer = IntPtr.Zero;
                try
                {
                    if (!OpenProcessToken(process, 8, out token)) return -1;
                    GetTokenInformation(token, 25, IntPtr.Zero, 0, out int size);
                    if (size <= 0 || size > 65536) return -1;
                    buffer = Marshal.AllocHGlobal(size);
                    if (!GetTokenInformation(token, 25, buffer, size, out _)) return -1;
                    var sid = Marshal.ReadIntPtr(buffer);
                    byte count = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
                    return count > 0 ? Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(count - 1))) : -1;
                }
                finally { if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer); if (token != IntPtr.Zero) CloseHandle(token); CloseHandle(process); }
            }
            [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();
            [DllImport("user32.dll")] internal static extern uint GetClipboardSequenceNumber();
            [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
            [DllImport("user32.dll")] internal static extern bool GetGUIThreadInfo(uint thread, ref GuiThreadInfo info);
            [DllImport("kernel32.dll")] internal static extern uint GetCurrentProcessId();
            [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
            [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
            [DllImport("user32.dll")] private static extern IntPtr GetKeyboardLayout(uint thread);
            [DllImport("imm32.dll")] private static extern IntPtr ImmGetContext(IntPtr window);
            [DllImport("imm32.dll")] private static extern bool ImmReleaseContext(IntPtr window, IntPtr context);
            [DllImport("imm32.dll", EntryPoint = "ImmGetCompositionStringW")] private static extern int ImmGetCompositionString(IntPtr context, uint index, IntPtr buffer, uint size);
            [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
            [DllImport("advapi32.dll", SetLastError = true)] private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
            [DllImport("advapi32.dll", SetLastError = true)] private static extern bool GetTokenInformation(IntPtr token, int type, IntPtr information, int length, out int returnedLength);
            [DllImport("advapi32.dll")] private static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
            [DllImport("advapi32.dll")] private static extern IntPtr GetSidSubAuthority(IntPtr sid, uint index);
            [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
        }
    }
}
