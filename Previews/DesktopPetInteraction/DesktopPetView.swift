import AppKit

/// The approved Figma C mascot, composed locally into new resting expressions.
/// The SVG files remain unchanged; no temporary Figma URLs are used at runtime.
final class DesktopPetView: NSView {
    private let images: [String: NSImage]
    var pose: DesktopPetPose = .sitting
    var phase: Double = 0
    var walkDistance: CGFloat = 0
    var facingLeft = false
    var reduceMotion = false
    var onPointerDown: ((CGPoint) -> Void)?
    var onPointerDragged: ((CGPoint) -> Void)?
    var onPointerUp: (() -> Void)?
    var onAccessibilityPress: (() -> Void)?
    private var hitBitmap: NSBitmapImageRep?
    private var hitPose: DesktopPetPose?
    private var hitFacing = false
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(resources: URL? = Bundle.main.resourceURL?.appendingPathComponent("DesktopPet")) {
        let names = ["sit", "walk", "reply", "body", "tail", "walk-body", "walk-paws", "walk-front-face", "walk-foot-0", "walk-foot-1", "walk-foot-2", "walk-foot-3"]
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
        setAccessibilityRole(.button)
        setAccessibilityLabel("小黑貓桌面夥伴")
        setAccessibilityHelp("點一下逗逗牠，或按住拖曳，把牠拎起放下。")
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        onPointerDown?(window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation)
    }
    override func mouseDragged(with event: NSEvent) {
        onPointerDragged?(window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation)
    }
    override func mouseUp(with event: NSEvent) { onPointerUp?() }
    override func accessibilityPerformPress() -> Bool {
        guard let action = onAccessibilityPress else { return false }
        action()
        return true
    }

    /// Cache a native alpha mask per pose, rather than putting a rectangular
    /// click target over the desktop. Motion only changes this silhouette a few
    /// pixels; a 2pt tolerance keeps the boundary usable without a broad hotspot.
    func containsCat(_ point: CGPoint) -> Bool {
        guard bounds.contains(point), point.y >= 29 else { return false }
        if hitBitmap == nil || hitPose != pose || hitFacing != facingLeft {
            let image = NSImage(size: bounds.size, flipped: true) { _ in self.draw(self.bounds); return true }
            hitBitmap = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
            hitPose = pose
            hitFacing = facingLeft
        }
        guard let bitmap = hitBitmap else { return false }
        for dy in -2...2 {
            for dx in -2...2 {
                let x = Int((point.x + CGFloat(dx)) / bounds.width * CGFloat(bitmap.pixelsWide))
                let y = Int((point.y + CGFloat(dy)) / bounds.height * CGFloat(bitmap.pixelsHigh))
                if x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh,
                   (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 { return true }
            }
        }
        return false
    }

    func update(_ model: DesktopPetModel, reduceMotion: Bool) {
        if pose != model.pose || phase != model.phase || facingLeft != model.facingLeft ||
           walkDistance != model.walkDistance || self.reduceMotion != reduceMotion {
            hitBitmap = nil
        }
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
        if pose == .petted { drawResponseBubble() }
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
        case .grooming: drawGrooming()
        case .petted:
            breathe { drawImage("reply"); closeEyes(inHeadAt: .zero, scale: 1) }
        case .carried: drawCarried()
        case .yawning: drawYawning()
        case .loafing, .sleeping: drawLoaf(sleeping: pose == .sleeping)
        }
        if pose == .curious { drawQuestion() }
        if pose == .sleeping { drawSleepMarks() }
    }

    private let fur = NSColor(srgbRed: 16 / 255, green: 17 / 255, blue: 20 / 255, alpha: 1)
    private let ink = NSColor(srgbRed: 250 / 255, green: 250 / 255, blue: 249 / 255, alpha: 1)

