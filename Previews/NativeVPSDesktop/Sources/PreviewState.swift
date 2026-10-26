import AppKit
import SwiftUI

struct ChatMessage: Identifiable { let id = UUID(); let text: String; let user: Bool }
@MainActor final class PreviewState: ObservableObject {
    @Published var petals = true
    @Published var chatCollapsed = false
    @Published var remoteCollapsed = false
    var toggleChat: (() -> Void)?
    var toggleRemote: (() -> Void)?
    @Published var messages = [
        ChatMessage(text: "幫我找量子運算相關的論文。", user: true),
        ChatMessage(text: "好呀，我會在 VPS 的瀏覽器幫你查找，進度和畫面會放在右上角。", user: false),
        ChatMessage(text: "右上角會連到 VPS 電腦。你可以先看看桌面，需要時再按「接手操作」。", user: false)
    ]
    @Published var draft = ""
    @Published var replying = false
    @Published var notice: String?
    private var replyTask: Task<Void, Never>?
    var showRemote: (() -> Void)?
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !replying else { return }
        messages.append(ChatMessage(text: text, user: true)); draft = ""; replying = true
        replyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled, let self else { return }
            self.messages.append(ChatMessage(text: "收到。右上角連的是 VPS 真實桌面；聊天的 AI 任務執行仍在預覽階段，這則訊息尚未送出給遠端 Agent。", user: false))
            self.replying = false
        }
    }
    func shutdown() { replyTask?.cancel() }
}
struct CatAvatar: View {
    var body: some View {
        if let path = Bundle.main.path(forResource: "cat", ofType: "png"), let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 220, height: 200).frame(width: 110, height: 150).clipped().accessibilityLabel("我們的三花貓")
        }
    }
}
