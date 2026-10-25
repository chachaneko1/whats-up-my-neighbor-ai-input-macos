import Foundation

/// Articulated pose amounts shared by the model and native renderer. Capturing
/// these on release/re-grab preserves the exact silhouette, even mid-pickup.
struct DesktopPetLift: Equatable {
    var shoulder: CGFloat = 0
    var hip: CGFloat = 0
    var paws: CGFloat = 0
    var lean: CGFloat = 0
    var spriteFrame: CGFloat = 0

    static let frameInterval: Double = 0.05
    static let carryFrame: CGFloat = 15
    static let lastFrame: CGFloat = 23
    static let pickupDuration: Double = 0.85
    static let landingDuration: Double = 0.80

    // Logical positions identify complete Gemini PNGs, never interpolated poses.
    // Only source 08→10 expands to 200ms, with dwell intervals in 1/60s units for
    // the five unevenly spaced drawings. Remaining pickup drawings stay 50ms;
    // selected landing drawings use 100ms each without the rebound tail.
    static let framePositions: [CGFloat] = [
        0, 1, 2, 3, 4, 5, 6, 7,
        7.333333333333333, 7.666666666666667, 8,
        8.333333333333334, 8.666666666666666,
        9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
        19, 20, 21, 22, 23
    ]

    static let frameTimes: [Double] = [
        0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35,
        0.416666666666667, 0.433333333333333, 0.45,
        0.483333333333333, 0.516666666666667,
        0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.95,
        1.05, 1.15, 1.25, 1.35, 1.45, 1.55, 1.65
    ]

    // Keep pickup and the first landing drawings, then the original native
    // resting frame 35. Website frame 00 is smaller and must not replace it.
    // Timeline positions stay distinct so a re-grab can reverse from rest.
    // Landing holds each selected drawing for 100ms, preserving its 800ms total.
    static let sourceImageIndices: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
        14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 35
    ]

    static func time(for position: CGFloat) -> Double { frameTimes[imageIndex(for: position)] }

    static func imageIndex(for position: CGFloat) -> Int {
        framePositions.indices.min { abs(framePositions[$0] - position) < abs(framePositions[$1] - position) } ?? 0
    }

    static func sourceImageIndex(for position: CGFloat) -> Int {
        sourceImageIndices[imageIndex(for: position)]
    }

    static func travel(from start: CGFloat, to end: CGFloat, elapsed: Double) -> CGFloat {
        let startIndex = imageIndex(for: start), endIndex = imageIndex(for: end)
        let forward = endIndex >= startIndex
        let target = frameTimes[startIndex] + (forward ? 1 : -1) * max(0, elapsed)
        let tolerance = 0.0000001
        if forward {
            let index = (startIndex...endIndex).last { frameTimes[$0] <= target + tolerance } ?? startIndex
            return framePositions[index]
        }
        let index = (endIndex...startIndex).first { frameTimes[$0] >= target - tolerance } ?? startIndex
        return framePositions[index]
    }

    static func ease(_ elapsed: Double, delay: Double = 0, duration: Double) -> CGFloat {
        let t = max(0, min(1, (elapsed - delay) / duration))
        return CGFloat(t * t * (3 - 2 * t))
    }

    static func lifting(from start: Self = Self(), elapsed: Double, lean: CGFloat) -> Self {
        Self(shoulder: start.shoulder + (1 - start.shoulder) * ease(elapsed, duration: 0.14),
             hip: start.hip + (1 - start.hip) * ease(elapsed, delay: 0.04, duration: 0.21),
             paws: start.paws + (1 - start.paws) * ease(elapsed, delay: 0.085, duration: 0.23),
             lean: lean,
             spriteFrame: travel(from: start.spriteFrame, to: carryFrame, elapsed: elapsed))
    }

    var returnFrame: CGFloat { spriteFrame >= Self.carryFrame ? Self.lastFrame : 0 }
    var returnDuration: Double { abs(Self.time(for: returnFrame) - Self.time(for: spriteFrame)) }
    func landing(elapsed: Double) -> Self {
        let duration = returnDuration
        // The terminal position preserves the original native resting PNG
        // and its visible size, omitting only the intervening rebound tail.
        if elapsed >= duration { return Self(spriteFrame: returnFrame) }
        return Self(shoulder: shoulder * (1 - Self.ease(elapsed, duration: duration)),
             hip: hip * (1 - Self.ease(elapsed, duration: duration)),
             paws: paws * (1 - Self.ease(elapsed, duration: duration)),
             lean: lean * (1 - Self.ease(elapsed, duration: duration)),
             spriteFrame: Self.travel(from: spriteFrame, to: returnFrame, elapsed: elapsed))
    }
}
