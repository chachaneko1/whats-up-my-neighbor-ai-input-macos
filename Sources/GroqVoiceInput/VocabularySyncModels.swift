import Foundation

struct VocabularySyncRevision: Codable, Equatable, Sendable {
    static let legacy = VocabularySyncRevision(counter: 0, deviceID: "")

    let counter: Int64
    let deviceID: String

    func isNewer(than other: VocabularySyncRevision) -> Bool {
        if counter != other.counter {
            return counter > other.counter
        }
        return deviceID > other.deviceID
    }
}

struct VocabularySyncEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var term: String
    var isEnabled: Bool
    var isPinned: Bool
    let createdAt: Date
    var updatedAt: Date
    var useCount: Int
    var revision: VocabularySyncRevision

    init(
        id: UUID = UUID(),
        term: String,
        isEnabled: Bool = true,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        useCount: Int = 0,
        revision: VocabularySyncRevision = .legacy
    ) {
        self.id = id
        self.term = term
        self.isEnabled = isEnabled
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.useCount = useCount
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case term
        case isEnabled
        case isPinned
        case createdAt
        case updatedAt
        case useCount
        case revision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        term = try container.decode(String.self, forKey: .term)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        useCount = try container.decode(Int.self, forKey: .useCount)
        revision = try container.decodeIfPresent(
            VocabularySyncRevision.self,
            forKey: .revision
        ) ?? .legacy
    }
}

struct VocabularySyncTombstone: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let revision: VocabularySyncRevision
}

struct VocabularySyncPayload: Codable, Equatable, Sendable {
    var entries: [VocabularySyncEntry]
    var tombstones: [VocabularySyncTombstone]

    static let empty = VocabularySyncPayload(entries: [], tombstones: [])
}

enum VocabularySyncMerger {
    static func merge(
        local: VocabularySyncPayload,
        incoming: VocabularySyncPayload,
        maximumEntryCount: Int = 200
    ) -> VocabularySyncPayload {
        var records: [UUID: Record] = [:]
        ingest(local, into: &records)
        ingest(incoming, into: &records)

        var activeEntries = records.values.compactMap(\.entry)
        var tombstones = Dictionary(
            uniqueKeysWithValues: records.values.compactMap { record in
                record.tombstone.map { ($0.id, $0) }
            }
        )

        activeEntries = removeDuplicateTerms(
            from: activeEntries,
            tombstones: &tombstones
        )

        if activeEntries.count > maximumEntryCount {
            activeEntries.sort(by: isPreferred)
            let removed = activeEntries.dropFirst(maximumEntryCount)
            let winningRevision = activeEntries.first?.revision ?? .legacy
            for entry in removed {
                storeTombstone(
                    VocabularySyncTombstone(id: entry.id, revision: winningRevision),
                    in: &tombstones
                )
            }
            activeEntries = Array(activeEntries.prefix(maximumEntryCount))
        }

        activeEntries.removeAll { tombstone in
            guard let deleted = tombstones[tombstone.id] else { return false }
            return deleted.revision == tombstone.revision
                || deleted.revision.isNewer(than: tombstone.revision)
        }

        return VocabularySyncPayload(
            entries: activeEntries.sorted { $0.id.uuidString < $1.id.uuidString },
            tombstones: tombstones.values.sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    private enum Record {
        case entry(VocabularySyncEntry)
        case tombstone(VocabularySyncTombstone)

        var id: UUID {
            switch self {
            case .entry(let value): value.id
            case .tombstone(let value): value.id
            }
        }

        var revision: VocabularySyncRevision {
            switch self {
            case .entry(let value): value.revision
            case .tombstone(let value): value.revision
            }
        }

        var entry: VocabularySyncEntry? {
            guard case .entry(let value) = self else { return nil }
            return value
        }

        var tombstone: VocabularySyncTombstone? {
            guard case .tombstone(let value) = self else { return nil }
            return value
        }
    }

    private static func ingest(
        _ payload: VocabularySyncPayload,
        into records: inout [UUID: Record]
    ) {
        for entry in payload.entries {
            store(.entry(entry), in: &records)
        }
        for tombstone in payload.tombstones {
            store(.tombstone(tombstone), in: &records)
        }
    }

    private static func store(_ candidate: Record, in records: inout [UUID: Record]) {
        guard let existing = records[candidate.id] else {
            records[candidate.id] = candidate
            return
        }
        records[candidate.id] = preferred(existing, candidate)
    }

    private static func preferred(_ lhs: Record, _ rhs: Record) -> Record {
        if lhs.revision != rhs.revision {
            return lhs.revision.isNewer(than: rhs.revision) ? lhs : rhs
        }
        switch (lhs, rhs) {
        case (.tombstone, .entry):
            return lhs
        case (.entry, .tombstone):
            return rhs
        case (.tombstone, .tombstone):
            return lhs
        case (.entry(let left), .entry(let right)):
            return stableKey(left) >= stableKey(right) ? lhs : rhs
        }
    }

    private static func removeDuplicateTerms(
        from entries: [VocabularySyncEntry],
        tombstones: inout [UUID: VocabularySyncTombstone]
    ) -> [VocabularySyncEntry] {
        var winners: [String: VocabularySyncEntry] = [:]
        for entry in entries {
            let key = normalized(entry.term)
            guard let existing = winners[key] else {
                winners[key] = entry
                continue
            }
            let winner = isPreferred(entry, existing) ? entry : existing
            let loser = winner.id == entry.id ? existing : entry
            winners[key] = winner
            storeTombstone(
                VocabularySyncTombstone(id: loser.id, revision: winner.revision),
                in: &tombstones
            )
        }
        return Array(winners.values)
    }

    private static func storeTombstone(
        _ candidate: VocabularySyncTombstone,
        in tombstones: inout [UUID: VocabularySyncTombstone]
    ) {
        guard let existing = tombstones[candidate.id] else {
            tombstones[candidate.id] = candidate
            return
        }
        if candidate.revision.isNewer(than: existing.revision) {
            tombstones[candidate.id] = candidate
        }
    }

    private static func isPreferred(
        _ lhs: VocabularySyncEntry,
        _ rhs: VocabularySyncEntry
    ) -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision.isNewer(than: rhs.revision)
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private static func normalized(_ term: String) -> String {
        term.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "zh_Hant_TW")
        )
    }

    private static func stableKey(_ entry: VocabularySyncEntry) -> String {
        [
            entry.term,
            entry.isEnabled ? "1" : "0",
            entry.isPinned ? "1" : "0",
            String(entry.useCount),
            entry.id.uuidString
        ].joined(separator: "\u{1F}")
    }
}
