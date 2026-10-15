import Foundation
import CryptoKit
import Darwin

enum ClipboardHistoryKind: String, Codable {
    // Image cases are retained only to migrate histories written by build 21.
    case text, png, tiff
}

struct ClipboardHistoryItem: Equatable {
    let id: UUID
    let kind: ClipboardHistoryKind
    let data: Data
    let createdAt: Date

    var text: String? {
        kind == .text ? String(data: data, encoding: .utf8) : nil
    }
}

/// Call mutations on the UI thread. Only immutable snapshots cross onto the I/O queue.
/// This store never reads the system clipboard or sends its contents anywhere.
final class ClipboardHistoryStore {
    static let maximumItemByteCount = 8 * 1024 * 1024
    static let maximumItemCount = 10
    static let defaultDirectoryURL: URL = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appendingPathComponent("AI語音輸入", isDirectory: true)
        .appendingPathComponent("ClipboardHistory", isDirectory: true)

    private(set) var items: [ClipboardHistoryItem] = []
    var onChange: (() -> Void)?
    var lastError: String? { errorState.message }

    private let directoryURL: URL?
    private let limit: Int
    private let now: () -> Date
    private let queue = DispatchQueue(label: "tw.panh.clipboard-history.persistence")
    private let errorState = ErrorState()
    private var persistenceBlocked = false

    private static let manifestName = "manifest.json"
    private static let maximumManifestByteCount = 32 * 1024
    private static let unreadableMessage = "剪貼簿歷史無法讀取，已保留原檔；清除歷史後可重新儲存。"
    private static let writeFailureMessage = "剪貼簿歷史暫時無法儲存，目前內容仍保留在這次執行中。"

    init(
        directoryURL: URL? = ClipboardHistoryStore.defaultDirectoryURL,
        limit: Int = 10,
        now: @escaping () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL
        self.limit = min(Self.maximumItemCount, max(5, limit))
        self.now = now
        guard let directoryURL else { return }
        do {
            let loaded = try Self.load(from: directoryURL)
            items = Array(loaded.filter { $0.kind == .text }.prefix(self.limit))
            if loaded.contains(where: { $0.kind != .text }) {
                // Keep valid legacy text identities/order and remove image files
                // only after the text-only index has been committed in the background.
                enqueuePersistence()
            }
        } catch {
            // Do not replace an unreadable history with an empty/new snapshot.
            // New captures can still be kept in memory until an explicit clear.
            persistenceBlocked = true
            errorState.set(Self.unreadableMessage, generation: errorState.generation)
        }
    }

    @discardableResult
    func add(kind: ClipboardHistoryKind, data: Data) -> Bool {
        guard kind == .text, Self.isValidStoredPayload(kind: kind, data: data) else { return false }
        if let index = items.firstIndex(where: { $0.kind == kind && $0.data == data }) {
            guard index != 0 else { return true }
            let existing = items.remove(at: index)
            items.insert(existing, at: 0)
        } else {
            let timestamp = now()
            guard timestamp.timeIntervalSinceReferenceDate.isFinite else { return false }
            items.insert(.init(id: UUID(), kind: kind, data: data, createdAt: timestamp), at: 0)
            if items.count > limit { items.removeLast(items.count - limit) }
        }
        // Enqueue before notifying: a reentrant clear/add must remain the later write.
        enqueuePersistence()
        onChange?()
        return true
    }

    func item(id: UUID) -> ClipboardHistoryItem? {
        items.first { $0.id == id }
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        enqueuePersistence()
        onChange?()
    }

    func clear() {
        items.removeAll()
        persistenceBlocked = false
        // Ignore errors from snapshots queued before this explicit reset.
        errorState.reset()
        enqueuePersistence(reset: true)
        onChange?()
    }

    /// Wait for writes already queued by this store, for termination and isolated tests.
    func flush() {
        queue.sync {}
    }

    private func enqueuePersistence(reset: Bool = false) {
        guard let directoryURL, !persistenceBlocked else { return }
        let snapshot = items
        let state = errorState
        let generation = state.generation
        queue.async {
            guard state.generation == generation else { return }
            do {
                if reset { try Self.resetDirectory(directoryURL) }
                try Self.persist(snapshot, to: directoryURL)
                state.set(nil, generation: generation)
            } catch {
                state.set(Self.writeFailureMessage, generation: generation)
            }
        }
    }

    /// Legacy images remain readable for migration; new additions accept text only.
    private static func isValidStoredPayload(kind: ClipboardHistoryKind, data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maximumItemByteCount else { return false }
        if kind == .text {
            guard let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        }
        return true
    }

    private struct Manifest: Codable {
        let version: Int
        let items: [Record]
    }

    private struct Record: Codable {
        let id: UUID
        let kind: ClipboardHistoryKind
        let createdAt: Date
        let byteCount: Int
        let sha256: String
    }

    private enum StorageError: Error { case invalid }

