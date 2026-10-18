import Foundation

enum DesktopPetPose: String, CaseIterable {
    case sitting, standing, walking, curious, grooming, yawning, loafing, sleeping, petted, carried

    var description: String {
        switch self {
        case .sitting: return "安靜坐著"
        case .standing: return "站起來看看"
        case .walking: return "散步中"
        case .curious: return "有點好奇？"
        case .grooming: return "洗洗臉"
        case .petted: return "呼嚕～"
        case .carried: return "被拎起來了"
        case .yawning: return "打哈欠"
        case .loafing: return "趴著休息"
        case .sleeping: return "睡著了"
        }
    }
}

struct DesktopPetPerch: Equatable {
    let id: String
    let frame: CGRect
}

struct DesktopPetWorld {
    var areas: [CGRect]
    var perches: [DesktopPetPerch] = []
    var cursor: CGPoint = .zero
    var idleSeconds: TimeInterval = 0
    var hidden = false
    var reduceMotion = false
}

/// Articulated pose amounts shared by the model and native renderer. Capturing
/// these on release/re-grab preserves the exact silhouette, even mid-pickup.
struct DesktopPetLift: Equatable {
    var shoulder: CGFloat = 0
    var hip: CGFloat = 0
    var paws: CGFloat = 0
    var lean: CGFloat = 0

    static func ease(_ elapsed: Double, delay: Double = 0, duration: Double) -> CGFloat {
        let t = max(0, min(1, (elapsed - delay) / duration))
        return CGFloat(t * t * (3 - 2 * t))
    }

    static func lifting(from start: Self = Self(), elapsed: Double, lean: CGFloat) -> Self {
        Self(shoulder: start.shoulder + (1 - start.shoulder) * ease(elapsed, duration: 0.14),
             hip: start.hip + (1 - start.hip) * ease(elapsed, delay: 0.04, duration: 0.21),
             paws: start.paws + (1 - start.paws) * ease(elapsed, delay: 0.085, duration: 0.23),
             lean: lean)
    }

    func landing(elapsed: Double) -> Self {
        Self(shoulder: shoulder * (1 - Self.ease(elapsed, duration: 0.22)),
             hip: hip * (1 - Self.ease(elapsed, duration: 0.22)),
             paws: paws * (1 - Self.ease(elapsed, duration: 0.22)),
             lean: lean * (1 - Self.ease(elapsed, duration: 0.22)))
    }
}

/// A local animation model: no input events, file access, microphone or network.
struct DesktopPetModel {
    static let size = CGSize(width: 128, height: 128)
    static let feetInset: CGFloat = 2
    private(set) var released = false
    private(set) var visible = false
    private(set) var pose: DesktopPetPose = .sitting
    private(set) var origin = CGPoint.zero
    private(set) var facingLeft = false
    private(set) var phase: Double = 0
    private(set) var walkDistance: CGFloat = 0
    private(set) var perchID: String?
    private var nextAction: TimeInterval = 0
    private var poseStarted: TimeInterval = 0
    private var lastTick: TimeInterval?
    private var wasPaused = true
    private var wasActive = true
    private var cycle = 0
    private var seed: UInt64
    private var journey: Journey?
    private(set) var isPressed = false
    private(set) var isDragging = false
    private(set) var carryLean: CGFloat = 0
    private(set) var isSettling = false
    private(set) var lift = DesktopPetLift()
    private var liftStart = DesktopPetLift()
    private var petAfterLanding = false
    private var lastDragPoint = CGPoint.zero
    private var lastDragTime: TimeInterval?
    private var pressPoint = CGPoint.zero
    private var pressOrigin = CGPoint.zero
    private var interactionUntil: TimeInterval?
    static let dragThreshold: CGFloat = 5

