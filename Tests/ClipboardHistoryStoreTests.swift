import Foundation
import CryptoKit

@main
enum ClipboardHistoryStoreTests {
    private static var checks = 0

    static func main() throws {
        testMemoryAndDuplicates()
        testLimitsAndValidation()
        try testPersistenceAndPermissions()
        try testLegacyImageMigration()
        try testPersistentEviction()
        try testQueuedClearAndRemoval()
        try testReentrantChanges()
        try testCorruptManifestPreservedUntilClear()
        try testMissingManifestPreservesOrphans()
        try testCorruptPayloads()
        try testManifestBoundsAndPaths()
        try testSymlinkPayloadIsNotRead()
        try testWriteFailureKeepsMemory()
        print("ClipboardHistoryStoreTests passed: \(checks) isolated checks; no system clipboard or real history access")
    }

    private static func check(_ condition: Bool, _ message: String = "") {
        checks += 1
        precondition(condition, message)
    }

    private static func testMemoryAndDuplicates() {
        var time = Date(timeIntervalSince1970: 1234)
        let store = ClipboardHistoryStore(directoryURL: nil, now: { time })
        var changes = 0
        store.onChange = { changes += 1 }
        let original = "  第一行\n第二行\t "
        check(store.add(kind: .text, data: Data(original.utf8)))
        let first = store.items[0]
        check(first.text == original, "Keep original whitespace and line breaks")
        check(first.createdAt == time)
        check(store.item(id: first.id) == first)
        time.addTimeInterval(10)
        check(store.add(kind: .text, data: Data("second".utf8)))
        check(store.add(kind: .text, data: first.data))
        check(store.items.count == 2 && store.items.first == first, "Duplicate promotion keeps identity/date")
        check(changes == 3)
        check(store.add(kind: .text, data: first.data))
        check(changes == 3, "Already first is a no-op")
        check(!store.add(kind: .png, data: first.data))
        check(!store.add(kind: .tiff, data: first.data))
        check(store.items.count == 2 && store.items.first == first, "Images cannot add, replace or reorder text history")
        store.remove(id: UUID())
        check(changes == 3)
        store.flush()
        check(store.lastError == nil)
    }

    private static func testLimitsAndValidation() {
        let store = ClipboardHistoryStore(directoryURL: nil)
        for index in 0..<12 { check(store.add(kind: .text, data: Data("item \(index)".utf8))) }
        check(store.items.count == 10)
        check(store.items.first?.text == "item 11" && store.items.last?.text == "item 2")
        let limited = ClipboardHistoryStore(directoryURL: nil, limit: 1)
        let capped = ClipboardHistoryStore(directoryURL: nil, limit: 100)
        for index in 0..<12 {
            _ = limited.add(kind: .text, data: Data("\(index)".utf8))
            _ = capped.add(kind: .text, data: Data("\(index)".utf8))
        }
        check(limited.items.count == 5 && capped.items.count == 10)
        let before = store.items
        check(!store.add(kind: .text, data: Data()))
        check(!store.add(kind: .png, data: Data()))
        check(!store.add(kind: .text, data: Data(" \n\r\t　".utf8)))
        check(!store.add(kind: .text, data: Data([0xff, 0xfe])))
        let oversized = Data(repeating: 0x61, count: 8 * 1024 * 1024 + 1)
        for kind in [ClipboardHistoryKind.text, .png, .tiff] {
            check(!store.add(kind: kind, data: oversized))
        }
        check(store.items == before, "Rejected content cannot evict existing history")
        check(store.add(kind: .text, data: Data(oversized.dropLast())))
        check(store.items[0].data.count == 8 * 1024 * 1024)
    }

