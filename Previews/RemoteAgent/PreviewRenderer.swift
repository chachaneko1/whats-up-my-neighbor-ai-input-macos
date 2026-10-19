import AppKit
import SwiftUI

/// Renders only this app's view tree. Never records the desktop or requests TCC.
enum PreviewRenderer {
    private final class FixtureTransport: AgentTransport {
        var onEvent: ((AgentEvent) -> Void)?
        let isDemonstration = true
        var taskID: UUID?
        func start(_ task: AgentTask) throws { taskID = task.id }
        func cancel(taskID: UUID) {}
        func emit(_ kind: AgentEvent.Kind, sequence: Int, message: String, progress: Double? = nil, result: String? = nil) {
            onEvent?(AgentEvent(taskID: taskID!, sequence: sequence, kind: kind,
                message: message, progress: progress, result: result))
        }
    }
    private struct FixtureAdapter: ProviderAdapter {
        let provider: AgentProvider
        let transport: FixtureTransport
        func makeTransport() -> AgentTransport { transport }
    }

    static func render(to output: URL) throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let transport = FixtureTransport()
        let model = RemoteAgentPreviewModel(preferences: PreviewPreferencesStore(directory: output.appendingPathComponent("render-preferences")),
            adapterFactory: { FixtureAdapter(provider: $0, transport: transport) })
        model.useExample()
        try capture(model, name: "ready", output: output)
        model.startDemo()
        transport.emit(.progress, sequence: 0, message: "已接收任務，開始本機示範。", progress: 0.15)
        transport.emit(.progress, sequence: 1, message: "模擬查詢網頁；沒有實際開啟或讀取網站。", progress: 0.38)
        try capture(model, name: "running", output: output)
        model.cancel()
        try capture(model, name: "cancelled", output: output)
        model.startDemo()
        transport.emit(.failed, sequence: 0, message: "示範連線中斷，請重新執行示範。")
        try capture(model, name: "failed", output: output)
        model.startDemo()
        transport.emit(.completed, sequence: 0, message: "示範流程完成，未執行遠端任務。",
            result: "本次只驗證任務流程，沒有查詢網頁、呼叫 AI 或寫入備忘錄。\n\n接上並驗證 Linux VPS 後，這裡會呈現重點、來源與儲存位置。")
        try capture(model, name: "completed", output: output)
        try capture(model, name: "compact-dark", output: output, size: NSSize(width: 760, height: 680), dark: true)
        print("Rendered six preview states: \(output.path)")
    }

    private static func capture(_ model: RemoteAgentPreviewModel, name: String, output: URL,
                                size: NSSize = NSSize(width: 980, height: 780), dark: Bool = false) throws {
        let view = NSHostingView(rootView: RemoteAgentView(model: model))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = view
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: output.appendingPathComponent(name + ".png"))
        window.orderOut(nil)
    }
}
