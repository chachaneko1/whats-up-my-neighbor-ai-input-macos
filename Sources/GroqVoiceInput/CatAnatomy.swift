import Foundation

/// Coordinates are top-left, in the original artwork. These are masks clipped
/// to the source alpha, never replacement silhouettes or animation keyframes.
// 解剖遮罩取樣架構（Anatomical Coordinate Mapping）：
// 將原畫素材像素座標歸一化為部位局部幾何座標（u, v 介於 0~1）；
// 關鍵區分：
// 1. HeadProfile.desktop：對應桌面貓咪圓臉姿態。
// 2. HeadProfile.recording：對應全螢幕 HUD 的修長下顎與耳部輪廓，使虎斑與三花紋路在不同資產上精確對齊特徵點。
enum CatAnatomy {
    enum HeadProfile { case desktop, recording }
    struct Sample {
        let part: CatBodyPart
        let u: Double
        let v: Double
        var headProfile: HeadProfile = .desktop
    }
    struct PickupMap: Codable {
        let frame: Int
        let head: [Double]
        let body: [Double]
        let tail: [Double]
        /// x/y/width/height of each visible foreleg, then each hind leg.
        let legs: [[Double]]
    }
    enum Layout {
        case desktop(String)
        case pickup(PickupMap)
        case hud
        case part(CatBodyPart)
    }
    static let legParts: [CatBodyPart] = [.frontLeftLeg, .frontRightLeg, .rearLeftLeg, .rearRightLeg]
    static let pawParts: [CatBodyPart] = [.frontLeftPaw, .frontRightPaw, .rearLeftPaw, .rearRightPaw]

    static func pickupMaps(at url: URL?) -> [PickupMap]? {
        guard let url, let data = try? Data(contentsOf: url), data.count < 64 * 1024,
              let maps = try? JSONDecoder().decode([PickupMap].self, from: data), maps.count == 36,
              maps.enumerated().allSatisfy({ index, map in
                  map.frame == index && map.legs.count == 4 && ([map.head, map.body, map.tail] + map.legs).allSatisfy {
                      $0.count == 4 && $0.allSatisfy { $0.isFinite && abs($0) <= 1000 } && $0[2] > 0 && $0[3] > 0
                  }
              }) else { return nil }
        return maps
    }

    private static func inside(_ x: Double, _ y: Double, _ r: [Double]) -> Bool {
        let u = (x - r[0]) / r[2] * 2 - 1, v = (y - r[1]) / r[3] * 2 - 1
        return u * u + v * v <= 1
    }
    private static func sample(_ part: CatBodyPart, _ x: Double, _ y: Double, _ r: [Double]) -> Sample {
        Sample(part: part, u: (x - r[0]) / r[2], v: (y - r[1]) / r[3])
    }

