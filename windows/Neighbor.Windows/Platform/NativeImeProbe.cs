using System;
using System.Linq;
using System.Runtime.InteropServices;

namespace Neighbor.Windows.Platform
{
    // The net48 managed UIA facade predates TextEditPattern. This small COM projection
    // follows Microsoft's UIAutomationClient.h vtable order through the methods used.
    // It asks only whether a composition exists and never reads its text.
    internal static class NativeImeProbe
    {
        internal static bool TryRead(int[] expectedRuntimeId, out bool active)
        {
            active = false;
            IAutomationProbe automation = null;
            IElementProbe element = null;
            ITextEditProbe textEdit = null;
            IntPtr range = IntPtr.Zero;
            try
            {
                automation = (IAutomationProbe)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("e22ad333-b25f-460c-83d0-0581107395c9"), true));
                if (automation.GetFocusedElement(out element) < 0 || element == null) return false;
                if (element.GetRuntimeId(out var runtimeId) < 0 || runtimeId == null || !runtimeId.SequenceEqual(expectedRuntimeId)) return false;
                var iid = new Guid("17e21576-996c-4870-99d9-bff323380c06");
                if (element.GetCurrentPatternAs(10032, ref iid, out textEdit) < 0 || textEdit == null) return false;
                if (textEdit.GetActiveComposition(out range) < 0) return false;
                active = range != IntPtr.Zero;
                return true;
            }
            catch { return false; }
            finally
            {
                if (range != IntPtr.Zero) Marshal.Release(range);
                if (textEdit != null) Marshal.ReleaseComObject(textEdit);
                if (element != null) Marshal.ReleaseComObject(element);
                if (automation != null) Marshal.ReleaseComObject(automation);
            }
        }

        [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
        [ComImport, Guid("30cbe57d-d9d0-452a-ab13-7ac5ac4825ee"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAutomationProbe
        {
            [PreserveSig] int CompareElements(IntPtr first, IntPtr second, out int same);
            [PreserveSig] int CompareRuntimeIds(IntPtr first, IntPtr second, out int same);
            [PreserveSig] int GetRootElement(out IntPtr root);
            [PreserveSig] int ElementFromHandle(IntPtr window, out IntPtr element);
            [PreserveSig] int ElementFromPoint(Point point, out IntPtr element);
            [PreserveSig] int GetFocusedElement([MarshalAs(UnmanagedType.Interface)] out IElementProbe element);
        }
        [ComImport, Guid("d22108aa-8ac5-49a5-837b-37bbb3d7591e"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IElementProbe
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
            [PreserveSig] int GetCurrentPatternAs(int patternId, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out ITextEditProbe pattern);
        }
        [ComImport, Guid("17e21576-996c-4870-99d9-bff323380c06"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface ITextEditProbe
        {
            [PreserveSig] int RangeFromPoint(Point point, out IntPtr range);
            [PreserveSig] int RangeFromChild(IntPtr child, out IntPtr range);
            [PreserveSig] int GetSelection(out IntPtr ranges);
            [PreserveSig] int GetVisibleRanges(out IntPtr ranges);
            [PreserveSig] int GetDocumentRange(out IntPtr range);
            [PreserveSig] int GetSupportedTextSelection(out int selection);
            [PreserveSig] int GetActiveComposition(out IntPtr range);
            [PreserveSig] int GetConversionTarget(out IntPtr range);
        }
    }
}