    private static func testPersistenceAndPermissions() throws {
        try withDirectory { directory in
            let date = Date(timeIntervalSince1970: 2500)
            let store = ClipboardHistoryStore(directoryURL: directory, now: { date })
            check(store.items.isEmpty && store.lastError == nil)
            check(!FileManager.default.fileExists(atPath: directory.path), "Read-only empty init creates no history")
            let second = Data("第二次複製\n".utf8)
            let third = Data("  語音結果  ".utf8)
            check(store.add(kind: .text, data: Data("  保留\n換行 ".utf8)))
            check(store.add(kind: .text, data: second))
            check(store.add(kind: .text, data: third))
            let expected = store.items
            store.flush()
            check(store.lastError == nil)
            let reloaded = ClipboardHistoryStore(directoryURL: directory)
            check(reloaded.items == expected)
            check(reloaded.lastError == nil)
            check(reloaded.items[0].data == third && reloaded.items[1].data == second)
            check(try permissions(directory) == 0o700)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            check(files.count == 4)
            for file in files { check(try permissions(file) == 0o600) }
            let manifest = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
            let object = try JSONSerialization.jsonObject(with: manifest) as! [String: Any]
            let records = object["items"] as! [[String: Any]]
            check(records.count == 3)
            check(records.allSatisfy { $0["data"] == nil && $0["text"] == nil })
            check(manifest.count < 2048, "Index has metadata/checksums, no encoded payloads")
            check(store.add(kind: .text, data: second))
            store.flush()
            check(ClipboardHistoryStore(directoryURL: directory).items.first?.id == expected[1].id)
        }
    }

