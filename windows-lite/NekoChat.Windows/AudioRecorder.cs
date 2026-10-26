using NAudio.Wave;
using System.IO;

namespace NekoChat.Windows;

internal sealed class AudioRecorder : IDisposable
{
    private readonly MemoryStream stream=new();
    private readonly WaveInEvent input=new() { WaveFormat=new WaveFormat(16000,16,1), BufferMilliseconds=100 };
    private readonly WaveFileWriter writer;
    private readonly TaskCompletionSource<byte[]> stopped=new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int stopping;
    private int disposed;
    internal AudioRecorder()
    {
        writer=new WaveFileWriter(stream,input.WaveFormat);
        input.DataAvailable+=(_,e)=> {
            if (Volatile.Read(ref stopping)==0 && stream.Length < 2_100_000) writer.Write(e.Buffer,0,e.BytesRecorded);
        };
        input.RecordingStopped+=(_,e)=> {
            writer.Flush();
            if(e.Exception is not null) stopped.TrySetException(new IOException("無法錄音，請檢查麥克風權限與裝置。"));
            else { writer.Dispose(); stopped.TrySetResult(stream.ToArray()); }
        };
    }
    internal void Start()=>input.StartRecording();
    internal async Task<byte[]> StopAsync()
    {
        if (Interlocked.Exchange(ref stopping,1)==0) input.StopRecording();
        return await stopped.Task.WaitAsync(TimeSpan.FromSeconds(5));
    }
    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed,1)!=0) return;
        Interlocked.Exchange(ref stopping,1);
        input.Dispose(); writer.Dispose(); stream.Dispose();
    }
}
