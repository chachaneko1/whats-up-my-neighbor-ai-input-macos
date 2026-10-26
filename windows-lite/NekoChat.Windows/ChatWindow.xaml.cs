using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;

namespace NekoChat.Windows;

public partial class ChatWindow : Window
{
    private Settings settings;
    private bool loaded;
    internal event Action? SendRequested;
    internal event Action? VoiceRequested;
    internal event Action? CancelRequested;
    internal event Action<Settings,string>? ConnectRequested;
    internal event Action? DisconnectRequested;
    internal ChatWindow(Settings initial)
    {
        settings=initial;InitializeComponent();Mode.SelectedIndex=initial.Lan?0:1;
        Endpoint.Text=initial.Endpoint;UserId.Text=initial.User;loaded=true;
        Closing+=OnClosing;
    }
    private void OnClosing(object? sender,CancelEventArgs e){e.Cancel=true;Hide();}
    internal void ShowChat(string? sender=null)
    {
        if(sender is not null){Recipient.Text=sender;Tabs.SelectedIndex=0;}
        Show();if(WindowState==WindowState.Minimized)WindowState=WindowState.Normal;Activate();
    }
    internal void SetStatus(string status)=>Status.Text=status;
    internal void AddHistory(string text)
    {
        History.AppendText(text+Environment.NewLine);
        if(History.Text.Length>24000)History.Text=History.Text[^20000..];
        History.ScrollToEnd();
    }
    private void SendClick(object sender,RoutedEventArgs e)=>SendRequested?.Invoke();
    private void VoiceClick(object sender,RoutedEventArgs e)=>VoiceRequested?.Invoke();
    private void CancelClick(object sender,RoutedEventArgs e)=>CancelRequested?.Invoke();
    private void DisconnectClick(object sender,RoutedEventArgs e)=>DisconnectRequested?.Invoke();
    private void ModeChanged(object sender,SelectionChangedEventArgs e)
    {
        if(!loaded)return;
        // Keep independent LAN/VPS endpoints while switching the selector.
        settings=settings.Lan?settings with{LanEndpoint=Endpoint.Text}:settings with{VpsEndpoint=Endpoint.Text};
        settings=settings with{Lan=Mode.SelectedIndex==0};Endpoint.Text=settings.Endpoint;
    }
    private void ConnectClick(object sender,RoutedEventArgs e)
    {
        settings=settings with{Lan=Mode.SelectedIndex==0,User=UserId.Text.Trim()};
        settings=settings.Lan?settings with{LanEndpoint=Endpoint.Text.Trim()}:settings with{VpsEndpoint=Endpoint.Text.Trim()};
        var token=RelayToken.Password;RelayToken.Clear();ConnectRequested?.Invoke(settings,token);
    }
    private void SaveGroqClick(object sender,RoutedEventArgs e)
    {
        try {
            if(string.IsNullOrWhiteSpace(GroqKey.Password))throw new ArgumentException("請先輸入自己的 Groq Key。");
            CredentialStore.Save(CredentialStore.Groq,GroqKey.Password.Trim());SetStatus("Groq Key 已存入 Windows 認證管理員。");
        }catch(Exception ex){SetStatus(App.SafeError(ex));}finally{GroqKey.Clear();}
    }
    private void DeleteGroqClick(object sender,RoutedEventArgs e)
    {
        try{CredentialStore.Delete(CredentialStore.Groq);GroqKey.Clear();SetStatus("Groq Key 已刪除。");}catch(Exception ex){SetStatus(App.SafeError(ex));}
    }
    private void DeleteRelayClick(object sender,RoutedEventArgs e)
    {
        try{CredentialStore.Delete(CredentialStore.Relay(Endpoint.Text.Trim(),UserId.Text.Trim()));RelayToken.Clear();SetStatus("已刪除此連線的憑證；現有連線請另按中斷。");}catch(Exception ex){SetStatus(App.SafeError(ex));}
    }
    private void CopyClick(object sender,RoutedEventArgs e)
    {
        if(Transcript.Text.Length>0)SetStatus(NativeInput.Copy(Transcript.Text));
    }
}
