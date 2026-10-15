import Foundation
import NaturalLanguage

struct MacVocabularyCandidate: Equatable {
    let originalSegment: String
    let suggestedTerm: String
}

enum MacVocabularyCorrectionExtractor {
    static func candidate(
        original: String,
        edited: String,
        maximumTermLength: Int = MacVocabularyStore.maximumTermLength
    ) -> MacVocabularyCandidate? {
        guard original != edited else { return nil }

        let originalCharacters = Array(original)
        let editedCharacters = Array(edited)
        let sharedPrefixCount = commonPrefixCount(originalCharacters, editedCharacters)
        let sharedSuffixCount = commonSuffixCount(
            originalCharacters,
            editedCharacters,
            excludingPrefixCount: sharedPrefixCount
        )

        let editedEnd = editedCharacters.count - sharedSuffixCount
        let originalEnd = originalCharacters.count - sharedSuffixCount
        let originalChange = sharedPrefixCount..<originalEnd
        let editedChange = sharedPrefixCount..<editedEnd
        let removed = String(originalCharacters[originalChange])
        let inserted = String(editedCharacters[editedChange])
        guard containsLetterOrNumber(removed) || containsLetterOrNumber(inserted) else { return nil }

        let originalWords = wordRanges(in: original, characters: originalCharacters)
        let editedWords = wordRanges(in: edited, characters: editedCharacters)
        if editedChange.isEmpty {
            let affected = originalWords.filter { $0.overlaps(originalChange) }
            // Removing a complete word is editing the sentence, not teaching its
            // neighbour. A deleted letter inside ChatGPTT or 語語音 remains eligible.
            if !affected.isEmpty, affected.allSatisfy({
                originalChange.lowerBound <= $0.lowerBound && originalChange.upperBound >= $0.upperBound
            }) { return nil }
        }

        var destinations = editedWords.filter {
            $0.lowerBound <= editedChange.lowerBound && $0.upperBound >= editedChange.upperBound
        }
        if editedChange.isEmpty {
            let interior = destinations.filter {
                $0.lowerBound < editedChange.lowerBound && editedChange.lowerBound < $0.upperBound
            }
            if !interior.isEmpty { destinations = interior }
        }

        var candidates: [MacVocabularyCandidate] = []
        for destination in destinations {
            // Map the full corrected word back through the one changed span.
            // This supplies a nonempty original for an insertion/deletion inside
            // a word, while a newly typed standalone word maps to an empty span.
            let source = destination.lowerBound..<(destination.upperBound + removed.count - inserted.count)
            guard source.lowerBound >= 0, source.upperBound <= originalCharacters.count,
                  !source.isEmpty else { continue }
            let originalSegment = String(originalCharacters[source])
            let suggestedTerm = String(editedCharacters[destination])
            guard containsLetterOrNumber(originalSegment),
                  originalSegment.count <= maximumTermLength, suggestedTerm.count <= maximumTermLength,
                  !originalSegment.contains(where: { $0.isWhitespace || "。！？；.!?;".contains($0) }),
                  !suggestedTerm.contains(where: { $0.isWhitespace || "。！？；.!?;".contains($0) }) else { continue }

            let sourceWords = originalWords.filter { $0.overlaps(source) }
            if sourceWords.count > 1 {
                // A typo can split a Chinese word into two tokens (字 + 點), but
                // replacing several words or an entire sentence is not a term.
                let unchanged = destination.count - editedChange.count
                guard unchanged > 0, originalChange.count <= 2, editedChange.count <= 2 else { continue }
            }
            let candidate = MacVocabularyCandidate(originalSegment: originalSegment, suggestedTerm: suggestedTerm)
            if !candidates.contains(candidate) { candidates.append(candidate) }
        }
        // A deletion exactly between two plausible words is ambiguous.
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func commonPrefixCount(_ lhs: [Character], _ rhs: [Character]) -> Int {
        var count = 0
        while count < min(lhs.count, rhs.count), lhs[count] == rhs[count] {
            count += 1
        }
        return count
    }

    private static func commonSuffixCount(
        _ lhs: [Character],
        _ rhs: [Character],
        excludingPrefixCount prefixCount: Int
    ) -> Int {
        var count = 0
        while count < lhs.count - prefixCount,
              count < rhs.count - prefixCount,
              lhs[lhs.count - count - 1] == rhs[rhs.count - count - 1] {
            count += 1
        }
        return count
    }

    private static func wordRanges(in text: String, characters: [Character]) -> [Range<Int>] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var offsets = Dictionary(uniqueKeysWithValues: text.indices.enumerated().map { ($0.element, $0.offset) })
        offsets[text.endIndex] = characters.count
        var result: [Range<Int>] = []
        var seen = Set<Range<Int>>()
        for token in tokenizer.tokens(for: text.startIndex..<text.endIndex) {
            guard var lower = offsets[token.lowerBound], var upper = offsets[token.upperBound],
                  lower < upper, containsLetterOrNumber(String(text[token])) else { continue }
            // Keep technical names such as foo_bar and gpt-4o together.
            if characters[lower..<upper].allSatisfy(isASCIIWordCharacter) {
                while lower > 0, isASCIIWordCharacter(characters[lower - 1]) { lower -= 1 }
                while upper < characters.count, isASCIIWordCharacter(characters[upper]) { upper += 1 }
            }
            let range = lower..<upper
            if seen.insert(range).inserted { result.append(range) }
        }
        return result
    }

