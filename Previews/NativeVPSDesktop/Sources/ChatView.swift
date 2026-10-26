import SwiftUI

struct ChatView: View {
    @ObservedObject var state: PreviewState
    var body: some View {
        VStack(spacing: 0) {
            header
            if !state.chatCollapsed {
                Divider().opacity(0.4)
                conversation
                composer
            }
        }.background(Color.white).preferredColorScheme(.light).ignoresSafeArea()
    }
    private var header: some View {
        HStack(spacing: 8) {
            Text("小貓").font(.system(size: 14, weight: .semibold))
            Text("VPS 夥伴").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            if !state.chatCollapsed {
                Button { state.petals.toggle() } label: { Image(systemName: "sparkles").frame(width: 24, height: 26) }
                    .help("開關櫻花飄落").accessibilityLabel("開關櫻花飄落")
                Button { state.showRemote?() } label: { Image(systemName: "display").frame(width: 24, height: 26) }
                    .help("顯示 VPS 遠端工作區").accessibilityLabel("顯示 VPS 遠端工作區")
            }
            Button { state.toggleChat?() } label: { Image(systemName: state.chatCollapsed ? "chevron.down" : "chevron.up").frame(width: 24, height: 26) }
                .help(state.chatCollapsed ? "展開聊天面板" : "收合聊天面板")
                .accessibilityLabel(state.chatCollapsed ? "展開聊天面板" : "收合聊天面板")
        }.buttonStyle(.plain).padding(.leading, 80).padding(.trailing, 13).frame(height: 48)
    }
    private var conversation: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.white
            if state.petals { SakuraView() }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("今天 · 原生 Preview").font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
                        ForEach(state.messages) { message in MessageBubble(message: message) }
                        if state.replying { Text("小貓正在回覆…").font(.system(size: 12)).foregroundStyle(.secondary).padding(12) }
                        Color.clear.frame(height: 100).id("bottom")
                    }.padding(20)
                }.onChange(of: state.messages.count) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            CatAvatar().padding(.trailing, 12).padding(.bottom, 2).allowsHitTesting(false)
        }
    }
    private var composer: some View {
        VStack(spacing: 10) {
            if let notice = state.notice {
                HStack {
                    Text(notice).font(.system(size: 11))
                    Spacer()
                    Button { state.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("關閉提示")
                }.padding(10).background(Color(hex: 0xFCF4F5), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 8) {
                TextField("傳訊息給小貓", text: $state.draft).textFieldStyle(.plain).font(.system(size: 14)).onSubmit { state.send() }.accessibilityLabel("傳訊息給小貓")
                Button { state.notice = "語音輸入尚未接線；本預覽不會使用麥克風。" } label: { Image(systemName: "mic").foregroundStyle(.secondary).frame(width: 28, height: 32) }.buttonStyle(.plain).accessibilityLabel("語音輸入說明")
                Button { state.send() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.white).frame(width: 36, height: 36).background(Color(hex: 0x171719), in: Circle())
                }.buttonStyle(.plain).disabled(state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.replying).accessibilityLabel("送出訊息")
            }.padding(8).padding(.leading, 9).background(Color.white, in: Capsule()).overlay(Capsule().stroke(Color(hex: 0xE8E8E8), lineWidth: 1))
            Text("原生 Preview · 聊天尚未接上 AI 任務").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.horizontal, 18).padding(.bottom, 15).padding(.top, 8).background(Color.white)
    }
}
private struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.user { Spacer(minLength: 45) }
            Text(message.text).font(.system(size: 15)).lineSpacing(5).padding(.horizontal, 15).padding(.vertical, 12)
                .foregroundStyle(message.user ? Color.white : Color(hex: 0x171719))
                .background(message.user ? Color(hex: 0x171719) : Color(hex: 0xF1F1F1), in: RoundedRectangle(cornerRadius: 18))
            if !message.user { Spacer(minLength: 65) }
        }.id(message.id)
    }
}
