import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Offline tests: no microphone, network, keychain, application support writes,
/// clipboard, accessibility permission or UI interaction is needed.
@main
enum CatConfigurationTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }

    static func isDefault(_ config: CatConfiguration) -> Bool {
        config.version == 1 && config.image == nil && config.imageURL == nil && config.imageData == nil &&
        config.triggers == ["what's up", "whats up", "what is up"] && config.reply == "what's up!" &&
        config.fontFamily == "Comic Sans MS" && config.fontSize == 18 && config.bold &&
        config.bubblePosition == "upperRight" && config.tiltDegrees == -10 &&
        config.cooldownSeconds == 5 && config.displaySeconds == 3 && config.animateMouth
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CatConfigurationTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("cat.config.json")
        try testSchema(at: file)
        try testMatching(at: file)
        try testBoundsAndEncoding(at: file)
        try testImages(at: file)
        try testNonRegularFiles(at: file)
        try testCooldown(at: file)
        let sample = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("cat.config.json")
        let sampleConfig = CatConfiguration.load(from: sample)
        check(FileManager.default.fileExists(atPath: sample.path), "Portable sample is present")
        check(isDefault(sampleConfig) && sampleConfig.loadError == nil, "Portable sample matches version-one defaults")
        check(CatConfiguration.directoryURL.lastPathComponent == "tw.panh.FreeVoiceType", "Settings use the app-specific support folder")
        print("CatConfigurationTests passed (\(checks) checks)")
    }

    @discardableResult
    static func write(_ text: String, to file: URL) throws -> CatConfiguration {
        try Data(text.utf8).write(to: file)
        return CatConfiguration.load(from: file)
    }

    @discardableResult
    static func write(_ object: [String: Any], to file: URL) throws -> CatConfiguration {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: file)
        return CatConfiguration.load(from: file)
    }

    static func reject(_ text: String, at file: URL) throws {
        let config = try write(text, to: file)
        check(config.loadError != nil && isDefault(config), "Invalid config must fall back as a whole: \(text.prefix(120))")
        check(try! Data(contentsOf: file) == Data(text.utf8), "Invalid config must be preserved")
    }

    static func testSchema(at file: URL) throws {
        let missing = CatConfiguration.load(from: file)
        check(isDefault(missing) && missing.loadError == nil, "Missing file uses defaults without error")
        let missingDirectory = CatConfiguration.load(from: file.deletingLastPathComponent().appendingPathComponent("absent/cat.config.json"))
        check(isDefault(missingDirectory) && missingDirectory.loadError == nil, "Missing directory uses defaults")
        let empty = try write("{}", to: file)
        check(isDefault(empty) && empty.loadError == nil, "All fields may be omitted")

        let customJSON = #"{"version":1,"image":"my-cat.PNG","triggers":["Hello cat!","貓咪你好","what’s new"],"reply":"喵，今天也加油！","fontFamily":"Helvetica","fontSize":22.5,"bold":false,"bubblePosition":"upperLeft","tiltDegrees":7.5,"cooldownSeconds":8.5,"displaySeconds":4.5}"#
        try (Data([0xEF, 0xBB, 0xBF]) + Data(customJSON.utf8)).write(to: file)
        let custom = CatConfiguration.load(from: file)
        check(custom.loadError == nil && custom.version == 1 && custom.image == "my-cat.PNG" && custom.imageURL == nil, "BOM and missing same-directory PNG are allowed")
        check(custom.triggers.count == 3 && custom.reply == "喵，今天也加油！" && custom.fontFamily == "Helvetica" && custom.fontSize == 22.5 && !custom.bold, "Text and font values load")
        check(custom.bubblePosition == "upperLeft" && custom.tiltDegrees == 7.5 && custom.cooldownSeconds == 8.5 && custom.displaySeconds == 4.5, "Placement and duration values load")
        check(custom.animateMouth, "Old version-one files default animateMouth to true")
        check(isDefault(.defaults), "Custom loads cannot mutate shared defaults")
        var triggerCopy = custom.triggers
        triggerCopy[0] = "mutated"
        check(custom.matches("hello cat") && !custom.matches("mutated"), "Trigger snapshot is immutable")
        let disabled = try write(#"{"animateMouth":false}"#, to: file)
        check(!disabled.animateMouth && disabled.loadError == nil && disabled.reply == "what's up!", "Explicit mouth opt-out preserves greetings")
        let enabled = try write(#"{"animateMouth":true}"#, to: file)
        check(isDefault(enabled) && enabled.loadError == nil, "Explicit true uses defaults")
        for animate in [true, false] {
            let artwork = try write(["image": "missing-cat.png", "animateMouth": animate], to: file)
            check(artwork.loadError == nil && artwork.image == "missing-cat.png" && artwork.imageURL == nil && artwork.animateMouth == animate, "Missing custom art preserves explicit image selection to suppress mouth overlays")
        }

        let invalid = [
            "", "{broken", "null", "[]", "true", "42", #""text""#,
            #"{"version":2}"#, #"{"version":"1"}"#, #"{"version":null}"#, #"{"version":true}"#,
            #"{"version":1.5}"#, #"{"version":1.0}"#, #"{"version":1e0}"#, #"{"version":[]}"#,
            #"{"reply":"custom","fontSize":11}"#, #"{"fontSize":29}"#, #"{"fontSize":"18"}"#,
            #"{"fontSize":null}"#, #"{"fontSize":true}"#, #"{"fontSize":1e999}"#,
            #"{"bold":1}"#, #"{"bold":0}"#, #"{"bold":"true"}"#, #"{"bold":null}"#,
            #"{"bubblePosition":"center"}"#, #"{"bubblePosition":null}"#,
            #"{"animateMouth":1}"#, #"{"animateMouth":0}"#, #"{"animateMouth":"true"}"#,
            #"{"animateMouth":"false"}"#, #"{"animateMouth":null}"#, #"{"animateMouth":[]}"#,
            #"{"animateMouth":{}}"#, #"{"reply":"custom","animateMouth":"false"}"#,
            #"{"tiltDegrees":-15.1}"#, #"{"tiltDegrees":15.1}"#, #"{"cooldownSeconds":0}"#,
            #"{"cooldownSeconds":61}"#, #"{"displaySeconds":0}"#, #"{"displaySeconds":11}"#,
            #"{"reply":null}"#, #"{"reply":""}"#, #"{"reply":"   "}"#, #"{"reply":"two\nlines"}"#,
            #"{"reply":"two\u2028lines"}"#, #"{"reply":"two\u2029lines"}"#,
            #"{"reply":"nul\u0000"}"#, #"{"reply":"\ud800"}"#, #"{"reply":"\udc00"}"#,
            #"{"reply":["text"]}"#, #"{"fontFamily":false}"#, #"{"fontFamily":""}"#,
            #"{"triggers":null}"#, #"{"triggers":[]}"#, #"{"triggers":"hello"}"#,
            #"{"triggers":{"text":"hello"}}"#, #"{"triggers":[1]}"#, #"{"triggers":[null]}"#,
            #"{"triggers":[" "]}"#, #"{"triggers":["?!"]}"#, #"{"triggers":["two\nlines"]}"#,
            #"{"triggers":["HELLO!","hello"]}"#, #"{"triggers":["what’s up","what's up"]}"#,
            #"{"triggers":["hello  cat","hello cat!"]}"#,
            #"{"image":false}"#, #"{"image":""}"#, #"{"command":"run.exe"}"#,
            #"{"Reply":"wrong casing"}"#, #"{"reply":"custom","unknown":true}"#
        ]
        for json in invalid { try reject(json, at: file) }
        for key in ["fontSize", "tiltDegrees", "cooldownSeconds", "displaySeconds"] {
            for invalidValue in ["true", "false", "null", "\"18\"", "[]", "{}"] {
                try reject("{\"\(key)\":\(invalidValue)}", at: file)
            }
        }
    }

    static func testMatching(at file: URL) throws {
        for text in ["what's up", "whats up", "what is up", " WHAT’S UP?! ", "“What's up?”", "WHAT‘S UP", "whatʼs up", "what＇s up", "what\tis\nup", "what's up。", "\u{00A0}what   is up\u{00A0}"] {
            check(CatConfiguration.defaults.matches(text), "Approved whole greeting matches: \(text)")
        }
        for text in ["", "?!", "translate what's up", "what's up my neighbor", "say whats up", "what is up today", "whatsup", "what-s up", "w.h.a.t.s up", "what's up 2", "what's up🙂", "what's up what's up"] {
            check(!CatConfiguration.defaults.matches(text), "Ordinary dictation is not consumed: \(text)")
        }
        let custom = try write(["triggers": ["Hello cat!", "貓咪你好", "what’s new"]], to: file)
        for text in [" “HELLO\t CAT?” ", "貓咪你好。", "what's new", "WHAT＇S NEW?!"] {
            check(custom.matches(text), "Configured normalized trigger matches")
        }
        for text in ["please hello cat", "hello cat tomorrow", "hello-cat", "hello cat🙂", "what's up"] {
            check(!custom.matches(text), "Custom triggers replace defaults and require whole utterance")
        }
    }

    static func testBoundsAndEncoding(at file: URL) throws {
        let lower = try write([
            "triggers": (0..<32).map { "hello \($0)" }, "reply": String(repeating: "a", count: 80),
            "fontFamily": String(repeating: "a", count: 80), "fontSize": 12, "tiltDegrees": -15,
            "cooldownSeconds": 1, "displaySeconds": 1
        ], to: file)
        check(lower.loadError == nil && lower.triggers.count == 32 && lower.reply.count == 80 && lower.fontSize == 12 && lower.tiltDegrees == -15 && lower.cooldownSeconds == 1 && lower.displaySeconds == 1, "Inclusive lower bounds and largest lists/text are accepted")
        let upper = try write(#"{"fontSize":28,"tiltDegrees":15,"cooldownSeconds":60,"displaySeconds":10,"image":null}"#, to: file)
        check(upper.loadError == nil && upper.fontSize == 28 && upper.tiltDegrees == 15 && upper.cooldownSeconds == 60 && upper.displaySeconds == 10 && upper.imageURL == nil, "Inclusive upper bounds are accepted")
        for key in ["reply", "fontFamily", "image"] {
            let count = key == "image" ? 201 : 81
            let config = try write([key: String(repeating: "a", count: count)], to: file)
            check(config.loadError != nil && isDefault(config), "Overlong \(key) is rejected")
        }
        let oversizedObjects: [[String: Any]] = [
            ["triggers": [String(repeating: "a", count: 81)]],
            ["triggers": (0..<33).map { "hello \($0)" }],
            ["reply": String(repeating: "🐱", count: 81)],
            ["reply": String(repeating: "e\u{0301}", count: 41)]
        ]
        for object in oversizedObjects {
            let config = try write(object, to: file)
            check(config.loadError != nil && isDefault(config), "Unicode scalar and trigger count limits are enforced")
        }
        let emoji = String(repeating: "🐱", count: 80)
        let emojiConfig = try write(["reply": emoji], to: file)
        check(emojiConfig.loadError == nil && emojiConfig.reply == emoji, "Length counts Unicode scalars, not UTF-16 units")
        let combined = String(repeating: "e\u{0301}", count: 40)
        let combinedConfig = try write(["reply": combined], to: file)
        check(combinedConfig.loadError == nil, "Combining marks count as individual scalars")
        let trimmedConfig = try write(["reply": "  喵！  "], to: file)
        check(trimmedConfig.reply == "喵！", "Text is trimmed after length validation")
        let exact = try write("{}" + String(repeating: " ", count: CatConfiguration.maximumFileBytes - 2), to: file)
        check(exact.loadError == nil && isDefault(exact), "Exactly 16 KiB is accepted")
        try reject("{}" + String(repeating: " ", count: CatConfiguration.maximumFileBytes - 1), at: file)
        for invalidUTF8 in [Data([0xFF, 0xFE, 0x7B, 0, 0x7D, 0]), Data([0x7B, 0xFF, 0x7D]), Data([0xC0, 0xAF])] {
            try invalidUTF8.write(to: file)
            let config = CatConfiguration.load(from: file)
            check(config.loadError != nil && isDefault(config), "Only valid UTF-8 is accepted")
            check(try! Data(contentsOf: file) == invalidUTF8, "Invalid encoding is preserved")
        }
    }

    static func testImages(at file: URL) throws {
        for name in ["../cat.png", "..\\cat.png", "/cat.png", "\\cat.png", "C:\\cat.png", "C:cat.png", "\\\\server\\cat.png", "https://example.test/cat.png", "file:///cat.png", "folder/cat.png", "folder\\cat.png", "cat.jpg", "cat.jpeg", "cat.gif", "cat.svg", "cat.exe", "cat.png:payload", "cat?.png", "cat*.png", "CON.png", "NUL.png", "LPT1.png", "COM9.png", "com1 .png", "cat.png."] {
            let config = try write(["image": name, "reply": "custom"], to: file)
            check(config.loadError != nil && isDefault(config), "Unsafe portable image path rejects whole config: \(name)")
        }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let imageFile = file.deletingLastPathComponent().appendingPathComponent("safe.PNG")
        try png.write(to: imageFile)
        let valid = try write(["image": "safe.PNG", "reply": "custom"], to: file)
        check(valid.loadError == nil && valid.image == "safe.PNG", "A safe filename is accepted")
        #if canImport(ImageIO)
        check(valid.imageURL == imageFile && valid.imageData == png, "PNG must fully decode before exposing an immutable image snapshot")
        #else
        check(valid.imageURL == nil, "Portable builds fail closed when no image decoder exists")
        #endif
        let maxWidth = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAACAAAAAABCAYAAABKFE7yAAAAIUlEQVR4nO3DAQkAAAwEoetf+pdjoGCrqaqqqqqqqqq/Hwpa8OLNARupAAAAAElFTkSuQmCC")!
        try maxWidth.write(to: imageFile)
        #if canImport(ImageIO)
        check(valid.imageData == png, "Replacing artwork on disk cannot change the startup snapshot")
        check(CatConfiguration.load(from: file).imageURL == imageFile, "The 2048-pixel inclusive dimension limit is accepted")
        #endif
        let excessiveWidth = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAACAEAAAABCAYAAACl1iXMAAAAIUlEQVR4nO3DAQkAAAwEoetf+pdjoGCrqaqqqqqqqqr/H9MK8uApgcrIAAAAAElFTkSuQmCC")!
        var zeroDimension = png
        zeroDimension.replaceSubrange(16..<20, with: [0, 0, 0, 0])
        var excessiveHeight = png
        excessiveHeight.replaceSubrange(20..<24, with: [0, 0, 8, 1])
        var wrongSignature = png
        wrongSignature[0] = 0
        let invalidImages = [
            Data(), Data("not a png".utf8), Data(png.prefix(33)), excessiveWidth,
            excessiveHeight, zeroDimension, wrongSignature,
            png + Data(repeating: 0, count: CatConfiguration.maximumImageBytes)
        ]
        for bytes in invalidImages {
            try bytes.write(to: imageFile)
            let config = CatConfiguration.load(from: file)
            check(config.loadError == nil && config.image == "safe.PNG" && config.imageURL == nil && config.reply == "custom", "Invalid image content falls back only artwork, preserving explicit custom selection")
        }
        try FileManager.default.removeItem(at: imageFile)
        try FileManager.default.createSymbolicLink(at: imageFile, withDestinationURL: file)
        let symlink = CatConfiguration.load(from: file)
        check(symlink.loadError != nil && isDefault(symlink), "Image symlinks reject the whole config")
        try FileManager.default.removeItem(at: imageFile)
        try FileManager.default.createDirectory(at: imageFile, withIntermediateDirectories: true)
        let directoryImage = CatConfiguration.load(from: file)
        check(directoryImage.loadError == nil && directoryImage.imageURL == nil, "Directories are never decoded as artwork")
    }

    static func testNonRegularFiles(at file: URL) throws {
        let directory = file.deletingLastPathComponent()
        let invalidDirectory = CatConfiguration.load(from: directory)
        check(invalidDirectory.loadError != nil && isDefault(invalidDirectory), "Config directory is rejected")
        let fifo = directory.appendingPathComponent("pipe.json")
        check(mkfifo(fifo.path, mode_t(0o600)) == 0, "Test FIFO is created")
        let pipeConfig = CatConfiguration.load(from: fifo)
        check(pipeConfig.loadError != nil && isDefault(pipeConfig), "Config FIFOs fail without blocking")
        let imageFIFO = directory.appendingPathComponent("pipe.png")
        check(mkfifo(imageFIFO.path, mode_t(0o600)) == 0, "Image FIFO is created")
        let pipeImageConfig = try write(["image": "pipe.png"], to: file)
        check(pipeImageConfig.loadError == nil && pipeImageConfig.imageURL == nil, "Image FIFOs fail without blocking")
        let link = directory.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let linkedConfig = CatConfiguration.load(from: link)
        check(linkedConfig.loadError != nil && isDefault(linkedConfig), "Configuration symlink is rejected without following it")
        let nonFile = CatConfiguration.load(from: URL(string: "https://example.invalid/cat.config.json")!)
        check(nonFile.loadError != nil && isDefault(nonFile), "Remote config URLs are never fetched")
    }

    static func testCooldown(at file: URL) throws {
        let greeting = CatGreeting()
        check(greeting.consume("ordinary dictation", now: 0) == .notMatched, "Non-match is never consumed")
        check(greeting.consume("WHAT’S UP?!", now: 0) == .greet, "First match greets immediately, including at clock zero")
        check(greeting.consume("what is up", now: 0) == .cooldown, "Same-clock repeat is consumed in cooldown")
        check(greeting.consume("whats up", now: 4.999) == .cooldown, "Early repeats do not reach typing")
        check(greeting.consume("translate what's up", now: 4.999) == .notMatched, "Ordinary dictation remains ordinary during cooldown")
        check(greeting.consume("what's up", now: 5) == .greet, "Cooldown ends at exact boundary and repeats did not extend it")
        check(greeting.consume("what's up", now: 4) == .cooldown, "A backwards clock cannot bypass cooldown")
        check(greeting.consume("what's up", now: .infinity) == .cooldown, "Invalid clocks cannot poison cooldown state")
        check(greeting.consume("what's up", now: .nan) == .cooldown, "NaN clocks consume matches safely")
        check(greeting.consume("what's up", now: 10) == .greet, "Valid clock still works after invalid input")
        let config = try write(["triggers": ["hello cat"], "cooldownSeconds": 1.5], to: file)
        let custom = CatGreeting(configuration: config)
        check(custom.consume("what's up", now: 20) == .notMatched, "Cooldown policy uses configured trigger set")
        check(custom.consume("hello cat", now: 20) == .greet, "Custom greeting works")
        check(custom.consume("HELLO CAT!", now: 21.49) == .cooldown, "Custom fractional cooldown applies")
        check(custom.consume("hello cat", now: 21.5) == .greet, "Custom fractional cooldown ends at boundary")
    }
}
