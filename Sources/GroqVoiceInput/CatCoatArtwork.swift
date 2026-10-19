import AppKit

/// Color layers are clipped to each ORIGINAL fur path, before subsequent
/// original parts and facial strokes. No silhouette or expression is redrawn.
struct CatCoatArtwork {
    struct Patch {
        let rect: CGRect
        let color: String
        func contains(_ p: CGPoint) -> Bool {
            let x = (p.x - rect.midX) / (rect.width / 2), y = (p.y - rect.midY) / (rect.height / 2)
            return x * x + y * y <= 1
        }
        var svg: String {
            "<ellipse cx=\"\(rect.midX)\" cy=\"\(rect.midY)\" rx=\"\(rect.width / 2)\" ry=\"\(rect.height / 2)\" fill=\"\(color)\"/>"
        }
    }
    let coat: CatCoat
    private let patches: [Patch]
    var base: String {
        if coat.isOriginal { return "#101114" }
        if coat.isWhite { return "#F4EFE5" }
        if coat.isPoint { return coat.isDilute ? "#E0DCD2" : "#E2D3BA" }
        if coat.isOrange { return coat.isDilute ? "#E6CDA6" : "#D6A366" }
        return coat.isDilute ? "#8D9295" : "#35302D"
    }
    var stripe: String { coat.isOrange ? (coat.isDilute ? "#C5A67A" : "#9A5F2D") : (coat.isDilute ? "#676D72" : "#171717") }
    var line: String { Self.isLight(base) ? "#9B8976" : "#786B5F" }
    var fur: NSColor { Self.color(base) }
    var ink: NSColor { Self.color(ink(at: CGPoint(x: 201, y: 191))) }

    init(_ coat: CatCoat) {
        self.coat = coat
        var rng = CatCoatRandom(seed: coat.seed ^ 0x434154434F4154)
        var patches: [Patch] = []
        if !coat.isWhite {
            if coat.isMosaic {
                let ginger = coat.isDilute ? "#E3C59B" : "#C58B50"
                // Rounded, overlapping patches with seed-dependent position
                // and size; stable anatomical coordinates keep all poses related.
                for i in 0..<11 {
                    let x = i < 5 ? 55 + rng.unit() * 260 : 80 + rng.unit() * 240
                    let y = i < 5 ? 30 + rng.unit() * 160 : 235 + rng.unit() * 120
                    let w = 40 + rng.unit() * 78, h = 35 + rng.unit() * 75
                    patches.append(Patch(rect: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h), color: ginger))
                }
            }
            if coat.isPoint {
                let point = coat.isDilute ? "#84848B" : "#685145"
                patches += [Patch(rect: CGRect(x: 45, y: -23, width: 107, height: 119), color: point),
                            Patch(rect: CGRect(x: 255, y: -23, width: 95, height: 119), color: point),
                            Patch(rect: CGRect(x: 106, y: 125, width: 210, height: 105), color: point),
                            Patch(rect: CGRect(x: 100, y: 329, width: 190, height: 65), color: point),
                            Patch(rect: CGRect(x: 318, y: 110, width: 95, height: 245), color: point)]
            }
            if coat.whiteLevel > 0 {
                let white = "#F4EFE5"
                patches += [Patch(rect: CGRect(x: 158, y: 211, width: 88, height: 125), color: white),
                            Patch(rect: CGRect(x: 112, y: 339, width: 80, height: 44), color: white),
                            Patch(rect: CGRect(x: 211, y: 339, width: 80, height: 44), color: white),
                            Patch(rect: CGRect(x: 170, y: 163, width: 67, height: 72), color: white)]
                if coat.whiteLevel == 2 {
                    patches += [Patch(rect: CGRect(x: 140, y: 17, width: 115, height: 220), color: white),
                                Patch(rect: CGRect(x: 105, y: 251, width: 205, height: 155), color: white),
                                Patch(rect: CGRect(x: 28, y: 172, width: 138, height: 85), color: white)]
                }
            }
        }
        self.patches = patches
    }

    func ink(at point: CGPoint) -> String {
        let underlying = patches.last(where: { $0.contains(point) })?.color ?? base
        return Self.isLight(underlying) ? "#51443A" : "#FFF8EC"
    }
    private var patterns: String {
        var result = ""
        if coat.hasTabby {
            result += "<g fill=\"none\" stroke=\"\(stripe)\" stroke-width=\"12\" stroke-linecap=\"round\">"
            for d in ["M166 57L177 99L198 79L218 101L233 56", "M49 125L83 133M45 152L78 159M320 121L352 111M325 148L358 140", "M89 254L124 265M78 289L118 300M285 264L319 251M294 300L328 287", "M331 243L344 260M351 287L369 293M320 315L327 335"] {
                result += "<path d=\"\(d)\"/>"
            }
            result += "</g>"
        }
        return result + patches.map(\.svg).joined()
    }

    /// Supplied only with the app's trusted bundled SVG sources; no user XML.
    func svg(_ original: String, asset: String) -> String {
        guard !coat.isOriginal else { return original }
        let regex = try! NSRegularExpression(pattern: "<path\\b[^>]*?/>")
        let matches = regex.matches(in: original, range: NSRange(original.startIndex..., in: original))
        var result = original
        var index = 0, faceIndex = 0
        // Separate body/tail exports use local bounds, while their pattern
        // coordinates stay attached to the same original 400pt anatomy.
        let origin: CGPoint = asset == "body" ? CGPoint(x: 74.52722, y: 203)
            : asset == "tail" ? CGPoint(x: 272, y: 231.8007) : .zero
        var replacements: [(NSRange, String)] = []
        for match in matches {
            let tag = (original as NSString).substring(with: match.range)
            var replacement = tag
            if tag.contains("fill=\"#101114\"") {
                let path = Self.attribute("d", in: tag)!
                let clip = "coat-\(index)"; index += 1
                replacement = tag.replacingOccurrences(of: "#101114", with: base)
                replacement += "<defs><clipPath id=\"\(clip)\"><path d=\"\(path)\"/></clipPath></defs>"
                let shiftX = (asset == "walk-front-face" || (asset == "walk" && tag.contains("id=\"Vector_4\""))) ? -20.0 : -origin.x
                replacement += "<g clip-path=\"url(#\(clip))\"><g transform=\"translate(\(shiftX) \(-origin.y))\">\(patterns)</g></g>"
            } else if tag.contains("stroke=\"white\"") {
                let samples = [CGPoint(x: 114, y: 161), CGPoint(x: 279, y: 162), CGPoint(x: 201, y: 191)]
                let sample = samples[min(faceIndex, 2)]; faceIndex += 1
                // Face strokes remain EXACTLY the original d/width/caps.
                replacement = tag.replacingOccurrences(of: "stroke=\"white\"", with: "stroke=\"\(ink(at: sample))\"")
            } else if tag.contains("#303034") {
                replacement = tag.replacingOccurrences(of: "#303034", with: line)
            }
            replacements.append((match.range, replacement))
        }
        for (range, replacement) in replacements.reversed() {
            result = (result as NSString).replacingCharacters(in: range, with: replacement)
        }
        return result
    }
    static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: "\\b" + name + "=\"([^\"]*)\"")
        guard let match = pattern.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        return (tag as NSString).substring(with: match.range(at: 1))
    }
    static func color(_ hex: String) -> NSColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    private static func isLight(_ hex: String) -> Bool {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return Double((value >> 16) & 255) * 0.299 + Double((value >> 8) & 255) * 0.587 + Double(value & 255) * 0.114 > 150
    }
}
