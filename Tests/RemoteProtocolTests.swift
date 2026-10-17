import Foundation

@main
enum RemoteProtocolTests {
    static func main() throws {
        let target = RemoteTargetDescriptor(
            sessionID: "session-test",
            macName: "Test Mac",
            appName: "Google Chrome",
            windowTitle: "ChatGPT",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let original = RemoteMessage(
            id: "request-test",
            kind: .targetResponse,
            replyTo: "target-request",
            target: target,
            targetSessionID: target.sessionID
        )
        let decoded = try RemoteMessageCodec.decode(
            RemoteMessage.self,
            from: RemoteMessageCodec.encode(original)
        )
        precondition(decoded == original, "Remote message JSON round-trip failed")

        precondition(RemoteAction.pasteAndSubmit.submits, "pasteAndSubmit must be the only submit action")
        precondition(!RemoteAction.paste.submits, "paste must never submit")
        precondition(!RemoteAction.cancel.submits, "cancel must never submit")
        precondition(RemoteProtocolPolicy.supports(2), "Current protocol version must be supported")
        precondition(!RemoteProtocolPolicy.supports(99), "Unknown protocol versions must be rejected")
        precondition(RemoteActionPolicy.canExecute(hasText: true, hasTarget: true, isConnected: true, isWaiting: false))
        precondition(!RemoteActionPolicy.canExecute(hasText: false, hasTarget: true, isConnected: true, isWaiting: false))
        precondition(!RemoteActionPolicy.canExecute(hasText: true, hasTarget: false, isConnected: true, isWaiting: false))
        precondition(!RemoteActionPolicy.canExecute(hasText: true, hasTarget: true, isConnected: false, isWaiting: false))
        precondition(!RemoteActionPolicy.canExecute(hasText: true, hasTarget: true, isConnected: true, isWaiting: true))

        let englishCorrection = MacVocabularyCorrectionExtractor.candidate(
            original: "我使用 groq 做語音辨識",
            edited: "我使用 Groq 做語音辨識"
        )
        precondition(
            englishCorrection?.suggestedTerm == "Groq",
            "A case correction must expand to the complete English word"
        )
        precondition(
            englishCorrection?.originalSegment == "groq",
            "The explanation must show the complete original English word"
        )
        let cjkCorrection = MacVocabularyCorrectionExtractor.candidate(
            original: "更新UE Strategy的內容",
            edited: "更新YUI Strategy的內容"
        )
        precondition(
            cjkCorrection?.suggestedTerm == "YUI",
            "A corrected product name must be suggested"
        )
        precondition(
            MacVocabularyCorrectionExtractor.candidate(
                original: "這是測試。",
                edited: "這是測試！"
            ) == nil,
            "Punctuation-only edits must not produce vocabulary suggestions"
        )
        precondition(
            MacVocabularyCorrectionExtractor.candidate(
                original: "重複重複",
                edited: "重複"
            ) == nil,
            "Deletion-only edits must not produce vocabulary suggestions"
        )

        let trackedRange = TrackedPasteRange(location: 10, length: 8)
        precondition(
            TrackedPasteEditPolicy.evaluate(
                range: trackedRange,
                previousCharacterCount: 18,
                currentCharacterCount: 19,
                caretLocation: 19,
                selectedCorrectionIntersectsRange: false,
                isEditingBurst: false
            ) == .ignore,
            "Typing after the pasted range must not be treated as a correction"
        )
        precondition(
            TrackedPasteEditPolicy.evaluate(
                range: trackedRange,
                previousCharacterCount: 18,
                currentCharacterCount: 16,
                caretLocation: 14,
                selectedCorrectionIntersectsRange: true,
                isEditingBurst: false
            ) == .observe(newLength: 6),
            "Replacing a selection inside the pasted range must be observed"
        )
        precondition(
            TrackedPasteEditPolicy.evaluate(
                range: trackedRange,
                previousCharacterCount: 18,
                currentCharacterCount: 20,
                caretLocation: 7,
                selectedCorrectionIntersectsRange: false,
                isEditingBurst: false
            ) == .shift(newLocation: 12),
            "Edits before the pasted range must only shift its location"
        )

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let valid = RemoteTargetValidationPolicy.evaluate(
            expectedPID: 42,
            currentPID: 42,
            expectedBundleIdentifier: "test.app",
            currentBundleIdentifier: "test.app",
            expectedWindowTitle: "Chat",
            currentWindowTitle: "Chat",
            elementMatches: true,
            isEditable: true,
            expiresAt: now.addingTimeInterval(60),
            now: now
        )
        precondition(valid == nil)
        precondition(RemoteTargetValidationPolicy.evaluate(
            expectedPID: 42,
            currentPID: 99,
            expectedBundleIdentifier: "test.app",
            currentBundleIdentifier: "test.app",
            expectedWindowTitle: "Chat",
            currentWindowTitle: "Chat",
            elementMatches: true,
            isEditable: true,
            expiresAt: now.addingTimeInterval(60),
            now: now
        ) == .changed)
        precondition(RemoteTargetValidationPolicy.evaluate(
            expectedPID: 42,
            currentPID: 42,
            expectedBundleIdentifier: "test.app",
            currentBundleIdentifier: "test.app",
            expectedWindowTitle: "Chat",
            currentWindowTitle: "Other",
            elementMatches: false,
            isEditable: true,
            expiresAt: now.addingTimeInterval(60),
            now: now
        ) == .changed)
        precondition(RemoteTargetValidationPolicy.evaluate(
            expectedPID: 42,
            currentPID: 42,
            expectedBundleIdentifier: "test.app",
            currentBundleIdentifier: "test.app",
            expectedWindowTitle: "Chat",
            currentWindowTitle: "Chat",
            elementMatches: true,
            isEditable: true,
            expiresAt: now,
            now: now
        ) == .expired)

        let execute = RemoteMessage(
            kind: .executeRequest,
            action: .pasteAndSubmit,
            text: "測試文字",
            targetSessionID: target.sessionID
        )
        let executeDecoded = try RemoteMessageCodec.decode(
            RemoteMessage.self,
            from: RemoteMessageCodec.encode(execute)
        )
        precondition(executeDecoded.action == .pasteAndSubmit)
        precondition(executeDecoded.text == "測試文字")

        let phoneRevision = VocabularySyncRevision(counter: 3, deviceID: "phone")
        let macRevision = VocabularySyncRevision(counter: 4, deviceID: "mac")
        let sharedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let syncTimestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let phoneEntry = VocabularySyncEntry(
            id: sharedID,
            term: "UE Strategy",
            createdAt: syncTimestamp,
            updatedAt: syncTimestamp,
            revision: phoneRevision
        )
        let macEntry = VocabularySyncEntry(
            id: sharedID,
            term: "YUI Strategy",
            isPinned: true,
            createdAt: syncTimestamp,
            updatedAt: syncTimestamp,
            revision: macRevision
        )
        let mergedUpdate = VocabularySyncMerger.merge(
            local: .init(entries: [phoneEntry], tombstones: []),
            incoming: .init(entries: [macEntry], tombstones: [])
        )
        precondition(mergedUpdate.entries == [macEntry], "Newer monotonic revision must win")

        let deleted = VocabularySyncMerger.merge(
            local: mergedUpdate,
            incoming: .init(
                entries: [],
                tombstones: [.init(
                    id: sharedID,
                    revision: .init(counter: 5, deviceID: "phone")
                )]
            )
        )
        precondition(deleted.entries.isEmpty, "A newer deletion must not resurrect")
        precondition(deleted.tombstones.count == 1, "Deletion tombstone must be retained")

        let duplicatePhone = VocabularySyncEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            term: "Groq",
            createdAt: syncTimestamp,
            updatedAt: syncTimestamp,
            revision: .init(counter: 6, deviceID: "phone")
        )
        let duplicateMac = VocabularySyncEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            term: "ＧＲＯＱ",
            createdAt: syncTimestamp,
            updatedAt: syncTimestamp,
            revision: .init(counter: 7, deviceID: "mac")
        )
        let deduplicated = VocabularySyncMerger.merge(
            local: .init(entries: [duplicatePhone], tombstones: []),
            incoming: .init(entries: [duplicateMac], tombstones: [])
        )
        precondition(deduplicated.entries == [duplicateMac], "Normalized duplicates must converge")
        precondition(
            deduplicated.tombstones.contains { $0.id == duplicatePhone.id },
            "Duplicate loser must become a tombstone"
        )

