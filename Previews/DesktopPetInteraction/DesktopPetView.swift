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
    var carryLean: CGFloat = 0
    var isSettling = false
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
           walkDistance != model.walkDistance || self.reduceMotion != reduceMotion ||
           carryLean != model.carryLean || isSettling != model.isSettling {
            hitBitmap = nil
        }
        if pose != model.pose { setAccessibilityValue(model.pose.description) }
        pose = model.pose
        phase = model.phase
        walkDistance = model.walkDistance
        facingLeft = model.facingLeft
        self.reduceMotion = reduceMotion
        carryLean = model.carryLean
        isSettling = model.isSettling
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
            if pose == .sitting && isSettling { drawSettling() }
            else { breathe { drawImage(pose == .curious ? "reply" : "sit") } }
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
        let t = reduceMotion ? 1 : max(0, min(1, phase / 0.22))
        let arrival = 1 - pow(1 - t, 3)
        guard arrival > 0 else { drawImage("sit"); return }
        func point(_ rest: CGPoint, _ lifted: CGPoint) -> CGPoint {
            CGPoint(x: rest.x + (lifted.x - rest.x) * arrival,
                    y: rest.y + (lifted.y - rest.y) * arrival)
        }
        func p(_ x: CGFloat, _ y: CGFloat, _ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            point(CGPoint(x: x, y: y), CGPoint(x: lx, y: ly))
        }
        NSGraphicsContext.saveGraphicsState()
        let tilt: CGFloat = reduceMotion ? 0 : carryLean
        let settle: CGFloat = reduceMotion ? 0 : CGFloat(sin(phase * 10) * exp(-phase * 8)) * 1.5
        let body = NSAffineTransform()
        body.translateX(by: 202, yBy: 199)
        body.rotate(byDegrees: (tilt + settle) * arrival)
        body.translateX(by: -202, yBy: -199)
        body.concat()

        // Side-on silhouette: rear legs behind the rounded torso, one long
        // near foreleg and a bent near hindleg. Feet never form a four-finger row.
        drawImage("tail", in: CGRect(x: 272 + 11 * arrival, y: 247 + 13 * arrival,
                                    width: 102 - 24 * arrival, height: 79 - 19 * arrival))
        drawLimb(from: p(160, 270, 212, 224), through: p(166, 315, 208, 278),
                 to: p(166, 343, 196, 319), width: 21)
        drawOriginalPaw(1, at: p(166, 343, 196, 319), scale: 0.58)
        drawLimb(from: p(277, 281, 266, 275), through: p(293, 313, 298, 302),
                 to: p(290, 335, 284, 323), width: 22)
        drawOriginalPaw(3, at: p(290, 335, 284, 323), scale: 0.62)

        let torso = NSBezierPath()
        torso.move(to: p(152, 203, 196, 187))
        torso.curve(to: p(247, 203, 276, 218), controlPoint1: p(185, 203, 231, 183),
                    controlPoint2: p(214, 203, 264, 195))
        torso.curve(to: p(323, 290, 302, 291), controlPoint1: p(285, 205, 295, 243),
                    controlPoint2: p(314, 245, 310, 269))
        torso.curve(to: p(254, 366, 272, 326), controlPoint1: p(333, 338, 302, 314),
                    controlPoint2: p(312, 365, 292, 328))
        torso.curve(to: p(149, 366, 211, 305), controlPoint1: p(218, 366, 246, 333),
                    controlPoint2: p(185, 366, 221, 324))
        torso.curve(to: p(77, 289, 179, 233), controlPoint1: p(92, 365, 194, 279),
                    controlPoint2: p(66, 338, 181, 256))
        torso.curve(to: p(152, 203, 196, 187), controlPoint1: p(86, 243, 171, 210),
                    controlPoint2: p(114, 205, 178, 193))
        torso.close(); fur.setFill(); torso.fill()

        drawLimb(from: p(148, 283, 196, 220), through: p(148, 322, 179, 283),
                 to: p(148, 343, 173, 340), width: 27)
        drawOriginalPaw(0, at: p(148, 343, 173, 340), scale: 0.64)
        drawLimb(from: p(253, 283, 266, 282), through: p(260, 322, 301, 311),
                 to: p(254, 343, 254, 341), width: 27)
        drawOriginalPaw(2, at: p(254, 343, 254, 341), scale: 0.66)
        // One short armpit crease makes the near foreleg readable in black fur.
        let crease = NSBezierPath()
        crease.move(to: p(148, 283, 200, 251))
        crease.curve(to: p(148, 335, 187, 299), controlPoint1: p(143, 303, 192, 265),
                     controlPoint2: p(144, 321, 188, 283))
        ink.withAlphaComponent(0.45).setStroke()
        crease.lineWidth = 3; crease.lineCapStyle = .round; crease.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // The whole original face is scaled uniformly; X/check and mouth keep
        // their handedness and proportions while the body turns to the side.
        NSGraphicsContext.saveGraphicsState()
        images["sit"]?.draw(in: CGRect(x: -3 * arrival, y: 2 * arrival,
                                       width: 400 - 28 * arrival, height: 226 - 15.82 * arrival),
                             from: CGRect(x: 0, y: 174, width: 400, height: 226),
                             operation: .sourceOver, fraction: 1, respectFlipped: true,
                             hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawLimb(from root: CGPoint, through bend: CGPoint, to foot: CGPoint, width: CGFloat) {
        let leg = NSBezierPath()
        leg.move(to: root)
        leg.curve(to: foot, controlPoint1: bend, controlPoint2: bend)
        fur.setStroke(); leg.lineWidth = width; leg.lineCapStyle = .round; leg.stroke()
    }

    private func drawOriginalPaw(_ index: Int, at point: CGPoint, scale: CGFloat) {
        let anchors = [CGPoint(x: 102, y: 310), CGPoint(x: 163, y: 331),
                       CGPoint(x: 271, y: 331), CGPoint(x: 321, y: 318)]
        NSGraphicsContext.saveGraphicsState()
        let move = NSAffineTransform()
        move.translateX(by: point.x - anchors[index].x * scale, yBy: point.y - anchors[index].y * scale)
        move.scale(by: scale); move.concat()
        drawImage("walk-foot-\(index)")
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSettling() {
        let pulse = reduceMotion || phase >= 0.24 ? 0 : sin(max(0, phase) / 0.24 * .pi)
        NSGraphicsContext.saveGraphicsState()
        let land = NSAffineTransform()
        land.translateX(by: 200, yBy: 367)
        land.scaleX(by: 1 + 0.018 * pulse, yBy: 1 - 0.028 * pulse)
        land.translateX(by: -200, yBy: -367); land.concat()
        drawImage("sit")
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
    func renderPNG(pose: DesktopPetPose, phase: Double = 0, facingLeft: Bool = false, walkDistance: CGFloat = 0,
                   carryLean: CGFloat = 0, isSettling: Bool = false) -> Data {
        self.pose = pose
        self.phase = phase
        self.facingLeft = facingLeft
        self.walkDistance = walkDistance
        self.carryLean = carryLean
        self.isSettling = isSettling
        let image = NSImage(size: bounds.size, flipped: true) { _ in self.draw(self.bounds); return true }
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return bitmap.representation(using: .png, properties: [:])!
    }
    var loadedAssets: Set<String> { Set(images.keys) }
    #endif
}
