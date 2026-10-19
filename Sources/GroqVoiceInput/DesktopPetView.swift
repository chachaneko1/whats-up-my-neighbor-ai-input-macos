import AppKit

/// The approved Figma C mascot, composed locally into new resting expressions.
/// The SVG files remain unchanged; no temporary Figma URLs are used at runtime.
final class DesktopPetView: NSView {
    private var images: [String: NSImage]
    private let resources: URL?
    private(set) var coat = CatCoat.original
    private var palette = CatCoatArtwork(.original)
    var pose: DesktopPetPose = .sitting
    var phase: Double = 0
    var walkDistance: CGFloat = 0
    var facingLeft = false
    var reduceMotion = false
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    init(resources: URL? = Bundle.main.resourceURL?.appendingPathComponent("DesktopPet")) {
        self.resources = resources
        let names = ["sit", "walk", "reply", "body", "tail", "walk-body", "walk-paws", "walk-front-face"]
        images = Dictionary(uniqueKeysWithValues: names.compactMap { name in
            guard let url = resources?.appendingPathComponent(name + ".svg"),
                  let image = NSImage(contentsOf: url) else { return nil }
            // Render the original head and face together, without a reflected
            // SVG cache moving their edges after direction changes.
            if name == "walk-front-face" { image.cacheMode = .never }
            return (name, image)
        })
        super.init(frame: CGRect(origin: .zero, size: DesktopPetModel.size))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("小黑貓桌面夥伴")
        setAccessibilityHelp("可從選單列的小黑貓選擇收回。")
    }

    required init?(coder: NSCoder) { nil }

    @discardableResult
    func setCoat(_ coat: CatCoat) -> Bool {
        guard self.coat != coat else { return true }
        let palette = CatCoatArtwork(coat)
        var colored: [String: NSImage] = [:]
        for name in ["sit", "walk", "reply", "body", "tail", "walk-body", "walk-paws", "walk-front-face"] {
            guard let url = resources?.appendingPathComponent(name + ".svg"),
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  let image = coat.isOriginal ? NSImage(contentsOf: url) : NSImage(data: Data(palette.svg(source, asset: name).utf8)) else { return false }
            if name == "walk-front-face" { image.cacheMode = .never }
            colored[name] = image
            if name == "sit", !coat.isOriginal {
                let furOnly = source.replacingOccurrences(of: "<path[^>]*stroke=\"white\"[^>]*/>",
                                                          with: "", options: .regularExpression)
                guard let plain = NSImage(data: Data(palette.svg(furOnly, asset: name).utf8)) else { return false }
                colored["sit-fur"] = plain
            }
        }
        images = colored
        self.coat = coat
        self.palette = palette
        setAccessibilityLabel(coat.title + "桌面夥伴")
        needsDisplay = true
        return true
    }

    func update(_ model: DesktopPetModel, reduceMotion: Bool) {
        if pose != model.pose { setAccessibilityValue(model.pose.description) }
        pose = model.pose
        phase = model.phase
        walkDistance = model.walkDistance
        facingLeft = model.facingLeft
        self.reduceMotion = reduceMotion
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        // The original 400-point artwork's feet (y=367) sit 2pt above the
        // panel's bottom. This is also the model's folder-perch contact point.
        transform.translateX(by: 8, yBy: 128 - 2 - 367 * 0.28)
        transform.scale(by: 0.28)
        transform.concat()
        switch pose {
        case .sitting, .curious:
            breathe { drawImage(pose == .curious ? "reply" : "sit") }
        case .standing: drawImage("walk")
        case .walking: drawWalking()
        case .yawning: drawYawning()
        case .loafing, .sleeping: drawLoaf(sleeping: pose == .sleeping)
        }
        if pose == .curious { drawQuestion() }
        if pose == .sleeping { drawSleepMarks() }
    }

    private var fur: NSColor { palette.fur }
    private var ink: NSColor {
        coat.isOriginal ? NSColor(srgbRed: 250 / 255, green: 250 / 255, blue: 249 / 255, alpha: 1) : palette.ink
    }

