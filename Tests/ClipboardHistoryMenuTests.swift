import AppKit

@main
struct ClipboardHistoryMenuTests {
    static func main() {
        let menu = ClipboardHistoryMenuController()
        let secret = "synthetic private phrase"
        let item = ClipboardHistoryItem(id: UUID(), kind: .text,
                                        data: Data(secret.utf8), createdAt: Date())
        menu.update(items: [item], isEnabled: true)
        let titles = menu.menu.items.map(\.title)
        precondition(titles.contains("已保留 1 筆文字"))
        precondition(titles.contains("暫停記錄"))
        precondition(titles.contains("清除全部紀錄…"))
        precondition(!titles.contains { $0.contains(secret) })
        menu.update(items: [], isEnabled: false)
        precondition(menu.menu.items.first?.title == "已保留 0 筆文字")
        precondition(menu.menu.items.first(where: { $0.title == "暫停記錄" })?.state == .on)
        print("ClipboardHistoryMenuTests passed")
    }
}
