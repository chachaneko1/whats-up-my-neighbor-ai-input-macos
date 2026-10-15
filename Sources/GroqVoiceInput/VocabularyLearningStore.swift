import Foundation

struct VocabularyLearningCandidate: Codable, Identifiable, Equatable {
    let id: UUID
    let original: String
    var term: String
    let createdAt: Date
    var updatedAt: Date
    var state: String // candidate, added, rejected
    var entryID: UUID?
}

/// Main-thread model. Persist only bounded correction fragments, never full transcripts.
final class VocabularyLearningStore {
    let vocabulary: MacVocabularyStore
    private let defaults: UserDefaults
    private let key = "smartVocabulary.learning.v1"
    private(set) var candidates: [VocabularyLearningCandidate] = []
    private(set) var status = "等待下一次本機語音輸入；貼上後觀察修正最多兩分鐘。"
    private(set) var promptStatus = "尚未送出詞典提示。候選不會用於辨識。"
    private(set) var includedIDs: [UUID] = []
    private(set) var storageError: String?
    var onChange: (() -> Void)?

    init(vocabulary: MacVocabularyStore, defaults: UserDefaults = .standard) {
        self.vocabulary = vocabulary
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do { candidates = try JSONDecoder().decode([VocabularyLearningCandidate].self, from: data) }
            catch { storageError = "候選資料無法讀取，暫停寫入以保留原資料。" }
        }
    }

    func report(_ value: String) { status = value; onChange?() }

    @discardableResult
    func capture(_ candidate: MacVocabularyCandidate) -> VocabularyLearningCandidate? {
        guard storageError == nil else { report(storageError!); return nil }
        let term = candidate.suggestedTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.originalSegment.isEmpty, candidate.originalSegment.count <= 40,
              !term.isEmpty, term.count <= 40,
              !term.contains(where: { "。！？；\n\r".contains($0) }) else {
            report("這次變更不像單一詞彙修正，未建立候選；可手動新增。")
            return nil
        }
        guard !vocabulary.contains(term: term) else { report("修正詞已在詞典，不重複建立候選。"); return nil }
        let matching = candidates.filter { $0.term.compare(term, options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive]) == .orderedSame }
        guard !matching.contains(where: { $0.state == "rejected" }) else {
            report("此修正已拒絕，不重複加入。")
            return nil
        }
        if let existing = matching.first(where: { $0.state == "candidate" }) {
            report("已找到既有候選「\(existing.term)」。")
            return existing
        }
        guard candidates.count < 500 else { report("學習紀錄已達 500 筆，請先刪除不需要的紀錄。"); return nil }
        let now = Date()
        let record = VocabularyLearningCandidate(id: UUID(), original: candidate.originalSegment, term: term,
                                                createdAt: now, updatedAt: now, state: "candidate", entryID: nil)
        candidates.insert(record, at: 0)
        persist()
        report("已自動建立候選「\(term)」，請在詞典確認加入。")
        return storageError == nil ? record : nil
    }

    func update(id: UUID, term: String) throws {
        guard storageError == nil else { throw VoiceTypeError.message(storageError!) }
        let value = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw MacVocabularyError.emptyTerm }
        guard value.count <= 40 else { throw MacVocabularyError.termTooLong }
        guard let i = candidates.firstIndex(where: { $0.id == id && $0.state == "candidate" }) else { return }
        candidates[i].term = value
        candidates[i].updatedAt = Date()
        persist()
    }

    func confirm(id: UUID) throws {
        guard storageError == nil else { throw VoiceTypeError.message(storageError!) }
        guard let i = candidates.firstIndex(where: { $0.id == id && $0.state == "candidate" }) else { return }
        let term = candidates[i].term
        let entry = vocabulary.entries.first { $0.term.compare(term, options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive]) == .orderedSame }
        let saved = try entry ?? vocabulary.add(term: term)
        candidates[i].state = "added"
        candidates[i].entryID = saved.id
        candidates[i].updatedAt = Date()
        persist()
        report("已加入「\(term)」，下次辨識依提示額度納入。")
    }

    func reject(id: UUID) {
        guard storageError == nil, let i = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[i].state = "rejected"
        candidates[i].updatedAt = Date()
        persist()
    }

    func deleteRecord(id: UUID) {
        guard storageError == nil else { return }
        candidates.removeAll { $0.id == id }
        persist()
    }

    func prompt(base: String) -> String {
        let built = vocabulary.buildPrompt(baseInstruction: base)
        includedIDs = built.includedEntryIDs
        let used = Set(includedIDs)
        let included = vocabulary.entries.filter { used.contains($0.id) }.map(\.term)
        let omitted = vocabulary.entries.filter { $0.isEnabled && !used.contains($0.id) }.map(\.term)
        let disabled = vocabulary.entries.filter { !$0.isEnabled }.count
        promptStatus = "最近請求納入：\(included.isEmpty ? "無" : included.joined(separator: "、"))。\n因提示額度未納入：\(omitted.isEmpty ? "無" : omitted.joined(separator: "、"))；停用 \(disabled) 詞。提供提示不保證辨識命中。"
        vocabulary.recordPromptUse(entryIDs: includedIDs)
        onChange?()
        return built.text
    }

    private func persist() {
        guard storageError == nil else { return }
        do { defaults.set(try JSONEncoder().encode(candidates), forKey: key) }
        catch { storageError = "候選儲存失敗：\(error.localizedDescription)" }
        onChange?()
    }
}

/// A short opt-out period keeps unfinished typing out of the dictionary. This
/// model owns only its own candidate; existing or manually approved entries are
/// never removed when a pending observation is cancelled.
final class VocabularyAutomaticLearning {
    static let optOutDuration: TimeInterval = 6

    private let store: VocabularyLearningStore
    private(set) var pending: VocabularyLearningCandidate?
    private var ownsPendingRecord = false

    init(store: VocabularyLearningStore) { self.store = store }

    @discardableResult
    func propose(_ candidate: MacVocabularyCandidate) -> VocabularyLearningCandidate? {
        cancel()
        let existingIDs = Set(store.candidates.map(\.id))
        pending = store.capture(candidate)
        ownsPendingRecord = pending.map { !existingIDs.contains($0.id) } ?? false
        if let pending {
            store.report("將自動加入字典「\(pending.term)」；提示期間可按「不加入」。")
        }
        return pending
    }

    /// The caller revalidates the exact focused paste range at the deadline.
    @discardableResult
    func complete(isContextValid: Bool) -> Bool {
        guard let pending else { return false }
        guard isContextValid else { cancel(); return false }
        self.pending = nil
        ownsPendingRecord = false
        guard store.candidates.contains(where: { $0.id == pending.id && $0.state == "candidate" && $0.term == pending.term }) else { return false }
        do {
            try store.confirm(id: pending.id)
            return true
        } catch {
            store.report("未自動加入「\(pending.term)」：\(error.localizedDescription)；候選仍保留，可在字典處理。")
            return false
        }
    }

    func reject() {
        guard let pending else { return }
        self.pending = nil
        ownsPendingRecord = false
        store.reject(id: pending.id)
        store.report("未加入「\(pending.term)」，不會再次自動建議此詞。")
    }

    func cancel() {
        guard let pending else { return }
        let ownsRecord = ownsPendingRecord
        self.pending = nil
        ownsPendingRecord = false
        if ownsRecord, store.candidates.contains(where: { $0.id == pending.id && $0.state == "candidate" && $0.term == pending.term }) {
            store.deleteRecord(id: pending.id)
        }
    }
}