    private static func isASCIIWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            $0.isASCII && (
                CharacterSet.alphanumerics.contains($0)
                    || $0.value == 0x5F
                    || $0.value == 0x2D
            )
        }
    }

    private static func containsLetterOrNumber(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }
}

struct TrackedPasteRange: Equatable {
    var location: Int
    var length: Int

    var upperBound: Int {
        location + length
    }
}

enum TrackedPasteEditDecision: Equatable {
    case observe(newLength: Int)
    case shift(newLocation: Int)
    case ignore
}

enum TrackedPasteEditPolicy {
    static func boundariesMatch(expectedLeading: String, expectedTrailing: String,
                                currentLeading: String, currentTrailing: String) -> Bool {
        expectedLeading == currentLeading && expectedTrailing == currentTrailing
    }

    /// A replacement that crosses either boundary cannot be attributed to only
    /// the dictated text, even if most of its selection overlaps that text.
    static func selectionCrossesBoundary(location: Int, length: Int, range: TrackedPasteRange) -> Bool {
        guard length > 0 else { return false }
        let end = location + length
        let intersects = location < range.upperBound && range.location < end
        return intersects && (location < range.location || end > range.upperBound)
    }

    static func evaluate(
        range: TrackedPasteRange,
        previousCharacterCount: Int,
        currentCharacterCount: Int,
        caretLocation: Int,
        selectedCorrectionIntersectsRange: Bool,
        isEditingBurst: Bool,
        existingRangeTextChanged: Bool = false
    ) -> TrackedPasteEditDecision {
        let delta = currentCharacterCount - previousCharacterCount
        let proposedLength = max(0, range.length + delta)

        if selectedCorrectionIntersectsRange {
            return .observe(newLength: proposedLength)
        }

        if caretLocation < range.location {
            return .shift(newLocation: max(0, range.location + delta))
        }

        if caretLocation < range.upperBound {
            return .observe(newLength: proposedLength)
        }

        if delta < 0, caretLocation <= range.upperBound {
            return .observe(newLength: proposedLength)
        }

        // Polling may miss a fast selection-and-replace at the last character.
        // Only include the new endpoint if text already inside the verified
        // range changed; ordinary typing appended after it remains outside.
        if existingRangeTextChanged, delta >= 0,
           caretLocation <= range.upperBound + delta {
            return .observe(newLength: proposedLength)
        }

        if isEditingBurst,
           caretLocation <= range.upperBound + max(1, delta) {
            return .observe(newLength: proposedLength)
        }

        return .ignore
    }
}
