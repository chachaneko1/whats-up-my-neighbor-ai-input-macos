import Foundation

struct MacVocabularyPrompt: Equatable {
    let text: String
    let includedEntryIDs: [UUID]
}

enum MacVocabularyError: LocalizedError, Equatable {
    case emptyTerm
    case termTooLong
    case duplicateTerm
    case capacityReached
    case entryNotFound

    var errorDescription: String? {
        switch self {
        case .emptyTerm:
            return "常用詞不能是空白。"
        case .termTooLong:
            return "每個常用詞最多 40 個字。"
        case .duplicateTerm:
            return "詞典裡已經有相同的常用詞。"
        case .capacityReached:
            return "常用詞典最多可儲存 200 筆。"
        case .entryNotFound:
            return "找不到這筆常用詞，請重新開啟詞典。"
        }
    }
}

final class MacVocabularyStore {
    static let maximumEntryCount = 200
    static let maximumTermLength = 40
    static let maximumPromptUTF8ByteCount = 200
    static let baseInstruction = "請使用繁體中文、台灣常用字形與自然標點；保留中英混合、專有名詞、數字與法律用語。"

    private(set) var entries: [VocabularySyncEntry]
    var onEntriesChange: (() -> Void)?
    var onLocalChange: (() -> Void)?

    private let defaults: UserDefaults
    private let storageKey: String
    private let now: () -> Date
    private let deviceID: String
    private let counterKey: String
    private var revisionCounter: Int64
    private var tombstones: [VocabularySyncTombstone]

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "smartVocabulary.entries.v1",
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.now = now
        deviceID = Self.loadOrCreateDeviceID(
            defaults: defaults,
            key: "\(storageKey).syncDeviceID"
        )
        counterKey = "\(storageKey).syncRevisionCounter"

        let payload = Self.loadPayload(from: defaults, storageKey: storageKey)
        entries = payload.entries
        tombstones = payload.tombstones
        revisionCounter = max(
            Int64(defaults.integer(forKey: counterKey)),
            Self.maximumCounter(in: payload)
        )

