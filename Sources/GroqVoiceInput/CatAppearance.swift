import Foundation
import CoreFoundation

/// Display-only anatomy. Left/right refer to the front-view artwork, not ownership.
enum CatBodyPart: String, CaseIterable {
    case head, leftEar, rightEar, muzzle, chest, belly, body
    case frontLeftLeg, frontRightLeg, rearLeftLeg, rearRightLeg
    case frontLeftPaw, frontRightPaw, rearLeftPaw, rearRightPaw, tail
}

enum CatPattern: String, CaseIterable {
    case none, tabby, patches, calico, whiteSpots, point
}

struct CatPartStyle: Equatable {
    var color: String
    var pattern: CatPattern = .none
    var patternColor: String = "#C88C4E"
}

/// Immutable, fully resolved preset + overrides. No accounts, draws or writes.
struct CatAppearance: Equatable {
    // 花色預設與部位風格規格：
    // 預設 9 種官方認證花色（原版黑貓、黑貓、白貓、灰貓、橘虎斑、賓士貓、三花貓、玳瑁貓、重點色貓）；
    // 劃分 16 個獨立解剖部位（CatBodyPart），支援純色、虎斑、斑塊、三花、白斑與重點色紋理。
    static let presetIDs = ["original", "black", "white", "blue", "orange-tabby", "tuxedo", "calico", "tortoiseshell", "colorpoint"]
    static let presetNames = ["原版黑貓", "黑貓", "白貓", "灰貓", "橘虎斑", "賓士貓", "三花貓", "玳瑁貓", "重點色貓"]
    let preset: String
    let seed: UInt32
    private(set) var parts: [CatBodyPart: CatPartStyle]
    static let original = makePreset("original")!
    var isOriginal: Bool { parts == Self.original.parts }
    var title: String { Self.presetNames[Self.presetIDs.firstIndex(of: preset) ?? 0] }
    subscript(_ part: CatBodyPart) -> CatPartStyle { parts[part]! }

    static func makePreset(_ id: String, seed: UInt32 = 1) -> CatAppearance? {
        guard presetIDs.contains(id) else { return nil }
        let base: String
        switch id {
        case "original": base = "#101114"
        case "black": base = "#242323"
        case "white", "calico": base = "#F4EFE5"
        case "blue": base = "#8D9295"
        case "orange-tabby": base = "#D6A366"
        case "tuxedo": base = "#292828"
        case "tortoiseshell": base = "#3C3530"
        default: base = "#E2D3BA"
        }
        let pattern: CatPattern = id == "orange-tabby" ? .tabby : id == "calico" ? .calico : id == "tortoiseshell" ? .patches : .none
        let secondary = id == "orange-tabby" ? "#9A5F2D" : id == "tortoiseshell" ? "#B77D42" : "#C88C4E"
        var parts = Dictionary(uniqueKeysWithValues: CatBodyPart.allCases.map {
            ($0, CatPartStyle(color: base, pattern: pattern, patternColor: secondary))
        })
        let paws: [CatBodyPart] = [.frontLeftPaw, .frontRightPaw, .rearLeftPaw, .rearRightPaw]
        if id == "orange-tabby" {
            for part in [CatBodyPart.leftEar, .rightEar, .muzzle] { parts[part] = CatPartStyle(color: base) }
        }
        if id == "tuxedo" {
            for part in [.muzzle, .chest, .belly] + paws { parts[part] = CatPartStyle(color: "#F4EFE5") }
        }
        if id == "calico" {
            for part in [.muzzle, .chest, .belly] + paws { parts[part] = CatPartStyle(color: "#F4EFE5") }
            parts[.leftEar] = CatPartStyle(color: "#C88C4E")
            parts[.rightEar] = CatPartStyle(color: "#393431")
        }
        if id == "colorpoint" {
            for part in [.leftEar, .rightEar, .tail] + paws {
                parts[part] = CatPartStyle(color: "#685145")
            }
            parts[.muzzle] = CatPartStyle(color: "#806659")
            parts[.head] = CatPartStyle(color: base, pattern: .point, patternColor: "#806659")
        }
        return CatAppearance(preset: id, seed: seed, parts: parts)
    }

    enum Invalid: Error { case appearance }

    static func parse(_ value: Any) throws -> CatAppearance {
        // 嚴格型別校驗防護（Strict Type Parsing）：
        // 1. 嚴格檢查 JSON 鍵值白名單（preset、seed、parts），拒絕未知屬性。
        // 2. 種子值 seed 必須為非負整數（排除 CFBoolean 與浮點數 f/d 標記），防止解析歧義。
        // 3. 各部位覆寫僅接受 color、pattern、patternColor 三個欄位，格式錯誤時整批拋出例外安全退回預設。
        guard let object = value as? [String: Any],
              Set(object.keys).isSubset(of: ["preset", "seed", "parts"]),
              let id = object["preset"] as? String else { throw Invalid.appearance }
        var seed: UInt32 = 1
        if let value = object["seed"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  !["f", "d"].contains(String(cString: number.objCType)),
                  number.doubleValue >= 0, number.doubleValue <= Double(UInt32.max) else { throw Invalid.appearance }
            seed = number.uint32Value
        }
        guard var appearance = makePreset(id, seed: seed) else { throw Invalid.appearance }
        if let value = object["parts"] {
            guard let overrides = value as? [String: Any] else { throw Invalid.appearance }
            for (key, value) in overrides {
                guard let part = CatBodyPart(rawValue: key), let fields = value as? [String: Any],
                      Set(fields.keys).isSubset(of: ["color", "pattern", "patternColor"]) else { throw Invalid.appearance }
                var style = appearance[part]
                if let color = fields["color"] { style.color = try hex(color) }
                if let color = fields["patternColor"] { style.patternColor = try hex(color) }
                if let value = fields["pattern"] {
                    guard let name = value as? String, let pattern = CatPattern(rawValue: name) else { throw Invalid.appearance }
                    style.pattern = pattern
                }
                appearance.parts[part] = style
            }
        }
        return appearance
    }

    private static func hex(_ value: Any) throws -> String {
        guard let text = value as? String, text.utf8.count == 7, text.first == "#",
              text.dropFirst().utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw Invalid.appearance }
        return text.uppercased()
    }

    /// Full editable examples; every anatomical feature is filled explicitly.
    var jsonObject: [String: Any] {
        ["preset": preset, "seed": seed, "parts": Dictionary(uniqueKeysWithValues: CatBodyPart.allCases.map { part in
            (part.rawValue, ["color": self[part].color, "pattern": self[part].pattern.rawValue,
                             "patternColor": self[part].patternColor])
        })]
    }
}
