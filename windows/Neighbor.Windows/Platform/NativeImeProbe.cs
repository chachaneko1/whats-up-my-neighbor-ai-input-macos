using UIA = Interop.UIAutomationClient;

namespace Neighbor.Windows.Platform
{
    internal static class NativeImeProbe
    {
        internal static bool TryRead(int[] expectedRuntimeId, out bool active)
        {
            active = false;
            try
            {
                var element = NativeTextAccess.FocusedElement(expectedRuntimeId);
                var pattern = element?.GetCurrentPattern(UIA.UIA_PatternIds.UIA_TextEditPatternId) as UIA.IUIAutomationTextEditPattern;
                if (pattern == null) return false;
                // Only inspect existence of an active composition; never read its text.
                active = pattern.GetActiveComposition() != null;
                return true;
            }
            catch { return false; }
        }
    }
}
