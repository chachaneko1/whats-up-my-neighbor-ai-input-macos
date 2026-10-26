import AppKit
import SwiftUI
import WebKit

@MainActor final class VPSDesktopConnection: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var status = "尚未連線"
    @Published var connected = false
    @Published var loading = false
    @Published var controlling = false
    @Published var awaitingCredentials = false
    @Published var confirmDisconnect = false
    let webView: WKWebView
    private var process: Process?
    private var generation = UUID()
    private var buffer = Data()
    private var allowedURL: URL?
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(VPSDesktopMessage(owner: self), name: "connection")
    }
    func connect() {
        guard !loading && !connected && !awaitingCredentials else { return }
        if let process, process.isRunning, let allowedURL {
            loading = true; status = "正在重新連入 VPS 桌面…"
            webView.load(URLRequest(url: allowedURL))
            return
        }
        disconnect()
        let id = UUID(); generation = id
        status = "正在連線 VPS…"; loading = true
        guard let bridge = Bundle.main.url(forResource: "bridge", withExtension: "mjs", subdirectory: "VPSDesktop") else { status = "找不到遠端桌面元件"; loading = false; return }
        guard let node = VPSDesktopAvailability.nodePath() else { status = "找不到 Node.js，無法建立連線"; loading = false; return }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: node)
        child.arguments = [bridge.path]
        child.standardInput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        let output = Pipe(); child.standardOutput = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            // Re-capture weakly: Swift 5.10 rejects reading the outer `weak var self` inside a Task.
            Task { @MainActor [weak self] in self?.receive(data, id: id) }
        }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == id else { return }
                self.connected = false; self.loading = false; self.controlling = false; self.awaitingCredentials = false
                self.status = "連線已中斷，請重新連線"
                self.allowedURL = nil
            }
        }
        process = child
        do { try child.run() } catch { loading = false; status = "無法啟動連線元件"; process = nil }
    }
    private func receive(_ data: Data, id: UUID) {
        guard generation == id else { return }
        buffer.append(data)
        while let lineEnd = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: lineEnd)
            buffer.removeSubrange(...lineEnd)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: String] else { continue }
            if object["event"] == "ready", let value = object["url"], let url = URL(string: value), url.host == "127.0.0.1", url.scheme == "http" {
                allowedURL = url; status = "安全通道已就緒 · 準備登入"
                webView.load(URLRequest(url: url))
            } else if object["event"] == "error" {
                status = object["message"] ?? "連線失敗"; loading = false; connected = false; awaitingCredentials = false
            }
        }
    }
    func handle(_ event: String) {
        switch event {
        case "connected": connected = true; loading = false; controlling = false; awaitingCredentials = false; status = "已連線 · 即時桌面"
        case "credentials": loading = false; awaitingCredentials = true; status = "請輸入 VNC 密碼完成登入"
        case "authenticating": loading = true; awaitingCredentials = false; status = "正在驗證 VNC 密碼…"
        case "blocked": connected = false; loading = false; awaitingCredentials = false; status = "VPS 暫時限制登入，請稍後再試"
        case "authfailed": connected = false; loading = false; awaitingCredentials = false; status = "密碼驗證失敗，請重新連線後再試"
        case "disconnected":
            let wasWaiting = awaitingCredentials || loading
            connected = false; loading = false; controlling = false; awaitingCredentials = false
            if !status.contains("密碼驗證失敗") && !status.contains("暫時限制登入") { status = wasWaiting ? "登入連線已中斷，請重新連線" : "桌面連線已中斷" }
        case "retry": connect()
        default: break
        }
    }
    func toggleControl() {
        guard connected else { return }
        controlling.toggle()
        webView.evaluateJavaScript("window.setControl(\(controlling ? "true" : "false"))", completionHandler: nil)
    }
    func disconnect() {
        generation = UUID()
        if let process, process.isRunning { process.terminate() }
        process = nil; buffer.removeAll(); allowedURL = nil
        connected = false; loading = false; controlling = false; awaitingCredentials = false; confirmDisconnect = false; status = "尚未連線"
        webView.loadHTMLString("<html><body style='background:#faf8f9'></body></html>", baseURL: nil)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        decisionHandler(url.absoluteString == "about:blank" || url == allowedURL ? .allow : .cancel)
    }
}
private final class VPSDesktopMessage: NSObject, WKScriptMessageHandler {
    weak var owner: VPSDesktopConnection?
    init(owner: VPSDesktopConnection) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let value = message.body as? String else { return }
        Task { @MainActor in owner?.handle(value) }
    }
}
struct VPSDesktopSurface: NSViewRepresentable {
    let connection: VPSDesktopConnection
    func makeNSView(context: Context) -> WKWebView { connection.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