    private static func dataURL(for id: UUID, in directory: URL) -> URL {
        // Paths are always derived from a decoded UUID, never a manifest filename.
        directory.appendingPathComponent(id.uuidString + ".data", isDirectory: false)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func load(from directory: URL) throws -> [ClipboardHistoryItem] {
        let manager = FileManager.default
        guard let attributes = try? manager.attributesOfItem(atPath: directory.path) else {
            // Distinguish an absent directory from an inaccessible existing path.
            if !manager.fileExists(atPath: directory.path) { return [] }
            throw StorageError.invalid
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw StorageError.invalid }
        let manifestURL = directory.appendingPathComponent(manifestName)
        if !manager.fileExists(atPath: manifestURL.path) {
            guard try manager.contentsOfDirectory(atPath: directory.path).isEmpty else { throw StorageError.invalid }
            return []
        }
        let data = try boundedRead(manifestURL, maximum: maximumManifestByteCount)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.version == 1, manifest.items.count <= maximumItemCount,
              Set(manifest.items.map(\.id)).count == manifest.items.count else { throw StorageError.invalid }
        var result: [ClipboardHistoryItem] = []
        for record in manifest.items {
            guard record.byteCount > 0, record.byteCount <= maximumItemByteCount,
                  record.createdAt.timeIntervalSinceReferenceDate.isFinite else { throw StorageError.invalid }
            let bytes = try boundedRead(dataURL(for: record.id, in: directory), maximum: maximumItemByteCount)
            guard bytes.count == record.byteCount, digest(bytes) == record.sha256,
                  isValidStoredPayload(kind: record.kind, data: bytes) else { throw StorageError.invalid }
            result.append(.init(id: record.id, kind: record.kind, data: bytes, createdAt: record.createdAt))
        }
        // Tighten permissions only after validating the whole history.
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        for url in [manifestURL] + result.map({ dataURL(for: $0.id, in: directory) }) {
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return result
    }

    private static func boundedRead(_ url: URL, maximum: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw StorageError.invalid }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= maximum else { throw StorageError.invalid }
        var result = Data()
        while let chunk = try handle.read(upToCount: min(64 * 1024, maximum + 1 - result.count)), !chunk.isEmpty {
            result.append(chunk)
            guard result.count <= maximum else { throw StorageError.invalid }
        }
        return result
    }

    private static func prepareDirectory(_ directory: URL) throws {
        let manager = FileManager.default
        if let attributes = try? manager.attributesOfItem(atPath: directory.path) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw StorageError.invalid }
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private static func persist(_ snapshot: [ClipboardHistoryItem], to directory: URL) throws {
        try prepareDirectory(directory)
        var records: [Record] = []
        for item in snapshot {
            let url = dataURL(for: item.id, in: directory)
            let checksum = digest(item.data)
            // Immutable UUID files need writing only once. Validate before reusing
            // one so a damaged file is never silently committed into a new index.
            if FileManager.default.fileExists(atPath: url.path) {
                let existing = try boundedRead(url, maximum: maximumItemByteCount)
                guard existing == item.data else { throw StorageError.invalid }
            } else {
                try writePrivate(item.data, to: url)
            }
            records.append(.init(id: item.id, kind: item.kind, createdAt: item.createdAt,
                                 byteCount: item.data.count, sha256: checksum))
        }
        let encoded = try JSONEncoder().encode(Manifest(version: 1, items: records))
        guard encoded.count <= maximumManifestByteCount else { throw StorageError.invalid }
        try writePrivate(encoded, to: directory.appendingPathComponent(manifestName))
        // Delete evicted data only after the new index has been committed.
        let retainedNames = Set(snapshot.map { $0.id.uuidString + ".data" })
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            guard name.hasSuffix(".data"), let id = UUID(uuidString: String(name.dropLast(5))),
                  name == id.uuidString + ".data", !retainedNames.contains(name) else { continue }
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static func writePrivate(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw StorageError.invalid }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
        }
        try handle.write(contentsOf: data)
        try handle.close()
        guard rename(temporary.path, destination.path) == 0 else { throw StorageError.invalid }
    }

    private static func resetDirectory(_ directory: URL) throws {
        let manager = FileManager.default
        // Removing a symlink removes the link itself, never its destination.
        if (try? manager.attributesOfItem(atPath: directory.path)) != nil {
            try manager.removeItem(at: directory)
        }
    }

    /// Background errors are observable without dispatching back into a blocked main thread.
    private final class ErrorState {
        private let lock = NSLock()
        private var storedMessage: String?
        private var storedGeneration = 0

        var message: String? {
            lock.lock(); defer { lock.unlock() }
            return storedMessage
        }

        var generation: Int {
            lock.lock(); defer { lock.unlock() }
            return storedGeneration
        }

        func set(_ message: String?, generation: Int) {
            lock.lock(); defer { lock.unlock() }
            guard generation == storedGeneration else { return }
            storedMessage = message
        }

        func reset() {
            lock.lock(); defer { lock.unlock() }
            storedGeneration += 1
            storedMessage = nil
        }
    }
}
