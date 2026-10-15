import AppKit

@main
struct RenderPreview {
    static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let states = NekoMenuBarIcon.State.allCases
        let labels = ["待機", "錄音", "處理中", "等待重試", "接力開啟"]
        let board = NSImage(size: NSSize(width: 800, height: 420), flipped: false) { bounds in
            NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
            bounds.fill()
            let dark = NSRect(x: 0, y: 0, width: 800, height: 180)
            NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
            dark.fill()
            func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor) {
                (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
            }
            label("選單列黑貓 · 18 × 18 pt", x: 32, y: 375, size: 23, color: .black)
            label("上排為放大檢視，下排為實際尺寸。", x: 32, y: 345, size: 13, color: NSColor(calibratedWhite: 0.4, alpha: 1))
            for (index, state) in states.enumerated() {
                let x = CGFloat(index) * 152 + 38
                let icon = NekoMenuBarIcon.image(for: state)
                icon.isTemplate = false
                for (y, dark): (CGFloat, Bool) in [(240, false), (70, true)] {
                    let tint: NSColor = .black
                    let colored = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                        icon.draw(in: rect)
                        tint.setFill()
                        rect.fill(using: .sourceIn)
                        return true
                    }
                    colored.draw(in: NSRect(x: x + 20, y: y, width: 72, height: 72))
                    colored.draw(in: NSRect(x: x + 47, y: y - 27, width: 18, height: 18))
                    label(labels[index], x: x + 28, y: y - 52, size: 13, color: dark ? .white : .black)
                }
            }
            return true
        }
        let bitmap = NSBitmapImageRep(data: board.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("menu-bar-preview.png"))
        for (index, state) in states.enumerated() {
            let icon = NekoMenuBarIcon.image(for: state)
            icon.isTemplate = false
            let bitmap = NSBitmapImageRep(data: icon.tiffRepresentation!)!
            try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon-\(index).png"))
        }
    }
}
