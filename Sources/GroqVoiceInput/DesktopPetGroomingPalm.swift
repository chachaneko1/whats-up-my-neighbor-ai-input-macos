import Foundation

/// Palm-led abstraction: the foreleg remains hidden by the torso/head.
/// Only a rounded palm and short wrist are visible below the mouth.
struct DesktopPetGroomingPalm {
    let center: CGPoint
    let angle: CGFloat
    let activity: CGFloat
    let lick: CGFloat
    var headTilt: CGFloat { -3 * activity + 1.5 * lick }
    var headDrop: CGFloat { 9 * activity + 2 * lick }

    static func sample(time: Double, reduceMotion: Bool = false) -> Self {
        func ease(_ t: Double) -> CGFloat {
            let t = CGFloat(max(0, min(1, t)))
            return t * t * (3 - 2 * t)
        }
        func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        func curve(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u*u*u*a.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*d.x,
                           y: u*u*u*a.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*d.y)
        }
        let rest = CGPoint(x: 155, y: 346)
        let mouthPaw = CGPoint(x: 184, y: 235)
        if reduceMotion { return Self(center: mouthPaw, angle: 12, activity: 1, lick: 0) }
        let t = max(0, min(3.2, time.isFinite ? time : 0))
        if t < 0.65 {
            let u = ease(t / 0.65)
            return Self(center: curve(rest, CGPoint(x: 157, y: 307), CGPoint(x: 174, y: 247), mouthPaw, u),
                        angle: 12 * u, activity: u, lick: 0)
        }
        if t < 2.45 {
            // Four gentle tongue strokes. The palm holds below the muzzle;
            // a tiny yielding motion replaces the previous cheek-wide wipe.
            let cycle = max(0, min(4, (t - 0.75) / 0.4))
            let wave = sin(.pi * (cycle - floor(cycle)))
            let lick = CGFloat(wave * wave)
            return Self(center: mix(mouthPaw, CGPoint(x: 184, y: 236.2), lick),
                        angle: 12, activity: 1, lick: lick)
        }
        let u = ease((t - 2.45) / 0.75)
        return Self(center: curve(mouthPaw, CGPoint(x: 176, y: 264), CGPoint(x: 157, y: 307), rest, u),
                    angle: 12 * (1 - u), activity: 1 - u, lick: 0)
    }
}
