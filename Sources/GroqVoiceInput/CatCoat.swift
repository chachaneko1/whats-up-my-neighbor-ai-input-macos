import Foundation

/// A small visual inheritance model, not a biological genetics simulator.
/// Each locus keeps two inherited switches; a stable seed fixes patch placement.
struct CatCoat: Codable, Equatable {
    struct Pair: Codable, Equatable {
        var first: Bool
        var second: Bool
        var dominant: Bool { first || second }
        var recessive: Bool { first && second }
        var count: Int { (first ? 1 : 0) + (second ? 1 : 0) }
        static let off = Pair(first: false, second: false)
    }
    let version: Int
    let seed: UInt64
    let orange: Pair
    let dilution: Pair
    let tabby: Pair
    let spotting: Pair
    let white: Pair
    let point: Pair

    static let original = CatCoat(version: 1, seed: 0, orange: .off, dilution: .off,
                                  tabby: .off, spotting: .off, white: .off, point: .off)
    var isOriginal: Bool { self == .original }
    var isWhite: Bool { white.dominant }
    var isDilute: Bool { dilution.recessive }
    var isMosaic: Bool { orange.count == 1 && !isWhite }
    var isOrange: Bool { orange.count == 2 }
    var hasTabby: Bool { !isWhite && (tabby.dominant || isOrange) }
    var isPoint: Bool { point.recessive && !isWhite }
    var whiteLevel: Int { isWhite ? 3 : spotting.count }
    var title: String {
        if isOriginal { return "原版黑貓" }
        if isWhite { return "白貓" }
        if isMosaic { return whiteLevel > 0 ? (isDilute ? "淡三花貓" : "三花貓") : (isDilute ? "淡玳瑁貓" : "玳瑁貓") }
        if isPoint { return isDilute ? "淡重點色貓" : "重點色貓" }
        let base = isOrange ? (isDilute ? "奶油" : "橘") : (isDilute ? "灰" : "黑")
        if hasTabby { return base + "虎斑" + (whiteLevel > 0 ? "白襪貓" : "貓") }
        if whiteLevel > 0 { return isDilute ? "灰白貓" : "賓士貓" }
        return base + "貓"
    }
    var details: String {
        if isOriginal { return "最初熟悉的那隻小黑貓。" }
        if isWhite { return "白色覆蓋 · 原本的輪廓與表情" }
        var traits = [isMosaic ? "深色與橘色拼接" : (isOrange ? "橘色底" : "深色底")]
        if isDilute { traits.append("淡化") }
        if hasTabby { traits.append("虎斑") }
        if whiteLevel > 0 { traits.append(whiteLevel == 2 ? "大白斑" : "白胸與白襪") }
        if isPoint { traits.append("深色末端") }
        return traits.joined(separator: " · ")
    }
    var identifier: String { isOriginal ? "ORIGINAL" : String(format: "%016llX", seed) }

    static func draw<R: RandomNumberGenerator>(using rng: inout R) -> Self {
        let seed = UInt64.random(in: 1...UInt64.max, using: &rng)
        return generated(seed: seed)
    }
    static func generated(seed: UInt64) -> Self {
        var rng = CatCoatRandom(seed: seed)
        func pair(_ percent: UInt64) -> Pair {
            Pair(first: rng.next() % 100 < percent, second: rng.next() % 100 < percent)
        }
        return Self(version: 1, seed: seed, orange: pair(32), dilution: pair(42),
                    tabby: pair(33), spotting: pair(30), white: pair(3), point: pair(20))
    }
}

/// SplitMix64: identical seeds have identical markings on every launch.
struct CatCoatRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992 }
}

/// Only an explicit adoption writes this one preference. Reading old/corrupt
/// data falls back to the original, without modifying any stored preference.
final class CatCoatStore {
    static let key = "desktopCatCoat.v1"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> CatCoat {
        guard let data = defaults.data(forKey: Self.key), data.count < 8192,
              let coat = try? JSONDecoder().decode(CatCoat.self, from: data), coat.version == 1 else { return .original }
        return coat
    }
    func adopt(_ coat: CatCoat) {
        guard coat.version == 1, let data = try? JSONEncoder().encode(coat) else { return }
        defaults.set(data, forKey: Self.key)
    }
    func restoreOriginal() { defaults.removeObject(forKey: Self.key) }
}