    /// Only explicit pointer-down/up events call these methods. Mouse movement
    /// alone never changes the origin, heading, or animation destination.
    mutating func pointerDown(at point: CGPoint, now: TimeInterval, world: DesktopPetWorld) {
        guard released, visible, !world.hidden, point.x.isFinite, point.y.isFinite, now.isFinite else { return }
        isPressed = true
        isDragging = false
        // A press during landing freezes that exact silhouette until click or
        // drag decides the next state. It must not snap to the sitting asset.
        carryLean = lift.lean
        petAfterLanding = false
        lastDragPoint = point
        lastDragTime = now
        pressPoint = point
        pressOrigin = origin
        journey = nil
        interactionUntil = nil
        lastTick = now
    }

    mutating func pointerDragged(to point: CGPoint, now: TimeInterval, world: DesktopPetWorld) {
        guard isPressed, !world.hidden, point.x.isFinite, point.y.isFinite, now.isFinite,
              let area = validAreas(world).first(where: { $0.contains(point) })
                ?? validAreas(world).min(by: { distance($0.center, point) < distance($1.center, point) }) else { return }
        guard isDragging || distance(point, pressPoint) >= Self.dragThreshold else { return }
        let startingDrag = !isDragging
        if startingDrag {
            liftStart = lift
            isSettling = false
            setPose(.carried, now: now, duration: .infinity)
        }
        if !startingDrag, let previous = lastDragTime, now > previous, now - previous <= 0.3, !world.reduceMotion {
            let speed = (point.x - lastDragPoint.x) / CGFloat(now - previous)
            let target = max(-5, min(5, speed / 160))
            carryLean = carryLean * 0.6 + target * 0.4
        } else if world.reduceMotion { carryLean = 0 }
        lastDragPoint = point
        lastDragTime = now
        isDragging = true
        perchID = nil
        origin = Self.clamp(CGPoint(x: pressOrigin.x + point.x - pressPoint.x,
                                   y: pressOrigin.y + point.y - pressPoint.y), to: area)
        phase = world.reduceMotion ? 0 : max(0, now - poseStarted)
        lift = world.reduceMotion ? DesktopPetLift(shoulder: 1, hip: 1, paws: 1)
            : .lifting(from: liftStart, elapsed: phase, lean: carryLean)
    }

    mutating func pointerUp(now: TimeInterval, world: DesktopPetWorld) {
        guard isPressed else { return }
        let wasDragging = isDragging
        let resumeLanding = !wasDragging && isSettling && lift != DesktopPetLift() && !world.reduceMotion
        let releasedLift = lift
        cancelPointer(now: now)
        guard released, !world.hidden else { return }
        let landing = wasDragging || resumeLanding
        setPose(landing ? .sitting : .petted, now: now, duration: landing ? 2 : 1.6)
        isSettling = landing && !world.reduceMotion
        if isSettling { liftStart = releasedLift; lift = releasedLift }
        petAfterLanding = resumeLanding
        interactionUntil = now + (landing ? 2 : 1.6)
        lastTick = now
        wasPaused = false
    }

    mutating func cancelPointer(now: TimeInterval) {
        isPressed = false
        isDragging = false
        carryLean = 0
        isSettling = false
        lift = DesktopPetLift()
        liftStart = DesktopPetLift()
        petAfterLanding = false
        lastDragTime = nil
        interactionUntil = nil
        setPose(.sitting, now: now, duration: 2)
    }

    /// A preview control, never called by hover or cursor tracking.
    mutating func demonstrate(_ pose: DesktopPetPose, now: TimeInterval, world: DesktopPetWorld) {
        guard released, !world.hidden, !isPressed else { return }
        lift = DesktopPetLift()
        isSettling = false
        petAfterLanding = false
        journey = nil
        wasPaused = false
        wasActive = true
        lastTick = now
        if pose == .walking, let area = validAreas(world).first(where: { $0.contains(frame) }) {
            wasActive = false
            beginWalk(now: now, area: area, world: world)
            interactionUntil = now + 10
        } else {
            setPose(pose, now: now, duration: 4)
            interactionUntil = now + 4
        }
    }

