using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Neighbor.Core;

namespace Neighbor.Windows.Platform
{
    public sealed class WindowsCredentialStore : ICredentialStore
    {
        public const string DefaultTarget = "WhatsUpMyNeighbor/GroqApiKey";
        private readonly string target;
        public WindowsCredentialStore(string target = DefaultTarget)
        {
            this.target = target ?? throw new ArgumentNullException(nameof(target));
        }

        public string Read()
        {
            if (!CredRead(target, 1, 0, out var pointer))
            {
                int code = Marshal.GetLastWin32Error();
                if (code == 1168) return "";
                throw new Win32Exception(code, "無法讀取 Windows 認證管理員。");
            }
            try
            {
                var credential = (Credential)Marshal.PtrToStructure(pointer, typeof(Credential));
                if (credential.BlobSize > 5120 || credential.BlobSize % 2 != 0)
                    throw new InvalidOperationException("已儲存的 API Key 格式無效，請重新設定。");
                return Marshal.PtrToStringUni(credential.Blob, checked((int)credential.BlobSize / 2)) ?? "";
            }
            finally { CredFree(pointer); }
        }

        public void Write(string key)
        {
            if (string.IsNullOrWhiteSpace(key)) { Delete(); return; }
            var bytes = Encoding.Unicode.GetBytes(key.Trim());
            if (bytes.Length > 5120) { Array.Clear(bytes, 0, bytes.Length); throw new ArgumentException("API Key 過長。"); }
            var pointer = Marshal.AllocHGlobal(bytes.Length);
            try
            {
                Marshal.Copy(bytes, 0, pointer, bytes.Length);
                var credential = new Credential {
                    Type = 1, Target = target, Blob = pointer, BlobSize = (uint)bytes.Length,
                    Persist = 2, UserName = Environment.UserName
                };
                if (!CredWrite(ref credential, 0))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "無法儲存至 Windows 認證管理員。");
            }
            finally
            {
                Array.Clear(bytes, 0, bytes.Length);
                Marshal.Copy(bytes, 0, pointer, bytes.Length);
                Marshal.FreeHGlobal(pointer);
            }
        }

        public void Delete()
        {
            if (!CredDelete(target, 1, 0) && Marshal.GetLastWin32Error() != 1168)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "無法刪除 Windows 認證管理員中的 API Key。");
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct Credential
        {
            public uint Flags, Type;
            public string Target, Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public uint BlobSize;
            public IntPtr Blob;
            public uint Persist, AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias, UserName;
        }
        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);
        [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredWrite(ref Credential credential, uint flags);
        [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredDelete(string target, uint type, uint flags);
        [DllImport("advapi32.dll")] private static extern void CredFree(IntPtr credential);
    }
}
