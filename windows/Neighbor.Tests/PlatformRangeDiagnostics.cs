using System;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Automation;

namespace Neighbor.Tests
{
    // Test-only A/B probe. It runs only against the PID of our isolated fixture,
    // prints API status/lengths, and never emits control text or exception messages.
    internal static class PlatformRangeDiagnostics
    {
        internal static void Run(int fixtureProcessId, string label)
        {
            var thread = new Thread(() =>
            {
                int initialized = CoInitializeEx(IntPtr.Zero, 0);
                try
                {
                    var element = AutomationElement.FocusedElement;
                    if (element == null || element.Current.ProcessId != fixtureProcessId)
                    { Console.WriteLine(label + " range probe: fixture focus absent"); return; }
                    var runtimeId = element.GetRuntimeId();
                    // The prior diagnostic run proved the net48 legacy range bridge
                    // can raise AccessViolation in RawTextRange_GetText. Do not call
                    // that bridge again, even against an isolated fixture.
                    ProbeNative(runtimeId, label);
                }
                catch (Exception error) { Failure(label, "setup", error); }
                finally { if (initialized >= 0) CoUninitialize(); }
            }) { IsBackground = true, Name = "Neighbor.RangeProbe" };
            thread.SetApartmentState(ApartmentState.MTA); thread.Start();
            if (!thread.Join(8000)) Console.WriteLine(label + " range probe: timed out");
        }

