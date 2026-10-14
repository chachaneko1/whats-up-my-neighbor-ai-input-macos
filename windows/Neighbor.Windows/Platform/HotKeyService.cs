using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Shortcut = Neighbor.Core.Shortcut;
using Neighbor.Core;

namespace Neighbor.Windows.Platform
{
    public interface IHotKeyRegistrar : IDisposable
    {
        event Action<int> Pressed;
        bool Register(int id, int modifiers, int key);
        void Unregister(int id);
    }

    public sealed class HotKeyService : IDisposable
    {
        private sealed class Binding { public int Id, LogicalId; public Shortcut Shortcut; }
        private readonly IHotKeyRegistrar registrar;
        private List<Binding> bindings = new List<Binding>();
        private int nextId = 100;
        private bool disposed;
        public event Action<int> Pressed;
        public HotKeyService() : this(new NativeRegistrar()) { }
        public HotKeyService(IHotKeyRegistrar registrar)
        {
            this.registrar = registrar ?? throw new ArgumentNullException(nameof(registrar));
            registrar.Pressed += OnPressed;
        }
        private void OnPressed(int id)
        {
            var binding = bindings.FirstOrDefault(x => x.Id == id);
            if (binding != null && !disposed) Pressed?.Invoke(binding.LogicalId);
        }
        public bool TryApply(Shortcut primary, Shortcut secondary, out string error)
        {
            if (disposed) throw new ObjectDisposedException(nameof(HotKeyService));
            error = null;
            if (!Valid(primary) || (secondary != null && !Valid(secondary)))
            { error = "快捷鍵需含 Ctrl、Alt 或 Win，並搭配一般按鍵。"; return false; }
            if (secondary != null && Same(primary, secondary))
            { error = "兩組快捷鍵不能相同；原設定已保留。"; return false; }
            var desired = new[] { primary, secondary };
            var replacement = new List<Binding>();
            var additions = new List<Binding>();
            for (int index = 0; index < desired.Length; index++)
            {
                var shortcut = desired[index];
                if (shortcut == null) continue;
                var existing = bindings.FirstOrDefault(x => Same(x.Shortcut, shortcut));
                var item = new Binding { Id = existing?.Id ?? nextId++, LogicalId = index + 1, Shortcut = shortcut.Clone() };
                if (existing == null)
                {
                    if (!registrar.Register(item.Id, shortcut.Modifiers | 0x4000, shortcut.Key))
                    {
                        foreach (var addition in additions) registrar.Unregister(addition.Id);
                        error = "快捷鍵已被其他程式使用；原設定已保留。";
                        return false;
                    }
                    additions.Add(item);
                }
                replacement.Add(item);
            }
            foreach (var old in bindings.Where(x => replacement.All(n => n.Id != x.Id))) registrar.Unregister(old.Id);
            bindings = replacement;
            return true;
        }
        private static bool Same(Shortcut a, Shortcut b) { return a.Modifiers == b.Modifiers && a.Key == b.Key; }
        private static bool Valid(Shortcut shortcut)
        {
            return shortcut != null && (shortcut.Modifiers & ~15) == 0 && (shortcut.Modifiers & 11) != 0 &&
                shortcut.Key > 0 && shortcut.Key < 255 && shortcut.Key != 0x10 && shortcut.Key != 0x11 &&
                shortcut.Key != 0x12 && shortcut.Key != 0x5B && shortcut.Key != 0x5C && shortcut.Key != 0x7B;
        }
        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            registrar.Pressed -= OnPressed;
            foreach (var binding in bindings) registrar.Unregister(binding.Id);
            bindings.Clear();
            registrar.Dispose();
        }

        private sealed class NativeRegistrar : NativeWindow, IHotKeyRegistrar
        {
            public event Action<int> Pressed;
            public NativeRegistrar() { CreateHandle(new CreateParams { Caption = "Neighbor.Hotkeys", Parent = new IntPtr(-3) }); }
            public bool Register(int id, int modifiers, int key) { return RegisterHotKey(Handle, id, (uint)modifiers, (uint)key); }
            public void Unregister(int id) { UnregisterHotKey(Handle, id); }
            protected override void WndProc(ref Message m)
            {
                if (m.Msg == 0x0312) Pressed?.Invoke(m.WParam.ToInt32());
                base.WndProc(ref m);
            }
            public void Dispose() { DestroyHandle(); }
            [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
            [DllImport("user32.dll", SetLastError = true)] private static extern bool UnregisterHotKey(IntPtr window, int id);
        }
    }
}
