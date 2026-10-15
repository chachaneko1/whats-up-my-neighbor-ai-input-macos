import Foundation

struct TemporaryRecordingStore: RecordingStorage {
    private let directory: URL
    init(directory: URL = FileManager.default.temporaryDirectory) { self.directory = directory }

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
