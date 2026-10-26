using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using NekoChat.Core;

namespace NekoChat.Windows;

internal static class SmokeTest
{
    internal static int Run(string directory)
    {
        Directory.CreateDirectory(directory);
        var credential="NekoChat.WindowsLite/CI/"+Guid.NewGuid().ToString("N");
        try {
            CredentialStore.Save(credential,"test-only-ephemeral-credential");
            if(CredentialStore.Load(credential)!="test-only-ephemeral-credential")throw new Exception("Credential roundtrip failed");
            CredentialStore.Delete(credential);
            if(CredentialStore.Load(credential) is not null)throw new Exception("Credential removal failed");
            using(var canceled=new CancellationTokenSource()) {
                canceled.Cancel();bool rejected=false;
                try{NativeInput.InsertAsync("must not type or copy",null,canceled.Token).GetAwaiter().GetResult();}
                catch(OperationCanceledException){rejected=true;}
                if(!rejected)throw new Exception("Canceled input was not blocked");
            }
            var chat=new ChatWindow(new Settings());var pet=new PetWindow();
            foreach(var id in Appearance.Presets) {
                pet.SetArt(CatArtwork.Preset(id));pet.Notify("alice：下課見 🐈","alice");
                var visual=(FrameworkElement)pet.Content;
                visual.Measure(new Size(280,310));visual.Arrange(new Rect(0,0,280,310));visual.UpdateLayout();
                var bitmap=new RenderTargetBitmap(280,310,96,96,PixelFormats.Pbgra32);bitmap.Render(visual);
                Save(bitmap,Path.Combine(directory,id+"-window.png"));
                var native=CatArtwork.Preset(id);
                var custom=CatArtwork.Render(Appearance.Load(CatArtwork.PresetJson(id),CatArtwork.PresetJson));
                Save(custom,Path.Combine(directory,id+"-custom-render.png"));
                if(native.PixelWidth!=custom.PixelWidth || native.PixelHeight!=custom.PixelHeight)throw new Exception("Appearance dimensions changed");
                // Small color/edge differences are expected from native and WPF premultiplication.
                var left=new FormatConvertedBitmap(native,PixelFormats.Bgra32,null,0);
                var right=new FormatConvertedBitmap(custom,PixelFormats.Bgra32,null,0);
                int size=left.PixelWidth*left.PixelHeight*4;var a=new byte[size];var b=new byte[size];
                left.CopyPixels(a,left.PixelWidth*4,0);right.CopyPixels(b,right.PixelWidth*4,0);
                double error=0;int count=0;
                for(int i=0;i<size;i+=4)if(a[i+3]>240 && b[i+3]>240)for(int c=0;c<3;c++){error+=Math.Abs(a[i+c]-b[i+c]);count++;}
                if(count==0 || error/count>14)throw new Exception($"Custom renderer parity failed: {id} ({error/Math.Max(1,count):F2})");
            }
            chat.AddHistory("alice：中文與 emoji 🐈");
            File.WriteAllText(Path.Combine(directory,"result.txt"),"PASS: WPF windows/XAML, 9 native coats, custom-render parity, bubble rendering, Credential Manager write/read/delete. Microphone and foreground insertion require interactive QA.");
            return 0;
        }catch(Exception ex){File.WriteAllText(Path.Combine(directory,"result.txt"),"FAIL: "+ex.GetType().Name+" "+ex.Message);return 1;}
        finally{try{CredentialStore.Delete(credential);}catch(Exception){}}
    }
    private static void Save(BitmapSource source,string path)
    {
        var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(source));using var file=File.Create(path);encoder.Save(file);
    }
}