    private func drawResponseBubble() {
        let bubble = NSBezierPath(roundedRect: CGRect(x: 66, y: 1, width: 59, height: 24), xRadius: 9, yRadius: 9)
        ink.setFill(); bubble.fill()
        fur.setStroke(); bubble.lineWidth = 1.1; bubble.stroke()
        ("呼嚕～" as NSString).draw(at: CGPoint(x: 76, y: 5), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: fur
        ])
    }

    private func drawGrooming() {
        drawImage("sit")
        closeEyes(inHeadAt: .zero, scale: 1)
        let rub: CGFloat = reduceMotion ? 0 : sin(phase * .pi * 2) * 11
        NSGraphicsContext.saveGraphicsState()
        let raisedPaw = NSAffineTransform()
        raisedPaw.translateX(by: 53 + rub, yBy: -123 - abs(rub) * 0.3)
        raisedPaw.concat()
        drawImage("walk-foot-0")
        NSGraphicsContext.restoreGraphicsState()
        // The original paw overlaps a same-color foreleg, anchored in the body.
        fur.setStroke()
        let arm = NSBezierPath()
        arm.move(to: CGPoint(x: 151, y: 285))
        arm.curve(to: CGPoint(x: 163 + rub, y: 196 - abs(rub) * 0.3),
                  controlPoint1: CGPoint(x: 128, y: 255), controlPoint2: CGPoint(x: 140, y: 222))
        arm.lineWidth = 29; arm.lineCapStyle = .round; arm.stroke()
        let pawTip = NSBezierPath()
        pawTip.move(to: CGPoint(x: 149 + rub, y: 191 - abs(rub) * 0.3))
        pawTip.curve(to: CGPoint(x: 174 + rub, y: 191 - abs(rub) * 0.3),
                     controlPoint1: CGPoint(x: 153 + rub, y: 181 - abs(rub) * 0.3),
                     controlPoint2: CGPoint(x: 169 + rub, y: 181 - abs(rub) * 0.3))
        ink.withAlphaComponent(0.7).setStroke()
        pawTip.lineWidth = 3; pawTip.lineCapStyle = .round; pawTip.stroke()
    }

    private func drawCarried() {
        let sway: CGFloat = reduceMotion ? 0 : sin(phase * 4) * 3
        // Recompose the approved body, head and original rounded paws. No
        // stretched face or newly drawn paw contours are introduced.
        drawImage("tail", in: CGRect(x: 277 + sway, y: 239, width: 83, height: 83))
        let feet: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (102, 310, 139, 334), (163, 331, 178, 342),
            (271, 331, 221, 342), (321, 318, 260, 334)
        ]
        for (index, foot) in feet.enumerated() {
            let leg = NSBezierPath()
            leg.move(to: CGPoint(x: 161 + CGFloat(index) * 25 + sway, y: 271))
            leg.line(to: CGPoint(x: foot.2 + sway, y: foot.3))
            fur.setStroke(); leg.lineWidth = 21; leg.lineCapStyle = .round; leg.stroke()
            NSGraphicsContext.saveGraphicsState()
            let shift = NSAffineTransform()
            shift.translateX(by: foot.2 + sway - foot.0 * 0.72, yBy: foot.3 - foot.1 * 0.72)
            shift.scale(by: 0.72)
            shift.concat()
            drawImage("walk-foot-\(index)")
            NSGraphicsContext.restoreGraphicsState()
        }
        drawImage("body", in: CGRect(x: 137 + sway, y: 196, width: 126, height: 120))
        images["sit"]?.draw(in: CGRect(x: 0, y: 0, width: 400, height: 226),
                             from: CGRect(x: 0, y: 174, width: 400, height: 226),
                             operation: .sourceOver, fraction: 1, respectFlipped: true,
                             hints: [.interpolation: NSImageInterpolation.high])
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
        let bob = reduceMotion ? 0 : -abs(stride) * 3
        let distance = reduceMotion ? 0 : walkDistance
        // Keep each original paw contour. A short flexible root overlaps its
        // upper portion and remains anchored inside the unchanged torso.
        let paws: [(root: CGPoint, neck: CGPoint, width: CGFloat, pair: Int)] = [
            (CGPoint(x: 112, y: 277), CGPoint(x: 103, y: 299), 36, 0),
            (CGPoint(x: 159, y: 301), CGPoint(x: 161, y: 319), 37, 1),
            (CGPoint(x: 270, y: 301), CGPoint(x: 271, y: 318), 37, 0),
            (CGPoint(x: 309, y: 276), CGPoint(x: 321, y: 308), 31, 1)
        ]
        for (index, paw) in paws.enumerated() {
            let step = Self.pawOffset(distance: distance, pair: paw.pair)
            let root = CGPoint(x: paw.root.x, y: paw.root.y + bob)
            let neck = CGPoint(x: paw.neck.x + step.x, y: paw.neck.y + step.y)
            let half = paw.width / 2
            let join = NSBezierPath()
            join.move(to: CGPoint(x: root.x - half, y: root.y))
            join.curve(to: CGPoint(x: neck.x - half, y: neck.y),
                       controlPoint1: CGPoint(x: root.x - half, y: root.y + 16),
                       controlPoint2: CGPoint(x: neck.x - half, y: neck.y - 12))
            join.line(to: CGPoint(x: neck.x + half, y: neck.y))
            join.curve(to: CGPoint(x: root.x + half, y: root.y),
                       controlPoint1: CGPoint(x: neck.x + half, y: neck.y - 12),
                       controlPoint2: CGPoint(x: root.x + half, y: root.y + 16))
            join.close()
            fur.setFill(); join.fill()
            NSGraphicsContext.saveGraphicsState()
            let motion = NSAffineTransform()
            motion.translateX(by: step.x, yBy: step.y)
            motion.concat()
            drawImage("walk-foot-\(index)")
            NSGraphicsContext.restoreGraphicsState()
        }
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
        fur.setFill()
        NSBezierPath(ovalIn: CGRect(x: 174, y: 168, width: 57, height: 43)).fill()
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
        fur.setFill()
        NSBezierPath(ovalIn: CGRect(x: 85, y: 130, width: 62, height: 59)).fill()
        NSBezierPath(ovalIn: CGRect(x: 247, y: 129, width: 77, height: 57)).fill()
        ink.setStroke()
        for x: CGFloat in [99, 267] {
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
