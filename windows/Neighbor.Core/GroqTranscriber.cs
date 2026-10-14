using System;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Collections.Generic;

namespace Neighbor.Core
{
    public sealed class GroqTranscriber : ITranscriber, IDisposable
    {
        public const string Endpoint = "https://api.groq.com/openai/v1/audio/transcriptions";
        private readonly ICredentialStore credentials;
        private readonly HttpClient client;
        public GroqTranscriber(ICredentialStore credentials, HttpMessageHandler handler = null)
        {
            this.credentials = credentials;
            // Do not forward a bearer key to redirect destinations.
            client = new HttpClient(handler ?? new HttpClientHandler { AllowAutoRedirect = false });
            client.Timeout = TimeSpan.FromSeconds(90);
        }
        public async Task<string> TranscribeAsync(string path, string language, string prompt, CancellationToken cancellation)
        {
            cancellation.ThrowIfCancellationRequested();
            string key = credentials.Read();
            if (string.IsNullOrWhiteSpace(key)) throw new InvalidOperationException("請先在 App 中設定自己的 Groq API Key。");
            if (key.IndexOfAny(new[] { '\r', '\n' }) >= 0) throw new InvalidOperationException("金鑰格式無效，請重新儲存。");
            if (!LanguagePolicy.IsSupported(language)) throw new ArgumentException("語言設定無效。");
            var info = new FileInfo(path);
            if (!info.Exists || info.Length <= 44) throw new InvalidOperationException("錄音沒有有效資料，請確認麥克風後重錄。");
            if (info.Length > 20000000) throw new InvalidOperationException("錄音檔案過大，請縮短錄音。");
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            deadline.CancelAfter(TimeSpan.FromSeconds(90));
            var requestToken = deadline.Token;
            try
            {
                using (var request = new HttpRequestMessage(HttpMethod.Post, Endpoint))
                using (var form = new MultipartFormDataContent())
                using (var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete))
                {
                    var content = new StreamContent(file);
                    content.Headers.ContentType = new MediaTypeHeaderValue("audio/wav");
                    form.Add(content, "file", "dictation.wav");
                    form.Add(new StringContent("whisper-large-v3"), "model");
                    form.Add(new StringContent(language), "language");
                    form.Add(new StringContent(prompt ?? ""), "prompt");
                    form.Add(new StringContent("json"), "response_format");
                    form.Add(new StringContent("0"), "temperature");
                    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
                    request.Content = form;
                    using (var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, requestToken).ConfigureAwait(false))
                    {
                        if (!response.IsSuccessStatusCode) throw new InvalidOperationException(ErrorForStatus((int)response.StatusCode));
                        // Bound reads even when the server omits Content-Length. Never log a response body.
                        if (response.Content.Headers.ContentLength > 1024 * 1024) throw new InvalidOperationException("辨識服務回應過大，請稍後重試。");
                        using (var stream = await response.Content.ReadAsStreamAsync().ConfigureAwait(false))
                        using (var memory = new MemoryStream())
                        {
                            var buffer = new byte[4096]; int read;
                            using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(requestToken))
                            {
                                while ((read = await stream.ReadAsync(buffer, 0, buffer.Length, timeout.Token).ConfigureAwait(false)) != 0)
                                {
                                    if (memory.Length + read > 1024 * 1024) throw new InvalidOperationException("辨識服務回應過大，請稍後重試。");
                                    memory.Write(buffer, 0, read);
                                }
                            }
                            cancellation.ThrowIfCancellationRequested();
                            string text;
                            try
                            {
                                var result = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(System.Text.Encoding.UTF8.GetString(memory.ToArray()));
                                text = result != null && result.TryGetValue("text", out var value) ? value as string : null;
                            }
                            catch { throw new InvalidOperationException("辨識服務回傳的格式無法讀取。"); }
                            if (string.IsNullOrWhiteSpace(text)) throw new InvalidOperationException("未清楚辨識到語音，請重新錄音。");
                            return text.Trim();
                        }
                    }
                }
            }
            catch (OperationCanceledException) when (!cancellation.IsCancellationRequested) { throw new InvalidOperationException("辨識逾時，錄音可暫時保留供重試。"); }
            catch (HttpRequestException) { throw new InvalidOperationException("無法連線到 Groq，請確認網路後重試。"); }
        }
        public static string ErrorForStatus(int status)
        {
            switch (status)
            {
                case 401: case 403: return "Groq 金鑰無效或沒有權限，請在 App 中更換金鑰。";
                case 413: return "Groq 拒絕過大的錄音，請縮短錄音後再試。";
                case 429: return "Groq 額度或速率已達限制，請稍後再試；App 不會自動購買額度。";
                default: return status >= 500 ? "Groq 暫時無法提供服務，請稍後重試。" : "Groq 無法處理此次請求（HTTP " + status + "）。";
            }
        }
        public void Dispose() { client.Dispose(); }
    }
}