    private struct Journey {
        var from: CGPoint
        var to: CGPoint
        var started: TimeInterval
        var duration: TimeInterval
        var perch: String?
    }

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { self.seed = seed }

    var frame: CGRect { CGRect(origin: origin, size: Self.size) }
    var isTravelling: Bool { journey != nil }

    mutating func setReleased(_ value: Bool, now: TimeInterval, world: DesktopPetWorld) {
        released = value
        cancelPointer(now: now)
        journey = nil
        perchID = nil
        lastTick = nil
        wasPaused = true
        wasActive = true
        if value, let area = validAreas(world).first(where: { $0.contains(world.cursor) }) ?? validAreas(world).first {
            origin = CGPoint(x: area.maxX - Self.size.width - 22, y: area.minY)
        }
        setPose(.sitting, now: now, duration: 2)
        tick(now: now, world: world)
    }

    mutating func tick(now: TimeInterval, world: DesktopPetWorld) {
        guard now.isFinite else { return }
        let areas = validAreas(world)
        guard released, !world.hidden, !areas.isEmpty else {
            if isPressed || interactionUntil != nil { cancelPointer(now: now) }
            visible = false
            wasPaused = true
            lastTick = now
            return
        }
        let area = areas.first(where: { $0.insetBy(dx: -1, dy: -1).contains(frame.origin) })
            ?? areas.min(by: { distance($0.center, origin) < distance($1.center, origin) })!
        origin = Self.clamp(origin, to: area)
        if let id = perchID, !world.perches.contains(where: { $0.id == id }) {
            landOnEdge(area)
        }
        let delta = lastTick.map { max(0, min(0.2, now - $0)) } ?? 0
        let gap = lastTick.map { now < $0 || now - $0 > 2 } ?? false
        lastTick = now
        if wasPaused || gap {
            wasPaused = false
            if journey != nil || perchID != nil { landOnEdge(area) }
            setPose(.sitting, now: now, duration: 2)
        }
        // Remain available for an intentional click. The controller makes only
        // the opaque cat silhouette receive mouse events; padding passes through.
        visible = true
        if isPressed {
            if world.reduceMotion && !isDragging && isSettling {
                lift = DesktopPetLift()
                liftStart = DesktopPetLift()
                isSettling = false
                petAfterLanding = false
                setPose(.sitting, now: now, duration: 2)
            }
            if isDragging {
                carryLean = world.reduceMotion ? 0 : carryLean * CGFloat(exp(-delta * 7))
                phase = world.reduceMotion ? 0 : max(0, now - poseStarted)
                lift = world.reduceMotion ? DesktopPetLift(shoulder: 1, hip: 1, paws: 1)
                    : .lifting(from: liftStart, elapsed: phase, lean: carryLean)
            }
            return
        }
        if let until = interactionUntil {
            if now < until, journey == nil {
                phase = world.reduceMotion ? 0 : max(0, now - poseStarted)
                if isSettling {
                    lift = world.reduceMotion ? DesktopPetLift() : liftStart.landing(elapsed: phase)
                    if world.reduceMotion || phase >= 0.36 {
                        isSettling = false
                        if petAfterLanding {
                            petAfterLanding = false
                            setPose(.petted, now: now, duration: 1.6)
                            interactionUntil = now + 1.6
                        }
                    }
                }
                return
            }
            if now >= until {
                interactionUntil = nil
                isSettling = false
                if journey == nil { setPose(.sitting, now: now, duration: 2) }
            }
        }
        let active = !world.idleSeconds.isFinite || world.idleSeconds < 12
        if (active && interactionUntil == nil) || world.reduceMotion {
            if journey != nil || perchID != nil { landOnEdge(area) }
            if !wasActive || world.reduceMotion {
                cycle = 0
                setPose(world.reduceMotion && world.idleSeconds > 60 ? .sleeping : .sitting,
                        now: now, duration: 2)
            }
            wasActive = true
            phase = 0
            return
        }
        if wasActive {
            wasActive = false
            setPose(.sitting, now: now, duration: 1.8)
        }
        phase = max(0, now - poseStarted)
        if let move = journey {
            if let id = move.perch, !world.perches.contains(where: { $0.id == id }) {
                landOnEdge(area)
                setPose(.standing, now: now, duration: 2)
                return
            }
            let progress = max(0, min(1, (now - move.started) / move.duration))
            let eased = progress * progress * (3 - 2 * progress)
            origin = CGPoint(x: move.from.x + (move.to.x - move.from.x) * eased,
                             y: move.from.y + (move.to.y - move.from.y) * eased)
            if abs(move.to.y - move.from.y) > 3 {
                origin.y += sin(progress * .pi) * min(45, area.height * 0.08)
            }
            origin = Self.clamp(origin, to: area)
            walkDistance = abs(origin.x - move.from.x)
            if progress >= 1 {
                origin = move.to
                perchID = move.perch
                journey = nil
                setPose(cycle % 3 == 0 ? .curious : .standing, now: now, duration: 2.2)
            }
            return
        }
        guard now >= nextAction else { return }
        switch pose {
        case .sitting: setPose(.standing, now: now, duration: 1.8)
        case .standing where cycle == 0: beginWalk(now: now, area: area, world: world)
        case .walking, .curious, .standing: setPose(.grooming, now: now, duration: 3.2)
        case .grooming: setPose(.yawning, now: now, duration: 3.2)
        case .yawning: setPose(.loafing, now: now, duration: 5)
        case .loafing: setPose(.sleeping, now: now, duration: 18 + random() * 16)
        case .sleeping: beginWalk(now: now, area: area, world: world)
        case .petted, .carried: setPose(.sitting, now: now, duration: 2)
        }
    }

