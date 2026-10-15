import Foundation

@main enum VocabularyLearningTests {
    static func main() throws {
        let suite = "VocabularyTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vocabulary = MacVocabularyStore(defaults: defaults)
        let learning = VocabularyLearningStore(vocabulary: vocabulary, defaults: defaults)
        learning.capture(.init(originalSegment: "NekoEye", suggestedTerm: "NekoAI"))
        precondition(learning.candidates.count == 1 && vocabulary.entries.isEmpty)
        let id = learning.candidates[0].id
        learning.capture(.init(originalSegment: "NekoEye", suggestedTerm: "nekoai"))
        precondition(learning.candidates.count == 1)
        try learning.update(id: id, term: "YUI Neko")
        let reloaded = VocabularyLearningStore(vocabulary: vocabulary, defaults: defaults)
        precondition(reloaded.candidates[0].term == "YUI Neko")
        try learning.confirm(id: id)
        try learning.confirm(id: id)
        precondition(vocabulary.entries.count == 1 && learning.candidates[0].state == "added")
        let entry = vocabulary.entries[0]
        precondition(entry.id == learning.candidates[0].entryID)
        let prompt = learning.prompt(base: "保留原文。")
        precondition(prompt.contains("YUI Neko") && learning.includedIDs == [entry.id])
        vocabulary.setEnabled(false, for: entry.id)
        precondition(!learning.prompt(base: "保留原文。").contains("YUI Neko"))
        vocabulary.setEnabled(true, for: entry.id)
        precondition(vocabulary.buildPrompt(baseInstruction: String(repeating: "字", count: 66)).includedEntryIDs.isEmpty)
        learning.capture(.init(originalSegment: "foo", suggestedTerm: "bar"))
        let rejectedID = learning.candidates[0].id
        learning.reject(id: rejectedID)
        learning.capture(.init(originalSegment: "foo", suggestedTerm: "bar"))
        precondition(learning.candidates.count == 2 && learning.candidates[0].state == "rejected")
        learning.deleteRecord(id: rejectedID)
        precondition(learning.candidates.count == 1)
        learning.capture(.init(originalSegment: "", suggestedTerm: "隨便打字"))
        learning.capture(.init(originalSegment: "舊句子", suggestedTerm: "全新句子。"))
        precondition(learning.candidates.count == 1)
        vocabulary.delete(id: entry.id)
        precondition(vocabulary.entries.isEmpty && vocabulary.snapshot().tombstones.contains { $0.id == entry.id })
        let reopened = MacVocabularyStore(defaults: defaults)
        precondition(reopened.entries.isEmpty && reopened.snapshot().tombstones.count == 1)
        // Legacy array and sync payload remain readable, with stable IDs.
        defaults.set(try JSONEncoder().encode([entry]), forKey: "legacy")
        let legacy = MacVocabularyStore(defaults: defaults, storageKey: "legacy")
        precondition(legacy.entries[0].id == entry.id)
        defaults.set(try JSONEncoder().encode(legacy.snapshot()), forKey: "payload")
        precondition(MacVocabularyStore(defaults: defaults, storageKey: "payload").entries[0].id == entry.id)
        let full = MacVocabularyStore(defaults: defaults, storageKey: "full")
        for i in 0..<200 { try full.add(term: "term-\(i)") }
        let fullLearning = VocabularyLearningStore(vocabulary: full, defaults: defaults)
        fullLearning.capture(.init(originalSegment: "old", suggestedTerm: "new-term"))
        let pending = fullLearning.candidates.first { $0.term == "new-term" }!
        do { try fullLearning.confirm(id: pending.id); preconditionFailure() }
        catch MacVocabularyError.capacityReached {}
        precondition(fullLearning.candidates.first { $0.id == pending.id }?.state == "candidate")
        precondition(full.entries.count == 200)
        // Prompt budget selects pinned terms first, without including candidates.
        try full.update(id: full.entries[199].id, term: "pinned", isEnabled: true, isPinned: true)
        let bounded = full.buildPrompt(baseInstruction: "原文")
        precondition(bounded.text.utf8.count <= 200 && bounded.includedEntryIDs.first == full.entries[199].id)
        let broken = Data("broken".utf8)
        defaults.set(broken, forKey: "broken")
        let corrupt = MacVocabularyStore(defaults: defaults, storageKey: "broken")
        do { try corrupt.add(term: "不可覆蓋"); preconditionFailure() } catch {}
        precondition(defaults.data(forKey: "broken") == broken)
        defaults.set(broken, forKey: "smartVocabulary.learning.v1")
        let corruptLearning = VocabularyLearningStore(vocabulary: vocabulary, defaults: defaults)
        corruptLearning.capture(.init(originalSegment: "a", suggestedTerm: "b"))
        precondition(corruptLearning.storageError != nil && defaults.data(forKey: "smartVocabulary.learning.v1") == broken)
        let correction = MacVocabularyCorrectionExtractor.candidate(original: "我在用 NekoEye 開發", edited: "我在用 NekoAI 開發")!
        precondition(correction.suggestedTerm == "NekoAI")
        precondition(MacVocabularyCorrectionExtractor.candidate(original: "好", edited: "好") == nil)
        precondition(MacVocabularyCorrectionExtractor.candidate(original: "好", edited: "好。") == nil)
        try automaticLearningTests()
        print("Vocabulary learning tests passed: candidates, approval, persistence, prompt inclusion, rejection, compatibility and corrupt-data protection")
    }

