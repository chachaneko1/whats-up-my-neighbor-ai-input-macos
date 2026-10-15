using Microsoft.Win32;
using System.Windows.Forms;

namespace Neighbor.Windows.Platform
{
    public static class LoginStartup
    {
        public static void Apply(bool enabled)
        {
            using (var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
            {
                if (enabled) key.SetValue("WhatsUpMyNeighbor", "\"" + Application.ExecutablePath + "\"");
                else key.DeleteValue("WhatsUpMyNeighbor", false);
            }
        }
    }
}