        private static void ProbeNative(int[] expectedRuntimeId, string label)
        {
            IAutomation automation = null; IElement element = null; ITextPattern pattern = null;
            IRangeArray ranges = null; IRange selection = null, clone = null, document = null;
            try
            {
                automation = (IAutomation)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("e22ad333-b25f-460c-83d0-0581107395c9"), true));
                Marshal.ThrowExceptionForHR(automation.GetFocusedElement(out element));
                Marshal.ThrowExceptionForHR(element.GetRuntimeId(out var actualRuntimeId));
                if (!actualRuntimeId.SequenceEqual(expectedRuntimeId)) { Console.WriteLine(label + " native probe: focus changed"); return; }
                var iid = typeof(ITextPattern).GUID;
                Marshal.ThrowExceptionForHR(element.GetCurrentPatternAs(10014, ref iid, out pattern));
                Probe(label, "native.selection", () =>
                {
                    Marshal.ThrowExceptionForHR(pattern.GetSelection(out ranges));
                    if (ranges == null) return "count=0";
                    Marshal.ThrowExceptionForHR(ranges.GetLength(out int length));
                    if (length == 1) Marshal.ThrowExceptionForHR(ranges.GetElement(0, out selection));
                    return "count=" + length;
                });
                if (selection != null)
                {
                    Probe(label, "native.selection.endpoints", () =>
                    {
                        Marshal.ThrowExceptionForHR(selection.CompareEndpoints(0, selection, 1, out int comparison));
                        return "comparison=" + comparison;
                    });
                    Probe(label, "native.selection.clone", () => { Marshal.ThrowExceptionForHR(selection.Clone(out clone)); return "created=" + (clone != null); });
                }
                Probe(label, "native.document", () => { Marshal.ThrowExceptionForHR(pattern.GetDocumentRange(out document)); return "created=" + (document != null); });
                if (document != null)
                    Probe(label, "native.document.endpoints", () =>
                    {
                        Marshal.ThrowExceptionForHR(document.CompareEndpoints(0, document, 1, out int comparison));
                        return "comparison=" + comparison;
                    });
            }
            catch (Exception error) { Failure(label, "native.setup", error); }
            finally
            {
                Release(document); Release(clone); Release(selection); Release(ranges);
                Release(pattern); Release(element); Release(automation);
            }
        }
        private static void Probe(string label, string stage, Func<string> run)
        { try { Console.WriteLine(label + " range probe " + stage + ": " + run()); } catch (Exception error) { Failure(label, stage, error); } }
        private static void Failure(string label, string stage, Exception error)
        { Console.WriteLine(label + " range probe " + stage + ": " + error.GetType().Name + " 0x" + error.HResult.ToString("X8")); }
        private static void Release(object value) { if (value != null) Marshal.ReleaseComObject(value); }

        [DllImport("ole32.dll")] private static extern int CoInitializeEx(IntPtr reserved, uint apartment);
        [DllImport("ole32.dll")] private static extern void CoUninitialize();
        [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
        // Method order and GUIDs match Microsoft's UIAutomationClient.h. Only the
        // prefix through the methods exercised by this isolated probe is declared.
        [ComImport, Guid("30cbe57d-d9d0-452a-ab13-7ac5ac4825ee"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAutomation
        {
            [PreserveSig] int CompareElements(IntPtr first, IntPtr second, out int same);
            [PreserveSig] int CompareRuntimeIds(IntPtr first, IntPtr second, out int same);
            [PreserveSig] int GetRootElement(out IntPtr root);
            [PreserveSig] int ElementFromHandle(IntPtr window, out IntPtr element);
            [PreserveSig] int ElementFromPoint(Point point, out IntPtr element);
            [PreserveSig] int GetFocusedElement([MarshalAs(UnmanagedType.Interface)] out IElement element);
        }
        [ComImport, Guid("d22108aa-8ac5-49a5-837b-37bbb3d7591e"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IElement
        {
            [PreserveSig] int SetFocus();
            [PreserveSig] int GetRuntimeId([MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_I4)] out int[] runtimeId);
            [PreserveSig] int FindFirst(int scope, IntPtr condition, out IntPtr found);
            [PreserveSig] int FindAll(int scope, IntPtr condition, out IntPtr found);
            [PreserveSig] int FindFirstBuildCache(int scope, IntPtr condition, IntPtr request, out IntPtr found);
            [PreserveSig] int FindAllBuildCache(int scope, IntPtr condition, IntPtr request, out IntPtr found);
            [PreserveSig] int BuildUpdatedCache(IntPtr request, out IntPtr updated);
            [PreserveSig] int GetCurrentPropertyValue(int property, out IntPtr value);
            [PreserveSig] int GetCurrentPropertyValueEx(int property, int ignoreDefault, out IntPtr value);
            [PreserveSig] int GetCachedPropertyValue(int property, out IntPtr value);
            [PreserveSig] int GetCachedPropertyValueEx(int property, int ignoreDefault, out IntPtr value);
            [PreserveSig] int GetCurrentPatternAs(int patternId, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out ITextPattern pattern);
        }
        [ComImport, Guid("32eba289-3583-42c9-9c59-3b6d9a1e9b6a"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface ITextPattern
        {
            [PreserveSig] int RangeFromPoint(Point point, out IntPtr range);
            [PreserveSig] int RangeFromChild(IntPtr child, out IntPtr range);
            [PreserveSig] int GetSelection([MarshalAs(UnmanagedType.Interface)] out IRangeArray ranges);
            [PreserveSig] int GetVisibleRanges(out IntPtr ranges);
            [PreserveSig] int GetDocumentRange([MarshalAs(UnmanagedType.Interface)] out IRange range);
        }
        [ComImport, Guid("ce4ae76a-e717-4c98-81ea-47371d028eb6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IRangeArray
        {
            [PreserveSig] int GetLength(out int length);
            [PreserveSig] int GetElement(int index, [MarshalAs(UnmanagedType.Interface)] out IRange range);
        }
        [ComImport, Guid("a543cc6a-f4ae-494b-8239-c814481187a8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IRange
        {
            [PreserveSig] int Clone([MarshalAs(UnmanagedType.Interface)] out IRange range);
            [PreserveSig] int Compare([MarshalAs(UnmanagedType.Interface)] IRange range, out int same);
            [PreserveSig] int CompareEndpoints(int endpoint, [MarshalAs(UnmanagedType.Interface)] IRange range, int targetEndpoint, out int comparison);
        }
    }
}