    static func sample(x: Double, y: Double, width: Double, height: Double, layout: Layout,
                       forcedPart: CatBodyPart? = nil) -> Sample {
        switch layout {
        case .part(let part): return Sample(part: part, u: x / width, v: y / height)
        case .hud:
            // The elongated recording artwork exposes only the head and ears.
            var sample = head(x / width, y / height, muzzleTop: 0.64)
            sample.headProfile = .recording
            return sample
        case .pickup(let map):
            if y < map.head[1] + map.head[3] {
                return head((x - map.head[0]) / map.head[2], (y - map.head[1]) / map.head[3])
            }
            for i in 0..<4 where inside(x, y, map.legs[i]) {
                let r = map.legs[i]
                // Rounded toes, rather than a rectangular stripe across the bib.
                let paw = [r[0], r[1] + r[3] * 0.62, r[2], r[3] * 0.40]
                return sample(inside(x, y, paw) ? pawParts[i] : legParts[i], x, y, map.body)
            }
            if inside(x, y, map.tail), x > map.body[0] + map.body[2] * 0.88 {
                return sample(.tail, x, y, map.tail)
            }
            return torso(x, y, map.body)
        case .desktop(let asset):
            var x = x / width * 400, y = y / height * 400
            if asset == "tail" { return Sample(part: .tail, u: x / 400, v: y / 400) }
            if asset == "body" { x = x / 400 * 250.868 + 74.5272; y = y / 400 * 163 + 203 }
            let walking = asset.hasPrefix("walk")
            let bodyBounds: [Double] = [75, 203, 252, 164]
            if forcedPart == .tail {
                return sample(.tail, x, y, walking ? [305, 115, 90, 144] : [272, 231.8, 102.329, 96.204])
            }
            if let forcedPart, pawParts.contains(forcedPart) { return sample(forcedPart, x, y, bodyBounds) }
            if forcedPart == .body {
                if !walking {
                    for (part, r) in [(CatBodyPart.frontLeftLeg, [110.0, 260, 62, 106]), (.frontRightLeg, [230.0, 260, 62, 106])]
                        where inside(x, y, r) { return sample(part, x, y, bodyBounds) }
                }
                return torso(x, y, bodyBounds)
            }
            if asset.hasPrefix("walk-foot-"), let i = Int(asset.suffix(1)), (0..<4).contains(i) {
                let bounds: [[Double]] = [[70, 275, 63, 73], [135, 297, 57, 69], [244, 293, 62, 73], [300, 275, 61, 85]]
                let r = bounds[i]
                return sample(y > r[1] + r[3] * 0.55 ? pawParts[i] : legParts[i], x, y, bodyBounds)
            }
            if let forcedPart, let i = legParts.firstIndex(of: forcedPart) {
                return sample(y > 329 ? pawParts[i] : legParts[i], x, y, bodyBounds)
            }
            let headX = walking ? x + 20 : x
            if y < 225 && asset != "body" && asset != "groom-body" && asset != "walk-body" && asset != "walk-paws" {
                return head((headX - 45) / 312, (y - 18) / 208)
            }
            if walking && x > 349 { return sample(.tail, x, y, [307, 115, 88, 144]) }
            if !walking && x > 324 { return sample(.tail, x, y, [272, 231.8, 102.329, 96.204]) }
            if walking && y > 294 {
                let i = x < 133 ? 0 : x < 215 ? 1 : x < 302 ? 2 : 3
                return sample(y > 333 ? pawParts[i] : legParts[i], x, y, bodyBounds)
            }
            if !walking && y > 336 {
                let i = x < 126 ? 2 : x < 200 ? 0 : x < 276 ? 1 : 3
                return sample(pawParts[i], x, y, bodyBounds)
            }
            if y > 265 && (x < 160 || x > 244) {
                return sample(x < 200 ? .frontLeftLeg : .frontRightLeg, x, y, bodyBounds)
            }
            return torso(x, y, [75, 203, 252, 164])
        }
    }

    private static func head(_ u: Double, _ v: Double, muzzleTop: Double = 0.68) -> Sample {
        if v < 0.27 && u < 0.35 { return Sample(part: .leftEar, u: u / 0.35, v: v / 0.27) }
        if v < 0.27 && u > 0.65 { return Sample(part: .rightEar, u: (u - 0.65) / 0.35, v: v / 0.27) }
        // A tapered blaze follows the nose rather than a rectangular face patch.
        let halfWidth = max(0, (v - muzzleTop) * 0.35)
        if v > muzzleTop && abs(u - 0.5) < halfWidth {
            return Sample(part: .muzzle, u: u, v: v)
        }
        return Sample(part: .head, u: u, v: v)
    }

    private static func torso(_ x: Double, _ y: Double, _ r: [Double]) -> Sample {
        let u = (x - r[0]) / r[2], v = (y - r[1]) / r[3]
        let halfWidth = 0.12 + 0.10 * sin(max(0, min(1, v)) * .pi)
        let part: CatBodyPart = abs(u - 0.5) < halfWidth ? (v < 0.48 ? .chest : .belly) : .body
        return Sample(part: part, u: u, v: v)
    }
}
