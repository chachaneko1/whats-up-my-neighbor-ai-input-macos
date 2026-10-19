import Foundation
import CoreFoundation
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Version one remains portable; version two adds macOS anatomical appearance.
/// Invalid configuration
/// falls back as a whole; missing/undecodable artwork only falls back to the cat.
/// Values are immutable snapshots and are loaded once at app startup.
struct CatConfiguration {
    static let maximumFileBytes = 16 * 1024
    static let maximumImageBytes = 4 * 1024 * 1024
    static let maximumImageDimension = 2048
    static let defaults = CatConfiguration()
    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tw.panh.FreeVoiceType", isDirectory: true)
    }

    private(set) var version = 1
    private(set) var image: String?
    private(set) var imageURL: URL?
    private(set) var imageData: Data?
    private(set) var triggers = ["what's up", "whats up", "what is up"]
    private(set) var reply = "what's up!"
    private(set) var fontFamily = "Comic Sans MS"
    private(set) var fontSize = 18.0
    private(set) var bold = true
    private(set) var bubblePosition = "upperRight"
    private(set) var tiltDegrees = -10.0
    private(set) var cooldownSeconds = 5.0
    private(set) var displaySeconds = 3.0
    private(set) var animateMouth = true
    private(set) var appearance = CatAppearance.original
    private(set) var loadError: String?
    private var normalizedTriggers: Set<String> = ["what's up", "whats up", "what is up"]

    private static let knownFields: Set<String> = [
        "version", "image", "triggers", "reply", "fontFamily", "fontSize", "bold",
        "bubblePosition", "tiltDegrees", "cooldownSeconds", "displaySeconds", "animateMouth", "appearance"
    ]
    private enum Invalid: Error { case configuration, missingFile }

    static func load() -> CatConfiguration {
        load(from: directoryURL.appendingPathComponent("cat.config.json"))
    }

    /// Typed local preview/import adapter; never rewrites a user's file.
    func replacingAppearance(_ appearance: CatAppearance) -> CatConfiguration {
        var copy = self
        copy.version = 2
        copy.appearance = appearance
        return copy
    }

    /// Never modifies the supplied file, including on a decoding error.
    static func load(from url: URL) -> CatConfiguration {
        do {
            var data = try readBoundedFile(url, maximumBytes: maximumFileBytes)
            if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
            guard String(data: data, encoding: .utf8) != nil,
                  let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(document.keys).isSubset(of: knownFields) else { throw Invalid.configuration }
            var result = defaults
            if let value = document["version"] {
                guard let number = value as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      !["f", "d"].contains(String(cString: number.objCType)),
                      (1...2).contains(number.int64Value) else { throw Invalid.configuration }
                result.version = number.intValue
            }
            if let value = document["appearance"] {
                guard result.version == 2 else { throw Invalid.configuration }
                result.appearance = try CatAppearance.parse(value)
            }
            if let value = document["image"], !(value is NSNull) {
                result.image = try readText(value, maximum: 200)
                let candidate = try resolveImage(result.image!, relativeTo: url)
                result.imageData = validatedImageData(candidate)
                result.imageURL = result.imageData == nil ? nil : candidate
            }
            if let value = document["triggers"] {
                guard let values = value as? [Any], (1...32).contains(values.count) else {
                    throw Invalid.configuration
                }
                result.triggers = try values.map { try readText($0, maximum: 80) }
                var normalized = Set<String>()
                for trigger in result.triggers {
                    let phrase = normalizePhrase(trigger)
                    guard !phrase.isEmpty, normalized.insert(phrase).inserted else {
                        throw Invalid.configuration
                    }
                }
                result.normalizedTriggers = normalized
            }
            if let value = document["reply"] { result.reply = try readText(value, maximum: 80) }
            if let value = document["fontFamily"] { result.fontFamily = try readText(value, maximum: 80) }
            if let value = document["fontSize"] { result.fontSize = try readNumber(value, range: 12...28) }
            if let value = document["bold"] { result.bold = try readBool(value) }
            if let value = document["bubblePosition"] {
                guard let position = value as? String,
                      position == "upperRight" || position == "upperLeft" else { throw Invalid.configuration }
                result.bubblePosition = position
            }
            if let value = document["tiltDegrees"] { result.tiltDegrees = try readNumber(value, range: -15...15) }
            if let value = document["cooldownSeconds"] { result.cooldownSeconds = try readNumber(value, range: 1...60) }
            if let value = document["displaySeconds"] { result.displaySeconds = try readNumber(value, range: 1...10) }
            if let value = document["animateMouth"] { result.animateMouth = try readBool(value) }
            return result
        } catch Invalid.missingFile {
            return defaults
        } catch {
            var fallback = defaults
            fallback.loadError = "貓咪設定檔無法讀取或格式無效；已保留原檔，本次使用預設貓咪設定。"
            return fallback
        }
    }

    /// Matches a whole utterance, never a phrase embedded in ordinary dictation.
    func matches(_ text: String) -> Bool {
        normalizedTriggers.contains(Self.normalizePhrase(text))
    }

    private static func normalizePhrase(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var first = 0
        var end = scalars.count
        while first < end && isSurrounding(scalars[first]) { first += 1 }
        while end > first && isSurrounding(scalars[end - 1]) { end -= 1 }
        var normalized = String.UnicodeScalarView()
        var whitespace = false
        for scalar in scalars[first..<end] {
            if scalar.properties.isWhitespace { whitespace = true; continue }
            if whitespace && !normalized.isEmpty { normalized.append(" ") }
            whitespace = false
            switch scalar.value {
            case 0x2019, 0x2018, 0x02BC, 0xFF07: normalized.append("'")
            default: normalized.append(scalar)
            }
        }
        return String(normalized).lowercased()
    }

    private static func isSurrounding(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isWhitespace { return true }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: return true
        default: return false
        }
    }

    private static func readText(_ value: Any, maximum: Int) throws -> String {
        guard let text = value as? String,
              text.unicodeScalars.count <= maximum,
              !text.unicodeScalars.contains(where: {
                  $0.properties.generalCategory == .control || $0.value == 0x2028 || $0.value == 0x2029
              }) else { throw Invalid.configuration }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Invalid.configuration }
        return trimmed
    }

    private static func readNumber(_ value: Any, range: ClosedRange<Double>) throws -> Double {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, range.contains(number.doubleValue) else { throw Invalid.configuration }
        return number.doubleValue
    }

    private static func readBool(_ value: Any) throws -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { throw Invalid.configuration }
        return number.boolValue
    }

    private static func resolveImage(_ name: String, relativeTo configurationURL: URL) throws -> URL {
        // Enforce both platforms' filename rules, so the same file is portable.
        guard !name.contains(where: { "<>:\"/\\|?*".contains($0) }),
              name != ".", name != "..", !name.hasSuffix("."), !name.hasSuffix(" "),
              (name as NSString).pathExtension.lowercased() == "png" else { throw Invalid.configuration }
        let stem = name.split(separator: ".", omittingEmptySubsequences: false)[0]
            .trimmingCharacters(in: .whitespaces).uppercased()
        let reserved = ["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }
        guard !reserved.contains(stem) else { throw Invalid.configuration }
        let directory = configurationURL.deletingLastPathComponent().standardizedFileURL
        let resolved = directory.appendingPathComponent(name).standardizedFileURL
        guard resolved.deletingLastPathComponent() == directory else { throw Invalid.configuration }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
           attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw Invalid.configuration }
        return resolved
    }

    private static func validatedImageData(_ url: URL) -> Data? {
        guard let data = try? readBoundedFile(url, maximumBytes: maximumImageBytes),
              data.count >= 33,
              data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82]) else { return nil }
        func dimension(at offset: Int) -> UInt32 {
            data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        let width = dimension(at: 16)
        let height = dimension(at: 20)
        guard width > 0, height > 0,
              width <= UInt32(maximumImageDimension), height <= UInt32(maximumImageDimension) else { return nil }
        #if canImport(ImageIO)
        // Inspect and bound the header before asking ImageIO to allocate pixels.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              CGImageSourceGetCount(source) == 1,
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              decoded.width == Int(width), decoded.height == Int(height),
              CGImageSourceGetStatus(source) == .statusComplete else { return nil }
        return data
        #else
        // No image decoder exists in the portable policy-test binary. Production
        // is macOS; fail closed rather than call a header-only file validated.
        return nil
        #endif
    }

    /// Bounded, immutable read. O_NOFOLLOW rejects symlink swaps; O_NONBLOCK and
    /// fstat prevent FIFOs/devices from blocking startup or being read as files.
    private static func readBoundedFile(_ url: URL, maximumBytes: Int) throws -> Data {
        guard url.isFileURL else { throw Invalid.configuration }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw Invalid.missingFile }
            throw Invalid.configuration
        }
        defer { _ = close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              status.st_size >= 0, status.st_size <= Int64(maximumBytes) else { throw Invalid.configuration }
        var bytes = [UInt8](repeating: 0, count: maximumBytes + 1)
        var total = 0
        while total < bytes.count {
            let count = bytes.withUnsafeMutableBytes { buffer in
                read(descriptor, buffer.baseAddress!.advanced(by: total), buffer.count - total)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw Invalid.configuration
            }
            if count == 0 { break }
            total += count
        }
        guard total <= maximumBytes else { throw Invalid.configuration }
        return Data(bytes.prefix(total))
    }
}

/// A matched phrase is consumed even during cooldown. Only a visible greeting
/// starts cooldown; repeats never delay the next available greeting. Call on the
/// app's main queue. A monotonic clock avoids wall-clock/time-zone adjustments.
final class CatGreeting {
    enum Result: Equatable { case notMatched, cooldown, greet }
    let configuration: CatConfiguration
    private var lastGreetingTime: TimeInterval?

    init(configuration: CatConfiguration = .defaults) {
        self.configuration = configuration
    }

    func consume(_ transcript: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Result {
        guard configuration.matches(transcript) else { return .notMatched }
        guard now.isFinite else { return .cooldown }
        if let last = lastGreetingTime, now - last < configuration.cooldownSeconds { return .cooldown }
        lastGreetingTime = now
        return .greet
    }
}
