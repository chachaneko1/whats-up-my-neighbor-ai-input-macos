import AppKit

/// Export the exact native renderer for first-step and steady-gait review.
/// No UI input, clipboard access, network or user files are involved.
@main
struct RenderWalkingReview {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let view = DesktopPetView(resources: resources)
        var receipts: [[String: Any]] = []
        for left in [false, true] {
            let direction = left ? "left" : "right"
            for (sequence, count) in [("start", 40), ("steady", 48)] {
                for frame in 0..<count {
                    let distance: CGFloat
                    if sequence == "start" {
                        let time = CGFloat(frame) / CGFloat(count - 1)
                        distance = DesktopPetView.strideDistance * 1.1 * time * time
                    } else {
                        distance = DesktopPetView.strideDistance * (1 + CGFloat(frame) / CGFloat(count))
                    }
                    view.pose = .walking
                    view.facingLeft = left
                    view.walkDistance = distance
                    let image = NSImage(size: CGSize(width: view.bounds.width * 3, height: view.bounds.height * 3), flipped: true) { _ in
                        NSGraphicsContext.saveGraphicsState()
                        let scale = NSAffineTransform(); scale.scale(by: 3); scale.concat()
                        view.draw(view.bounds)
                        NSGraphicsContext.restoreGraphicsState()
                        return true
                    }
                    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
                    let data = bitmap.representation(using: .png, properties: [:])!
                    let name = "\(sequence)-\(direction)-\(String(format: "%02d", frame)).png"
                    try data.write(to: output.appendingPathComponent(name))
                    receipts.append(["file": name, "distance": Double(distance)])
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: receipts, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("frames.json"))
        print("Walking review: \(receipts.count) native frames exported")
    }
}