        var migrated = false
        for index in entries.indices where entries[index].revision == .legacy {
            entries[index].revision = nextRevision()
            migrated = true
        }
        if migrated {
            persist()
        }
    }

    @discardableResult
    func add(
        term rawTerm: String,
        isEnabled: Bool = true,
        isPinned: Bool = false
    ) throws -> VocabularySyncEntry {
        let term = try validatedTerm(rawTerm)
        guard !entries.contains(where: { normalized($0.term) == normalized(term) }) else {
            throw MacVocabularyError.duplicateTerm
        }
        guard entries.count < Self.maximumEntryCount else {
            throw MacVocabularyError.capacityReached
        }

        let timestamp = now()
        let entry = VocabularySyncEntry(
            term: term,
            isEnabled: isEnabled,
            isPinned: isPinned,
            createdAt: timestamp,
            updatedAt: timestamp,
            revision: nextRevision()
        )
        entries.append(entry)
        completeLocalMutation()
        return entry
    }

    func update(
        id: UUID,
        term rawTerm: String,
        isEnabled: Bool,
        isPinned: Bool
    ) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            throw MacVocabularyError.entryNotFound
        }
        let term = try validatedTerm(rawTerm)
        guard !entries.contains(where: {
            $0.id != id && normalized($0.term) == normalized(term)
        }) else {
            throw MacVocabularyError.duplicateTerm
        }

        entries[index].term = term
        entries[index].isEnabled = isEnabled
        entries[index].isPinned = isPinned
        entries[index].updatedAt = now()
        entries[index].revision = nextRevision()
        completeLocalMutation()
    }

    func setEnabled(_ isEnabled: Bool, for id: UUID) {
        updateEntry(id: id) {
            $0.isEnabled = isEnabled
        }
    }

    func setPinned(_ isPinned: Bool, for id: UUID) {
        updateEntry(id: id) {
            $0.isPinned = isPinned
        }
    }

    func delete(id: UUID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        let revision = nextRevision()
        entries.removeAll { $0.id == id }
        storeTombstone(.init(id: id, revision: revision))
        completeLocalMutation()
    }

    func deleteAll() {
        guard !entries.isEmpty else { return }
        let revision = nextRevision()
        for entry in entries {
            storeTombstone(.init(id: entry.id, revision: revision))
        }
        entries = []
        completeLocalMutation()
    }

    func recordPromptUse(entryIDs: [UUID]) {
        let usedIDs = Set(entryIDs)
        guard !usedIDs.isEmpty,
              entries.contains(where: { usedIDs.contains($0.id) }) else { return }
        let revision = nextRevision()
        for index in entries.indices where usedIDs.contains(entries[index].id) {
            entries[index].useCount += 1
            entries[index].updatedAt = now()
            entries[index].revision = revision
        }
        completeLocalMutation()
    }

    func buildPrompt() -> MacVocabularyPrompt {
        let prioritized = entries
            .filter(\.isEnabled)
            .sorted(by: hasHigherPromptPriority)

        var included: [VocabularySyncEntry] = []
        for entry in prioritized {
            let proposed = included + [entry]
            guard promptText(for: proposed).utf8.count <= Self.maximumPromptUTF8ByteCount else {
                continue
            }
            included = proposed
        }
        return MacVocabularyPrompt(
            text: promptText(for: included),
            includedEntryIDs: included.map(\.id)
        )
    }

    func snapshot() -> VocabularySyncPayload {
        VocabularySyncPayload(entries: entries, tombstones: tombstones)
    }

    @discardableResult
    func merge(_ incoming: VocabularySyncPayload) -> Bool {
        let current = snapshot()
        let merged = VocabularySyncMerger.merge(
            local: current,
            incoming: incoming,
            maximumEntryCount: Self.maximumEntryCount
        )
        guard merged != current else { return false }

        revisionCounter = max(revisionCounter, Self.maximumCounter(in: merged))
        defaults.set(Int(revisionCounter), forKey: counterKey)
        entries = merged.entries
        tombstones = merged.tombstones
        persist()
        onEntriesChange?()
        return true
    }

    func filteredEntries(matching query: String) -> [VocabularySyncEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = entries.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.updatedAt > $1.updatedAt
        }
        guard !trimmedQuery.isEmpty else { return sorted }
        return sorted.filter {
            $0.term.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    func contains(term rawTerm: String) -> Bool {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return false }
        return entries.contains {
            normalized($0.term) == normalized(term)
        }
    }

    private func validatedTerm(_ rawTerm: String) throws -> String {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { throw MacVocabularyError.emptyTerm }
        guard term.count <= Self.maximumTermLength else {
            throw MacVocabularyError.termTooLong
        }
        return term
    }

    private func normalized(_ term: String) -> String {
        term.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "zh_Hant_TW")
        )
    }

    private func updateEntry(
        id: UUID,
        mutation: (inout VocabularySyncEntry) -> Void
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        mutation(&entries[index])
        entries[index].updatedAt = now()
        entries[index].revision = nextRevision()
        completeLocalMutation()
    }

    private func nextRevision() -> VocabularySyncRevision {
        revisionCounter += 1
        defaults.set(Int(revisionCounter), forKey: counterKey)
        return VocabularySyncRevision(counter: revisionCounter, deviceID: deviceID)
    }

    private func completeLocalMutation() {
        persist()
        onEntriesChange?()
        onLocalChange?()
    }

    private func storeTombstone(_ candidate: VocabularySyncTombstone) {
        if let index = tombstones.firstIndex(where: { $0.id == candidate.id }) {
            if candidate.revision.isNewer(than: tombstones[index].revision) {
                tombstones[index] = candidate
            }
        } else {
            tombstones.append(candidate)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot()) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func promptText(for entries: [VocabularySyncEntry]) -> String {
        guard !entries.isEmpty else { return Self.baseInstruction }
        return "\(Self.baseInstruction) 常用詞：\(entries.map(\.term).joined(separator: "、"))。"
    }

    private func hasHigherPromptPriority(
        _ lhs: VocabularySyncEntry,
        _ rhs: VocabularySyncEntry
    ) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.useCount != rhs.useCount {
            return lhs.useCount > rhs.useCount
        }
        return lhs.createdAt > rhs.createdAt
    }

    private static func loadPayload(
        from defaults: UserDefaults,
        storageKey: String
    ) -> VocabularySyncPayload {
        guard let data = defaults.data(forKey: storageKey) else { return .empty }
        if let payload = try? JSONDecoder().decode(VocabularySyncPayload.self, from: data) {
            return payload
        }
        if let legacyEntries = try? JSONDecoder().decode([VocabularySyncEntry].self, from: data) {
            return VocabularySyncPayload(entries: legacyEntries, tombstones: [])
        }
        return .empty
    }

    private static func loadOrCreateDeviceID(defaults: UserDefaults, key: String) -> String {
        if let value = defaults.string(forKey: key), !value.isEmpty {
            return value
        }
        let value = UUID().uuidString
        defaults.set(value, forKey: key)
        return value
    }

    private static func maximumCounter(in payload: VocabularySyncPayload) -> Int64 {
        let entryMaximum = payload.entries.map(\.revision.counter).max() ?? 0
        let tombstoneMaximum = payload.tombstones.map(\.revision.counter).max() ?? 0
        return max(entryMaximum, tombstoneMaximum)
    }
}