    private mutating func beginWalk(now: TimeInterval, area: CGRect, world: DesktopPetWorld) {
        cycle += 1
        let candidates = world.perches.filter { perch in
            let point = CGPoint(x: perch.frame.midX - Self.size.width / 2,
                                y: perch.frame.maxY - Self.feetInset)
            return area.contains(CGRect(origin: point, size: Self.size)) &&
                perch.id != perchID && distance(perch.frame.center, world.cursor) > 100
        }
        let selected = !candidates.isEmpty && cycle % 2 == 1
            ? candidates[Int(random() * Double(candidates.count)) % candidates.count] : nil
        let target = selected.map { CGPoint(x: $0.frame.midX - Self.size.width / 2,
                                           y: $0.frame.maxY - Self.feetInset) }
            ?? CGPoint(x: area.minX + CGFloat(random()) * (area.width - Self.size.width), y: area.minY)
        let destination = Self.clamp(target, to: area)
        facingLeft = destination.x < origin.x
        walkDistance = 0
        let duration = max(2, min(9, Double(distance(origin, destination)) / 70))
        journey = Journey(from: origin, to: destination, started: now, duration: duration, perch: selected?.id)
        perchID = nil
        setPose(.walking, now: now, duration: duration)
    }

    private mutating func landOnEdge(_ area: CGRect) {
        journey = nil
        perchID = nil
        origin = Self.clamp(CGPoint(x: origin.x, y: area.minY), to: area)
    }

    private mutating func setPose(_ pose: DesktopPetPose, now: TimeInterval, duration: TimeInterval) {
        self.pose = pose
        poseStarted = now
        nextAction = now + duration
        phase = 0
    }

    private mutating func random() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(UInt64(1) << 53)
    }

    private func validAreas(_ world: DesktopPetWorld) -> [CGRect] {
        world.areas.filter { $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite &&
            $0.width >= Self.size.width && $0.height >= Self.size.height }
    }

    static func clamp(_ point: CGPoint, to area: CGRect) -> CGPoint {
        CGPoint(x: max(area.minX, min(point.x, area.maxX - size.width)),
                y: max(area.minY, min(point.y, area.maxY - size.height)))
    }

    static func appKitFrame(topLeft rect: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}

private extension CGRect { var center: CGPoint { CGPoint(x: midX, y: midY) } }