    private static func automaticLearningTests() throws {
        let suite = "AutomaticVocabularyTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vocabulary = MacVocabularyStore(defaults: defaults)
        let store = VocabularyLearningStore(vocabulary: vocabulary, defaults: defaults)
        let automatic = VocabularyAutomaticLearning(store: store)
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool) { precondition(condition()); checks += 1 }

        let first = automatic.propose(.init(originalSegment: "NekoEye", suggestedTerm: "NekoAI"))!
        check(vocabulary.entries.isEmpty && first.state == "candidate")
        check(!store.prompt(base: "保留原文").contains("NekoAI"))
        check(automatic.complete(isContextValid: true))
        check(vocabulary.contains(term: "NekoAI") && store.candidates.first?.state == "added")
        check(store.prompt(base: "保留原文").contains("NekoAI"))
        check(!automatic.complete(isContextValid: true)) // Expiration cannot commit twice.
        check(automatic.propose(.init(originalSegment: "NekoEye", suggestedTerm: "nekoai")) == nil)
        check(MacVocabularyStore(defaults: defaults).contains(term: "NekoAI"))

        let declined = automatic.propose(.init(originalSegment: "foo", suggestedTerm: "bar"))!
        automatic.reject()
        check(!vocabulary.contains(term: "bar") && store.candidates.first { $0.id == declined.id }?.state == "rejected")
        check(automatic.propose(.init(originalSegment: "foo", suggestedTerm: "BAR")) == nil)

        // More typing during the notice discards only the uncommitted fragment.
        let unfinished = automatic.propose(.init(originalSegment: "Neighbour", suggestedTerm: "Neighbo"))!
        automatic.cancel()
        check(!store.candidates.contains { $0.id == unfinished.id } && !vocabulary.contains(term: "Neighbo"))
        let finished = automatic.propose(.init(originalSegment: "Neighbour", suggestedTerm: "Neighbor"))!
        check(automatic.complete(isContextValid: true))
        check(store.candidates.first { $0.id == finished.id }?.state == "added" && vocabulary.contains(term: "Neighbor"))

        let stale = automatic.propose(.init(originalSegment: "old", suggestedTerm: "stale"))!
        check(!automatic.complete(isContextValid: false))
        check(!store.candidates.contains { $0.id == stale.id } && !vocabulary.contains(term: "stale"))

