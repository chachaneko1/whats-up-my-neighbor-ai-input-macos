using System;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Automation.Text;
using UIA = Interop.UIAutomationClient;

namespace Neighbor.Windows.Platform
{
    // All access is confined to WindowsTextDelivery's MTA worker. Use the current
    // UIA COM interface directly: net48's deprecated HTextRange/VARIANT bridge can
    // return invalid range handles on supported Windows installations.
    internal static class NativeTextAccess
    {
        [ThreadStatic] private static UIA.IUIAutomation client;
        internal static UIA.IUIAutomation Client
        {
            get
            {
                if (client != null) return client;
                var created = (UIA.IUIAutomation)new UIA.CUIAutomation8();
                var settings = (UIA.IUIAutomation2)created;
                settings.ConnectionTimeout = 1000;
                settings.TransactionTimeout = 1000;
                client = created;
                return client;
            }
        }
        internal static UIA.IUIAutomationElement FocusedElement(int[] expectedRuntimeId)
        {
            var element = Client.GetFocusedElement();
            var actual = element?.GetRuntimeId();
            return actual != null && actual.SequenceEqual(expectedRuntimeId) ? element : null;
        }
        internal static NativeTextPattern Pattern(int[] expectedRuntimeId)
        {
            var element = FocusedElement(expectedRuntimeId);
            if (element == null) return null;
            var pattern = element.GetCurrentPattern(UIA.UIA_PatternIds.UIA_TextPatternId) as UIA.IUIAutomationTextPattern;
            return pattern == null ? null : new NativeTextPattern(Client, element, pattern);
        }
        internal static void ReleaseCurrentClient()
        {
            // Called only when the worker's queue has drained and no operation can
            // use this apartment again. Individual range RCWs use CLR lifetimes.
            var existing = client; client = null;
            if (existing != null) Marshal.ReleaseComObject(existing);
        }
    }

    internal sealed class NativeTextPattern
    {
        private readonly UIA.IUIAutomation client;
        private readonly UIA.IUIAutomationElement element;
        private readonly UIA.IUIAutomationTextPattern pattern;
        internal NativeTextPattern(UIA.IUIAutomation client, UIA.IUIAutomationElement element, UIA.IUIAutomationTextPattern pattern)
        { this.client = client; this.element = element; this.pattern = pattern; }
        internal NativeTextRange[] GetSelection()
        {
            var selections = pattern.GetSelection();
            int count = selections?.Length ?? 0;
            if (count < 0 || count > 256) throw new InvalidOperationException("Unexpected selection count.");
            var result = new NativeTextRange[count];
            for (int index = 0; index < count; index++) result[index] = new NativeTextRange(this, selections.GetElement(index));
            return result;
        }
        internal NativeTextRange DocumentRange => new NativeTextRange(this, pattern.DocumentRange);
    }

    internal sealed class NativeTextRange
    {
        private readonly NativeTextPattern owner;
        private readonly UIA.IUIAutomationTextRange range;
        internal NativeTextRange(NativeTextPattern owner, UIA.IUIAutomationTextRange range)
        { this.owner = owner; this.range = range ?? throw new InvalidOperationException("Text range unavailable."); }
        internal NativeTextRange Clone() => new NativeTextRange(owner, range.Clone());
        internal bool Compare(NativeTextRange other) => range.Compare(other.range) != 0;
        internal int CompareEndpoints(TextPatternRangeEndpoint endpoint, NativeTextRange other, TextPatternRangeEndpoint targetEndpoint)
            => range.CompareEndpoints((UIA.TextPatternRangeEndpoint)endpoint, other.range, (UIA.TextPatternRangeEndpoint)targetEndpoint);
        internal void MoveEndpointByRange(TextPatternRangeEndpoint endpoint, NativeTextRange other, TextPatternRangeEndpoint targetEndpoint)
            => range.MoveEndpointByRange((UIA.TextPatternRangeEndpoint)endpoint, other.range, (UIA.TextPatternRangeEndpoint)targetEndpoint);
        internal int MoveEndpointByUnit(TextPatternRangeEndpoint endpoint, TextUnit unit, int count)
            => range.MoveEndpointByUnit((UIA.TextPatternRangeEndpoint)endpoint, (UIA.TextUnit)unit, count);
        internal int Move(TextUnit unit, int count) => range.Move((UIA.TextUnit)unit, count);
        internal object GetAttributeValue(int attribute) => range.GetAttributeValue(attribute);
        internal string GetText(int maxLength)
        {
            if (maxLength < 0 || maxLength > 4225) throw new ArgumentOutOfRangeException(nameof(maxLength));
            return range.GetText(maxLength);
        }
    }
}