    private static func testLegacyImageMigration() throws {
        for imagesOnly in [false, true] {
            try withDirectory { directory in
                let date = Date(timeIntervalSince1970: 3000)
                let png = ClipboardHistoryItem(id: UUID(), kind: .png,
                    data: Data([0x89, 0x50, 0x4e, 0x47, 0, 1, 0xff, 0xfe]), createdAt: date)
                let tiff = ClipboardHistoryItem(id: UUID(), kind: .tiff,
                    data: Data([0x49, 0x49, 0x2a, 0, 10, 11, 0xfd, 0xfc]), createdAt: date)
                let newer = ClipboardHistoryItem(id: UUID(), kind: .text,
                    data: Data("  原有語音結果\n".utf8), createdAt: date.addingTimeInterval(-10))
                let older = ClipboardHistoryItem(id: UUID(), kind: .text,
                    data: Data("原有手動複製".utf8), createdAt: date.addingTimeInterval(-20))
                let legacy = imagesOnly ? [png, tiff] : [png, newer, tiff, older]
                try writeLegacyHistory(legacy, to: directory)
                let store = ClipboardHistoryStore(directoryURL: directory)
                let expected = imagesOnly ? [] : [newer, older]
                check(store.lastError == nil, "Valid older images must not mark the history corrupt")
                check(store.items == expected, "Migration preserves exact text, identity, timestamp and order")
                check(store.item(id: png.id) == nil && store.item(id: tiff.id) == nil)
                store.flush()
                check(store.lastError == nil)
                check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(png.id.uuidString + ".data").path))
                check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(tiff.id.uuidString + ".data").path))
                check(ClipboardHistoryStore(directoryURL: directory).items == expected)
                check(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == expected.count + 1)
                let object = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))) as! [String: Any]
                let records = object["items"] as! [[String: Any]]
                check(records.allSatisfy { $0["kind"] as? String == "text" })
                check(store.add(kind: .text, data: Data("升級後的新文字".utf8)))
                store.flush()
                check(ClipboardHistoryStore(directoryURL: directory).items == store.items)
            }
        }
    }

    /// Build the previous on-disk schema directly; never enable new image capture.
    private static func writeLegacyHistory(_ items: [ClipboardHistoryItem], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        for item in items {
            try item.data.write(to: directory.appendingPathComponent(item.id.uuidString + ".data"))
            let checksum = SHA256.hash(data: item.data).map { String(format: "%02x", $0) }.joined()
            records.append(["id": item.id.uuidString, "kind": item.kind.rawValue,
                            "createdAt": item.createdAt.timeIntervalSinceReferenceDate,
                            "byteCount": item.data.count, "sha256": checksum])
        }
        let manifest = try JSONSerialization.data(withJSONObject: ["version": 1, "items": records])
        try manifest.write(to: directory.appendingPathComponent("manifest.json"))
    }

    private static func testQueuedClearAndRemoval() throws {
        try withDirectory { directory in
            let store = ClipboardHistoryStore(directoryURL: directory)
            for index in 0..<25 { _ = store.add(kind: .text, data: Data("pending \(index)".utf8)) }
            store.clear()
            check(store.items.isEmpty)
            _ = store.add(kind: .text, data: Data("only after clear".utf8))
            store.flush()
            check(store.lastError == nil)
            let after = ClipboardHistoryStore(directoryURL: directory)
            check(after.items == store.items && after.items.count == 1, "Old queued writes cannot revive cleared entries")
            check(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
            store.remove(id: store.items[0].id)
            store.flush()
            check(ClipboardHistoryStore(directoryURL: directory).items.isEmpty)
            check(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["manifest.json"])
            store.clear()
            store.flush()
            check(ClipboardHistoryStore(directoryURL: directory).lastError == nil)
        }
    }

    private static func testPersistentEviction() throws {
        try withDirectory { directory in
            let store = ClipboardHistoryStore(directoryURL: directory)
            _ = store.add(kind: .text, data: Data("oldest".utf8))
            let oldestID = store.items[0].id
            for index in 0..<10 { _ = store.add(kind: .text, data: Data("newer \(index)".utf8)) }
            store.flush()
            check(store.lastError == nil)
            check(store.items.count == 10 && store.item(id: oldestID) == nil)
            check(ClipboardHistoryStore(directoryURL: directory).items == store.items)
            check(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 11)
            check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(oldestID.uuidString + ".data").path))
        }
    }

    private static func testReentrantChanges() throws {
        try withDirectory { directory in
            let store = ClipboardHistoryStore(directoryURL: directory)
            var resetOnce = false
            store.onChange = {
                guard !resetOnce else { return }
                resetOnce = true
                store.clear()
                _ = store.add(kind: .text, data: Data("replacement".utf8))
            }
            _ = store.add(kind: .text, data: Data("must disappear".utf8))
            store.flush()
            check(store.items.map(\.text) == ["replacement"])
            check(ClipboardHistoryStore(directoryURL: directory).items == store.items,
                  "A callback's clear/add must be persisted after the original mutation")
        }
    }

    private static func testCorruptManifestPreservedUntilClear() throws {
        try withDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let corrupt = Data("not valid JSON".utf8)
            let manifest = directory.appendingPathComponent("manifest.json")
            let originalFile = directory.appendingPathComponent(UUID().uuidString + ".data")
            try corrupt.write(to: manifest)
            try Data([1, 2, 3]).write(to: originalFile)
            let store = ClipboardHistoryStore(directoryURL: directory)
            check(store.items.isEmpty && store.lastError != nil)
            let fixedMessage = store.lastError
            check(!(fixedMessage ?? "").contains(directory.path))
            check(store.add(kind: .text, data: Data("still retained this session".utf8)))
            store.flush()
            check(store.items.count == 1 && store.lastError == fixedMessage)
            check(try Data(contentsOf: manifest) == corrupt)
            check(try Data(contentsOf: originalFile) == Data([1, 2, 3]))
            store.clear()
            _ = store.add(kind: .text, data: Data("fresh history".utf8))
            store.flush()
            check(store.lastError == nil)
            check(!FileManager.default.fileExists(atPath: originalFile.path))
            check(ClipboardHistoryStore(directoryURL: directory).items == store.items)
        }
    }

    private static func testCorruptPayloads() throws {
        for mutation in 0..<3 {
            try withDirectory { directory in
                let source = ClipboardHistoryStore(directoryURL: directory)
                _ = source.add(kind: .text, data: Data("original".utf8))
                source.flush()
                let file = directory.appendingPathComponent(source.items[0].id.uuidString + ".data")
                if mutation == 0 { try Data("modified".utf8).write(to: file) }
                if mutation == 1 { try FileManager.default.removeItem(at: file) }
                if mutation == 2 { try Data(repeating: 1, count: 8 * 1024 * 1024 + 1).write(to: file) }
                let manifest = directory.appendingPathComponent("manifest.json")
                let before = try Data(contentsOf: manifest)
                let loaded = ClipboardHistoryStore(directoryURL: directory)
                check(loaded.items.isEmpty && loaded.lastError != nil)
                _ = loaded.add(kind: .text, data: Data("do not replace damaged files".utf8))
                loaded.flush()
                check(try Data(contentsOf: manifest) == before)
            }
        }
    }

    private static func testMissingManifestPreservesOrphans() throws {
        try withDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let orphan = directory.appendingPathComponent(UUID().uuidString + ".data")
            let original = Data([4, 3, 2, 1])
            try original.write(to: orphan)
            let store = ClipboardHistoryStore(directoryURL: directory)
            check(store.items.isEmpty && store.lastError != nil)
            _ = store.add(kind: .text, data: Data("retain memory only".utf8))
            store.flush()
            check(try Data(contentsOf: orphan) == original)
            check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path))
        }
    }

    private static func testManifestBoundsAndPaths() throws {
        for mutation in 0..<6 {
            try withDirectory { directory in
                let source = ClipboardHistoryStore(directoryURL: directory)
                _ = source.add(kind: .text, data: Data("bounded".utf8))
                source.flush()
                let manifest = directory.appendingPathComponent("manifest.json")
                var object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [String: Any]
                let records = object["items"] as! [[String: Any]]
                switch mutation {
                case 0: object["version"] = 99
                case 1: object["items"] = Array(repeating: records[0], count: 11)
                case 2: object["items"] = [records[0], records[0]]
                case 3:
                    var record = records[0]
                    record["id"] = "../../outside"
                    object["items"] = [record]
                case 4:
                    var record = records[0]
                    record["byteCount"] = 8 * 1024 * 1024 + 1
                    object["items"] = [record]
                default: break
                }
                let damaged = mutation == 5 ? Data(repeating: 0x20, count: 32 * 1024 + 1)
                    : try JSONSerialization.data(withJSONObject: object)
                try damaged.write(to: manifest)
                let loaded = ClipboardHistoryStore(directoryURL: directory)
                check(loaded.items.isEmpty && loaded.lastError != nil)
                _ = loaded.add(kind: .text, data: Data("memory only".utf8))
                loaded.flush()
                check(try Data(contentsOf: manifest) == damaged)
            }
        }
    }

    private static func testSymlinkPayloadIsNotRead() throws {
        try withDirectory { directory in
            let source = ClipboardHistoryStore(directoryURL: directory)
            _ = source.add(kind: .text, data: Data("same bytes".utf8))
            source.flush()
            let file = directory.appendingPathComponent(source.items[0].id.uuidString + ".data")
            let outside = directory.deletingLastPathComponent().appendingPathComponent("outside.txt")
            try Data("same bytes".utf8).write(to: outside)
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
            let loaded = ClipboardHistoryStore(directoryURL: directory)
            check(loaded.items.isEmpty && loaded.lastError != nil, "Reject symlinks even if target would match")
            loaded.clear()
            loaded.flush()
            check(try Data(contentsOf: outside) == Data("same bytes".utf8))
            check(loaded.lastError == nil)
        }
    }

    private static func testWriteFailureKeepsMemory() throws {
        try withDirectory { directory in
            let store = ClipboardHistoryStore(directoryURL: directory)
            try Data("path is occupied".utf8).write(to: directory)
            check(store.add(kind: .text, data: Data("retain despite disk failure".utf8)))
            store.flush()
            check(store.items.count == 1 && store.lastError != nil)
            check(try Data(contentsOf: directory) == Data("path is occupied".utf8))
            store.clear()
            _ = store.add(kind: .text, data: Data("after explicit reset".utf8))
            store.flush()
            check(store.lastError == nil)
            check(ClipboardHistoryStore(directoryURL: directory).items == store.items)
        }
    }

    private static func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as! NSNumber).intValue & 0o777
    }

    private static func withDirectory(_ body: (URL) throws -> Void) throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardHistoryStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try body(parent.appendingPathComponent("History", isDirectory: true))
    }
}