    private func paintFur(in rect: CGRect) {
        guard !coat.isOriginal else {
            fur.setFill(); NSBezierPath(ovalIn: rect).fill(); return
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: rect).addClip()
        drawImage("sit-fur")
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawImage(_ name: String, in rect: CGRect = CGRect(x: 0, y: 0, width: 400, height: 400)) {
        images[name]?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }

    private func breathe(_ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let breath = reduceMotion ? 0 : sin(phase * .pi / 2.8) * 0.006
        let transform = NSAffineTransform()
        transform.translateX(by: 200, yBy: 367)
        transform.scaleX(by: 1 + breath * 0.35, yBy: 1 + breath)
        transform.translateX(by: -200, yBy: -367)
        transform.concat()
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawWalking() {
        let stride = reduceMotion ? 0 : sin(walkDistance / Self.strideDistance * 2 * .pi)
        NSGraphicsContext.saveGraphicsState()
        // Only the silhouette turns. Mirroring the complete mascot swaps X/✓
        // and reverses the check itself, including after a leftward walk.
        if !facingLeft {
            let turn = NSAffineTransform()
            turn.translateX(by: 400, yBy: 0)
            turn.scaleX(by: -1, yBy: 1)
            turn.concat()
        }
        // The original Walk body has its tail at the rear (right). Separate
        // original paw groups keep contact with the ground as they alternate.
        for side in 0...1 {
            NSGraphicsContext.saveGraphicsState()
            let step = Self.pawOffset(distance: reduceMotion ? 0 : walkDistance, pair: side)
            let motion = NSAffineTransform()
            motion.translateX(by: step.x, yBy: step.y)
            motion.concat()
            // Diagonal pairs, not a sliding lower half of the front-facing cat.
            for region in side == 0
                ? [CGRect(x: 60, y: 270, width: 73, height: 100), CGRect(x: 240, y: 270, width: 63, height: 100)]
                : [CGRect(x: 133, y: 270, width: 65, height: 100), CGRect(x: 303, y: 270, width: 65, height: 100)] {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: region).addClip()
                drawImage("walk-paws")
                NSGraphicsContext.restoreGraphicsState()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        let bob = reduceMotion ? 0 : -abs(stride) * 3
        let lift = NSAffineTransform()
        lift.translateX(by: 0, yBy: bob)
        lift.concat()
        drawImage("walk-body")
        NSGraphicsContext.restoreGraphicsState()

        // Keep the approved front-facing head, eyes and mouth together.
        // Only the body turns; the face keeps its original proportions.
        NSGraphicsContext.saveGraphicsState()
        let faceLift = NSAffineTransform()
        faceLift.translateX(by: 0, yBy: bob)
        faceLift.concat()
        drawWalkingFace()
        NSGraphicsContext.restoreGraphicsState()
    }

    // One cycle covers 40pt of actual screen travel. During 60% of the
    // cycle each planted paw moves back relative to the body by exactly the
    // distance the body moves forward, so the paw stays fixed on the desktop.
    // The remaining 40% lifts it in an arc and brings it forward for landing.
    static let strideDistance: CGFloat = 86 * 0.28 / 0.6

    static func pawOffset(distance: CGFloat, pair: Int) -> CGPoint {
        let cycle = (max(0, distance) / strideDistance + CGFloat(pair) * 0.5)
            .truncatingRemainder(dividingBy: 1)
        if cycle < 0.6 {
            return CGPoint(x: -43 + 86 * cycle / 0.6, y: 0)
        }
        let swing = (cycle - 0.6) / 0.4
        let eased = swing * swing * (3 - 2 * swing)
        return CGPoint(x: 43 - 86 * eased, y: -sin(swing * .pi) * 28)
    }

    private func drawWalkingFace() {
        // A small shoulder offset follows travel without stretching the head
        // or mirroring the X-left / check-right face.
        drawImage("walk-front-face", in: CGRect(x: facingLeft ? 0 : 40, y: 0, width: 400, height: 400))
    }

    private func drawYawning() {
        drawImage("sit")
        let opening = reduceMotion ? 0.8 : sin(min(1, phase / 3.2) * .pi)
        paintFur(in: CGRect(x: 174, y: 168, width: 57, height: 43))
        ink.setStroke()
        let mouth = NSBezierPath(ovalIn: CGRect(x: 187, y: 181 - opening * 3,
                                               width: 25, height: 8 + opening * 30))
        mouth.lineWidth = 6
        mouth.stroke()
        if opening > 0.4 {
            closeEyes(inHeadAt: CGPoint.zero, scale: 1)
        }
    }

    private func drawLoaf(sleeping: Bool) {
        breathe {
            drawImage("tail", in: CGRect(x: 272, y: 283, width: 102.33, height: 79))
            drawImage("body", in: CGRect(x: 62, y: 272, width: 280, height: 94))
            // Head remains round and uncompressed while the body tucks down.
            // Its source rectangle is the head of the approved sitting asset.
            images["sit"]?.draw(in: CGRect(x: 16, y: 118, width: 360, height: 203.4),
                                 from: CGRect(x: 0, y: 174, width: 400, height: 226),
                                 operation: .sourceOver, fraction: 1, respectFlipped: true,
                                 hints: [.interpolation: NSImageInterpolation.high])
            if sleeping { closeEyes(inHeadAt: CGPoint(x: 16, y: 118), scale: 0.9) }
        }
    }

    private func closeEyes(inHeadAt origin: CGPoint, scale: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: origin.x, yBy: origin.y)
        transform.scale(by: scale)
        transform.concat()
        paintFur(in: CGRect(x: 85, y: 130, width: 62, height: 59))
        paintFur(in: CGRect(x: 247, y: 129, width: 77, height: 57))
        ink.setStroke()
        for x: CGFloat in [99, 267] {
            if !coat.isOriginal { CatCoatArtwork.color(palette.ink(at: CGPoint(x: x + 16, y: 159))).setStroke() }
            let eyelid = NSBezierPath()
            eyelid.move(to: CGPoint(x: x, y: 159))
            eyelid.curve(to: CGPoint(x: x + 32, y: 159), controlPoint1: CGPoint(x: x + 9, y: 170),
                         controlPoint2: CGPoint(x: x + 23, y: 170))
            eyelid.lineWidth = 6
            eyelid.lineCapStyle = .round
            eyelid.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawQuestion() {
        let bob = reduceMotion ? 0 : sin(phase * 2) * 2
        let bubble = CGRect(x: 308, y: -44 + bob, width: 64, height: 65)
        fur.setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 22, yRadius: 22).fill()
        ink.setStroke()
        let question = NSBezierPath()
        question.move(to: CGPoint(x: 329, y: -23 + bob))
        question.curve(to: CGPoint(x: 343, y: -9 + bob), controlPoint1: CGPoint(x: 330, y: -39 + bob),
                       controlPoint2: CGPoint(x: 365, y: -28 + bob))
        question.line(to: CGPoint(x: 340, y: -3 + bob))
        question.lineWidth = 6
        question.lineCapStyle = .round
        question.stroke()
        ink.setFill()
        NSBezierPath(ovalIn: CGRect(x: 336, y: 5 + bob, width: 7, height: 7)).fill()
    }

    private func drawSleepMarks() {
        for i in 0..<3 {
            let opacity: CGFloat = reduceMotion ? 0.8 : 0.5 + 0.35 * CGFloat(sin(phase * 0.8 + Double(i)))
            let x = CGFloat(310 + i * 19), y = CGFloat(104 - i * 25)
            let z = NSBezierPath()
            z.move(to: CGPoint(x: x, y: y))
            z.line(to: CGPoint(x: x + 13, y: y))
            z.line(to: CGPoint(x: x, y: y + 14))
            z.line(to: CGPoint(x: x + 13, y: y + 14))
            z.lineCapStyle = .round
            z.lineJoinStyle = .round
            fur.withAlphaComponent(opacity).setStroke()
            z.lineWidth = 9
            z.stroke()
            ink.withAlphaComponent(opacity).setStroke()
            z.lineWidth = 4
            z.stroke()
        }
    }

    #if DESKTOP_PET_TESTS
    func renderPNG(pose: DesktopPetPose, phase: Double = 0, facingLeft: Bool = false, walkDistance: CGFloat = 0) -> Data {
        self.pose = pose
        self.phase = phase
        self.facingLeft = facingLeft
        self.walkDistance = walkDistance
        let image = NSImage(size: bounds.size, flipped: true) { _ in self.draw(self.bounds); return true }
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return bitmap.representation(using: .png, properties: [:])!
    }
    var loadedAssets: Set<String> { Set(images.keys) }
    #endif
}