        let syncMessage = RemoteMessage(
            kind: .vocabularySync,
            vocabulary: deduplicated
        )
        let syncDecoded = try RemoteMessageCodec.decode(
            RemoteMessage.self,
            from: RemoteMessageCodec.encode(syncMessage)
        )
        precondition(syncDecoded == syncMessage, "Vocabulary sync JSON round-trip failed")

        let suiteName = "RemoteProtocolTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MacVocabularyStore(
            defaults: defaults,
            now: { syncTimestamp }
        )
        let storedEntry = try store.add(term: "YUI Strategy", isPinned: true)
        precondition(store.contains(term: "ｙｕｉ strategy"), "Duplicate lookup must normalize width and case")
        let prompt = store.buildPrompt()
        precondition(prompt.text.contains("YUI Strategy"), "Mac prompt must use enabled vocabulary")
        precondition(prompt.includedEntryIDs == [storedEntry.id])
        store.setEnabled(false, for: storedEntry.id)
        precondition(!store.buildPrompt().text.contains("YUI Strategy"), "Disabled terms must leave the prompt")

        let persisted = MacVocabularyStore(defaults: defaults)
        precondition(persisted.entries.count == 1, "Mac vocabulary must persist")
        persisted.delete(id: storedEntry.id)
        precondition(persisted.entries.isEmpty)
        precondition(persisted.snapshot().tombstones.count == 1, "Mac deletion must persist a tombstone")

        let unknownAction = Data("{\"protocolVersion\":1,\"id\":\"x\",\"kind\":\"executeRequest\",\"action\":\"deleteEverything\"}".utf8)
        precondition(
            (try? RemoteMessageCodec.decode(RemoteMessage.self, from: unknownAction)) == nil,
            "Unknown remote actions must be rejected"
        )

        print("Remote protocol tests passed")
    }
}
