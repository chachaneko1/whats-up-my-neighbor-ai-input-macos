import AppKit

/// Same native drawing as the standalone pet, exported locally at 3x scale.
@main
struct RenderGroomingReview {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let view = DesktopPetView(resources: URL(fileURLWithPath: CommandLine.arguments[1]))
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        view.pose = .grooming
        for frame in 0..<80 {
            view.phase = Double(frame) * 0.04
            let image = NSImage(size: CGSize(width: view.bounds.width * 3, height: view.bounds.height * 3), flipped: true) { _ in
                NSGraphicsContext.saveGraphicsState()
                let scale = NSAffineTransform(); scale.scale(by: 3); scale.concat()
                view.draw(view.bounds)
                NSGraphicsContext.restoreGraphicsState()
                return true
            }
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            try bitmap.representation(using: .png, properties: [:])!.write(
                to: output.appendingPathComponent(String(format: "%02d.png", frame)))
        }
        print("Grooming review: 80 native frames exported at 3x scale")
    }
}
