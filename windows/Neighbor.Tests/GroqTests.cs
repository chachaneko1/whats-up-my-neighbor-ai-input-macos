using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Neighbor.Core;

namespace Neighbor.Tests
{
    public static class GroqTests
    {
        private const string FakeKey = "test-key-never-a-real-credential";
        public static async Task RunAsync(Action<bool, string> check)
        {
            string directory = Path.Combine(Path.GetTempPath(), "NeighborGroqTests-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(directory);
            string path = Path.Combine(directory, "fixture.wav");
            byte[] audio = Enumerable.Range(0, 128).Select(i => (byte)i).ToArray(); File.WriteAllBytes(path, audio);
            try
            {
                var handler = new Handler(async (request, token) => {
                    check(request.Method == HttpMethod.Post && request.RequestUri.AbsoluteUri == GroqTranscriber.Endpoint, "Groq uses only the specified transcription endpoint");
                    check(request.Headers.Authorization?.Scheme == "Bearer" && request.Headers.Authorization.Parameter == FakeKey, "Credential appears only in bearer authorization header");
                    var form = request.Content as MultipartFormDataContent;
                    check(form != null && request.Content.Headers.ContentType.MediaType == "multipart/form-data", "Groq request is multipart");
                    var fields = new Dictionary<string, string>(); int fileCount = 0;
                    foreach (var content in form)
                    {
                        string name = content.Headers.ContentDisposition.Name.Trim('"');
                        if (name == "file")
                        {
                            fileCount++;
                            check(content.Headers.ContentType.MediaType == "audio/wav" && content.Headers.ContentDisposition.FileName.Trim('"') == "dictation.wav", "WAV attachment has bounded generic filename and audio MIME type");
                            check((await content.ReadAsByteArrayAsync()).SequenceEqual(audio), "Multipart includes exact finalized audio bytes");
                        }
                        else fields.Add(name, await content.ReadAsStringAsync());
                    }
                    check(fileCount == 1 && fields.Count == 5, "Request has one file and only expected fields");
                    check(fields["model"] == "whisper-large-v3" && fields["response_format"] == "json" && fields["temperature"] == "0", "Fixed model JSON format and zero temperature");
                    check(fields["language"] == "zh" && fields["prompt"] == "保留原話與法律用語。", "Configured language and UTF-8 prompt preserved");
                    check(fields.Values.All(v => !v.Contains(FakeKey)), "Credential never appears in multipart fields");
                    return Json("{\"text\":\"  正常轉錄  \"}");
                });
                using (var transcriber = new GroqTranscriber(new Credentials(), handler))
                    check(await transcriber.TranscribeAsync(path, "zh", "保留原話與法律用語。", CancellationToken.None) == "正常轉錄", "Successful JSON transcription trimmed");
                check(handler.Count == 1, "Successful transcription sends one request");

                foreach (int status in new[] { 401, 403, 413, 429, 500, 503, 302, 400 })
                {
                    var errorHandler = new Handler((_, __) => Task.FromResult(Json("{\"error\":\"echo " + FakeKey + "\"}", status)));
                    using (var transcriber = new GroqTranscriber(new Credentials(), errorHandler))
                    {
                        Exception error = await Failure(() => transcriber.TranscribeAsync(path, "zh", "", CancellationToken.None));
                        check(error is InvalidOperationException && error.Message == GroqTranscriber.ErrorForStatus(status) && !error.Message.Contains(FakeKey), "HTTP " + status + " is actionable and does not echo server body");
                        check(errorHandler.Count == 1, "HTTP " + status + " has no automatic provider or request fallback");
                    }
                }
                foreach (string body in new[] { "not JSON " + FakeKey, "[]", "null", "{}", "{\"text\":42}", "{\"text\":\"   \"}" })
                {
                    using (var transcriber = new GroqTranscriber(new Credentials(), new Handler((_, __) => Task.FromResult(Json(body)))))
                    {
                        Exception error = await Failure(() => transcriber.TranscribeAsync(path, "zh", "", CancellationToken.None));
                        check(error is InvalidOperationException && !error.Message.Contains(FakeKey), "Malformed missing or empty transcription fails without echoing response");
                    }
                }
                using (var transcriber = new GroqTranscriber(new Credentials(), new Handler((_, __) => Task.FromException<HttpResponseMessage>(new HttpRequestException("echo " + FakeKey)))))
                {
                    Exception error = await Failure(() => transcriber.TranscribeAsync(path, "zh", "", CancellationToken.None));
                    check(error is InvalidOperationException && error.Message.Contains("無法連線") && !error.Message.Contains(FakeKey), "Network errors sanitized");
                }
                using (var transcriber = new GroqTranscriber(new Credentials(), new Handler((_, __) => Task.FromCanceled<HttpResponseMessage>(new CancellationToken(true)))))
                {
                    Exception error = await Failure(() => transcriber.TranscribeAsync(path, "zh", "", CancellationToken.None));
                    check(error is InvalidOperationException && error.Message.Contains("逾時"), "Internal request cancellation reports timeout");
                }
                var credentials = new Credentials(); var unused = new Handler((_, __) => Task.FromResult(Json("{\"text\":\"unused\"}")));
                using (var transcriber = new GroqTranscriber(credentials, unused))
                {
                    Exception error = await Failure(() => transcriber.TranscribeAsync(path, "zh", "", new CancellationToken(true)));
                    check(error is OperationCanceledException && credentials.Reads == 0 && unused.Count == 0, "Pre-cancelled transcription does not read credentials or send network request");
                }
                using (var cancel = new CancellationTokenSource())
                {
                    var pending = new TaskCompletionSource<HttpResponseMessage>();
                    var waitingHandler = new Handler((_, token) => { token.Register(() => pending.TrySetCanceled()); return pending.Task; });
                    using (var transcriber = new GroqTranscriber(new Credentials(), waitingHandler))
                    {
                        Task<string> task = transcriber.TranscribeAsync(path, "zh", "", cancel.Token); cancel.Cancel();
                        Exception error = await Failure(() => task);
                        check(error is OperationCanceledException && waitingHandler.Count == 1, "User cancellation propagates while awaiting response headers");
                    }
                }
                using (var cancel = new CancellationTokenSource())
                {
                    var stream = new BlockingStream();
                    var bodyHandler = new Handler((_, __) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(stream) }));
                    using (var transcriber = new GroqTranscriber(new Credentials(), bodyHandler))
                    {
                        Task<string> task = transcriber.TranscribeAsync(path, "zh", "", cancel.Token);
                        check(stream.ReadStarted, "Response body is read as a stream"); cancel.Cancel();
                        Exception error = await Failure(() => task);
                        check(error is OperationCanceledException, "User cancellation propagates while reading response body");
                    }
                }
                var oversized = new byte[1024 * 1024 + 1];
                using (var transcriber = new GroqTranscriber(new Credentials(), new Handler((_, __) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(oversized) }))))
                {
                    Exception error = await Failure(() => transcriber.TranscribeAsync(path, "zh", "", CancellationToken.None));
                    check(error is InvalidOperationException && error.Message.Contains("回應過大"), "Declared response above one MiB rejected");
                }
                var streaming = new NonSeekableStream(new byte[2 * 1024 * 1024]);
                using (var transcriber = new GroqTranscriber(new Credentials(), new Handler((_, __) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(streaming) }))))
                {
                    Exception error = await Failure(() => transcriber.TranscribeAsync(path, "zh", "", CancellationToken.None));
                    check(error is InvalidOperationException && error.Message.Contains("回應過大") && streaming.BytesRead <= 1024 * 1024 + 4096, "Unbounded chunked response stops reading at one MiB limit");
                }
                foreach (string key in new[] { "", " \t", "bad\r\nkey" })
                {
                    var never = new Handler((_, __) => Task.FromResult(Json("{\"text\":\"unused\"}")));
                    using (var transcriber = new GroqTranscriber(new Credentials { Key = key }, never))
                    {
                        check(await Failure(() => transcriber.TranscribeAsync(path, "zh", "", CancellationToken.None)) is InvalidOperationException && never.Count == 0, "Missing or newline credential rejected before network");
                    }
                }
                var invalidHandler = new Handler((_, __) => Task.FromResult(Json("{\"text\":\"unused\"}")));
                using (var transcriber = new GroqTranscriber(new Credentials(), invalidHandler))
                {
                    check(await Failure(() => transcriber.TranscribeAsync(path, "xx", "", CancellationToken.None)) is ArgumentException, "Unknown language rejected before upload");
                    check(await Failure(() => transcriber.TranscribeAsync(Path.Combine(directory, "missing.wav"), "zh", "", CancellationToken.None)) is InvalidOperationException, "Missing audio rejected");
                    string empty = Path.Combine(directory, "empty.wav"); File.WriteAllBytes(empty, new byte[44]);
                    check(await Failure(() => transcriber.TranscribeAsync(empty, "zh", "", CancellationToken.None)) is InvalidOperationException, "Header-only audio rejected");
                    string large = Path.Combine(directory, "large.wav"); using (var file = File.Create(large)) file.SetLength(20000001);
                    check(await Failure(() => transcriber.TranscribeAsync(large, "zh", "", CancellationToken.None)) is InvalidOperationException && invalidHandler.Count == 0, "Oversized audio rejected before network");
                }
            }
            finally { Directory.Delete(directory, true); }
        }
        private static HttpResponseMessage Json(string body, int status = 200)
        { return new HttpResponseMessage((HttpStatusCode)status) { Content = new StringContent(body, Encoding.UTF8, "application/json") }; }
        private static async Task<Exception> Failure(Func<Task<string>> action)
        { try { await action(); return null; } catch (Exception error) { return error; } }
        private sealed class Credentials : ICredentialStore
        {
            public string Key = FakeKey; public int Reads;
            public string Read() { Reads++; return Key; }
            public void Write(string key) { Key = key; }
            public void Delete() { Key = null; }
        }
        private sealed class Handler : HttpMessageHandler
        {
            private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send;
            public int Count;
            public Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) { this.send = send; }
            protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            { Count++; return send(request, cancellationToken); }
        }
        private sealed class NonSeekableStream : Stream
        {
            private readonly byte[] content; private int position;
            public int BytesRead { get { return position; } }
            public NonSeekableStream(byte[] content) { this.content = content; }
            public override bool CanRead => true; public override bool CanSeek => false; public override bool CanWrite => false;
            public override long Length => throw new NotSupportedException();
            public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
            public override int Read(byte[] buffer, int offset, int count)
            { int length = Math.Min(count, content.Length - position); Array.Copy(content, position, buffer, offset, length); position += length; return length; }
            public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
            { cancellationToken.ThrowIfCancellationRequested(); return Task.FromResult(Read(buffer, offset, count)); }
            public override void Flush() { }
            public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
            public override void SetLength(long value) { throw new NotSupportedException(); }
            public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
        }
        private sealed class BlockingStream : Stream
        {
            public bool ReadStarted;
            public override bool CanRead => true; public override bool CanSeek => false; public override bool CanWrite => false;
            public override long Length => throw new NotSupportedException();
            public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
            public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
            { ReadStarted = true; var pending = new TaskCompletionSource<int>(); cancellationToken.Register(() => pending.TrySetCanceled()); return pending.Task; }
            public override int Read(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
            public override void Flush() { }
            public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
            public override void SetLength(long value) { throw new NotSupportedException(); }
            public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
        }
    }
}
