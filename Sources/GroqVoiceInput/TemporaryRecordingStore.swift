import Foundation

struct TemporaryRecordingStore: RecordingStorage {
    private let directory: URL
    init(directory: URL = FileManager.default.temporaryDirectory) { self.directory = directory }

    // 暫存命名與孤兒檔案清理：
    // 每個暫存檔以 "FreeVoiceType-" 為固定前綴與隨機 UUID 組合。
    // 在應用程式啟動時呼叫 cleanupStaleRecordings()，安全遍歷並刪除前次異常終止遺留的暫存音訊，
    // 杜絕使用者磁碟空間被錄音殘留無謂消耗。
    func makeURL() -> URL {
        directory.appendingPathComponent("FreeVoiceType-\(UUID().uuidString).m4a")
    }

    func isNonempty(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return false }
        return size.int64Value > 0
    }

    func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    func cleanupStaleRecordings() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("FreeVoiceType-") && file.pathExtension == "m4a" {
            remove(file)
        }
    }
}
