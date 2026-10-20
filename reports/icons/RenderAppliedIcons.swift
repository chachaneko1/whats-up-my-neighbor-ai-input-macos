import AppKit
import Foundation

@main
enum RenderAppliedIcons {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let app = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon-source.png"))!
        func color(_ h: Int) -> NSColor {
            NSColor(srgbRed: CGFloat(h >> 16 & 255)/255, green: CGFloat(h >> 8 & 255)/255, blue: CGFloat(h & 255)/255, alpha: 1)
        }
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 22, _ bold: Bool = false) {
            (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: color(0x252629)])
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: NSColor) {
            fill.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: 20, yRadius: 20).fill()
        }
        func draw(_ image: NSImage, _ rect: NSRect) {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let image = NSImage(size: NSSize(width: 1440, height: 1020), flipped: true) { _ in
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1440, height: 1020).fill()
            text("核准原稿・實作後的圖示", 64, 44, 36, true)
            text("App 純白底，選單列沿用同一臉型；以下由實際程式繪製。", 64, 106)
            box(64, 168, 628, 466, color(0xF5F6F7))
            box(716, 168, 660, 466, color(0xF5F6F7))
            text("App／VPS 預覽 App", 96, 196, 26, true)
            draw(app, NSRect(x: 206, y: 250, width: 340, height: 340))
            text("選單列・一般狀態", 748, 196, 26, true)
            draw(NekoMenuBarIcon.image(), NSRect(x: 902, y: 274, width: 288, height: 216))
            box(768, 540, 550, 42, color(0x2680AF))
            draw(NekoMenuBarIcon.image(), NSRect(x: 1032, y: 552, width: 24, height: 18))
            text("選單列實際尺寸示意", 926, 596, 18)
            text("五種狀態保留", 64, 664, 26, true)
            let labels = ["一般", "錄音中", "處理中", "重試", "遠端模式"]
            for (index, state) in NekoMenuBarIcon.State.allCases.enumerated() {
                let x = 64 + CGFloat(index) * 266
                box(x, 720, 248, 188, color(0xE5EAF0))
                draw(NekoMenuBarIcon.image(for: state), NSRect(x: x+52, y: 748, width: 144, height: 108))
                text(labels[index], x+82, 868, 21)
            }
            text("本機建置與原生渲染預覽；未啟動、未安裝、未發布。", 64, 953, 20)
            return true
        }
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("reports/icons/applied-icons-preview.png"))
    }
}
