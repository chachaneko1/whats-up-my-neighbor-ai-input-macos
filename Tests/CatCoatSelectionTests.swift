import Foundation

@main enum CatCoatSelectionTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CatCoatSelectionTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("cat.config.json")

        try CatCoatSelection.save("calico", to: file)
        precondition(CatConfiguration.load(from: file).appearance.preset == "calico")
        var saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition(saved["version"] as? Int == 2)

        let oldVersion = #"{"version":1,"reply":"保留舊問候","fontSize":22}"#
        try Data(oldVersion.utf8).write(to: file)
        try CatCoatSelection.save("calico", to: file)
        saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition(saved["version"] as? Int == 2)
        precondition(saved["reply"] as? String == "保留舊問候")
        precondition(saved["fontSize"] as? Int == 22)

        saved["reply"] = "我的問候"
        saved["triggers"] = ["你好貓咪"]
        saved["image"] = "my-cat.png"
        try JSONSerialization.data(withJSONObject: saved).write(to: file)
        try CatCoatSelection.save("tuxedo", to: file)
        saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition(saved["reply"] as? String == "我的問候")
        precondition(saved["triggers"] as? [String] == ["你好貓咪"])
        precondition(saved["image"] as? String == "my-cat.png")
        precondition(CatConfiguration.load(from: file).appearance.preset == "tuxedo")

        let custom = ##"{"version":2,"appearance":{"preset":"calico","parts":{"tail":{"color":"#ffffff"}}}}"##
        try Data(custom.utf8).write(to: file)
        do { try CatCoatSelection.save("blue", to: file); preconditionFailure("Custom parts must be preserved") }
        catch CatCoatSelection.Error.customAppearance { }
        let preservedCustom = try Data(contentsOf: file)
        precondition(preservedCustom == Data(custom.utf8))

        let invalid = #"{"reply":"kept","unknown":true}"#
        try Data(invalid.utf8).write(to: file)
        do { try CatCoatSelection.save("white", to: file); preconditionFailure("Invalid config must be preserved") }
        catch CatCoatSelection.Error.invalidConfiguration { }
        let preservedInvalid = try Data(contentsOf: file)
        precondition(preservedInvalid == Data(invalid.utf8))

        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: directory.appendingPathComponent("missing"))
        do { try CatCoatSelection.save("black", to: file); preconditionFailure("Symbolic link must be rejected") }
        catch CatCoatSelection.Error.unsafeFile { }

        print("CatCoatSelectionTests passed")
    }
}