        // A candidate from an older app version can be auto-approved when the
        // correction is observed again; cancelling must preserve that old record.
        let legacy = store.capture(.init(originalSegment: "old", suggestedTerm: "LegacyTerm"))!
        check(automatic.propose(.init(originalSegment: "old", suggestedTerm: "legacyterm"))?.id == legacy.id)
        automatic.cancel()
        check(store.candidates.contains { $0.id == legacy.id && $0.state == "candidate" })
        check(automatic.propose(.init(originalSegment: "old", suggestedTerm: "LegacyTerm"))?.id == legacy.id)
        check(automatic.complete(isContextValid: true) && vocabulary.contains(term: "LegacyTerm"))

        let manuallyApproved = automatic.propose(.init(originalSegment: "old", suggestedTerm: "ManualTerm"))!
        try store.confirm(id: manuallyApproved.id)
        automatic.cancel()
        check(vocabulary.contains(term: "ManualTerm") && store.candidates.contains { $0.id == manuallyApproved.id })

        let manuallyEdited = automatic.propose(.init(originalSegment: "old", suggestedTerm: "BeforeManualEdit"))!
        try store.update(id: manuallyEdited.id, term: "AfterManualEdit")
        check(!automatic.complete(isContextValid: true))
        check(!vocabulary.contains(term: "AfterManualEdit") && store.candidates.contains { $0.term == "AfterManualEdit" })

        let full = MacVocabularyStore(defaults: defaults, storageKey: "full.auto")
        for i in 0..<200 { try full.add(term: "term-\(i)") }
        let fullStore = VocabularyLearningStore(vocabulary: full, defaults: defaults)
        let fullAutomatic = VocabularyAutomaticLearning(store: fullStore)
        let blocked = fullAutomatic.propose(.init(originalSegment: "old", suggestedTerm: "overflow"))!
        check(!fullAutomatic.complete(isContextValid: true))
        check(full.entries.count == 200 && fullStore.candidates.contains { $0.id == blocked.id && $0.state == "candidate" })

        let range = TrackedPasteRange(location: 6, length: 5)
        check(TrackedPasteEditPolicy.selectionCrossesBoundary(location: 4, length: 5, range: range))
        check(TrackedPasteEditPolicy.selectionCrossesBoundary(location: 9, length: 5, range: range))
        check(!TrackedPasteEditPolicy.selectionCrossesBoundary(location: 6, length: 5, range: range))
        check(!TrackedPasteEditPolicy.selectionCrossesBoundary(location: 0, length: 5, range: range))
        // Poll missed the selection: "o app" -> "XYZ" crosses the left boundary,
        // leaving a plausible-looking "Zle" fragment. Context guards reject it.
        let crossed = "hellXYZle world" as NSString
        check(!TrackedPasteEditPolicy.boundariesMatch(expectedLeading: "hello ", expectedTrailing: " world",
                                                     currentLeading: crossed.substring(with: NSRange(location: 0, length: 6)),
                                                     currentTrailing: crossed.substring(from: 9)))
        check(TrackedPasteEditPolicy.boundariesMatch(expectedLeading: "hello ", expectedTrailing: " world",
                                                    currentLeading: "hello ", currentTrailing: " world"))
        // The same-length final-character replacement still works when an editor
        // exposes bounded reads but sends no AX selection notification.
        let shortRange = TrackedPasteRange(location: 0, length: 6)
        check(TrackedPasteEditPolicy.evaluate(range: shortRange, previousCharacterCount: 6, currentCharacterCount: 6,
                                             caretLocation: 6, selectedCorrectionIntersectsRange: false, isEditingBurst: false,
                                             existingRangeTextChanged: true) == .observe(newLength: 6))
        check(TrackedPasteEditPolicy.evaluate(range: shortRange, previousCharacterCount: 6, currentCharacterCount: 8,
                                             caretLocation: 8, selectedCorrectionIntersectsRange: false, isEditingBurst: false,
                                             existingRangeTextChanged: true) == .observe(newLength: 8))
        check(TrackedPasteEditPolicy.evaluate(range: shortRange, previousCharacterCount: 6, currentCharacterCount: 8,
                                             caretLocation: 8, selectedCorrectionIntersectsRange: false, isEditingBurst: false,
                                             existingRangeTextChanged: false) == .ignore)
        print("Automatic vocabulary regression checks passed: \(checks)")
    }
}
