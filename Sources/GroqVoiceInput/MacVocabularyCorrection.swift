import Foundation

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
        guard sharedPrefixCount < editedEnd else { return nil }

        let originalEnd = originalCharacters.count - sharedSuffixCount
        var originalSegment = String(
            originalCharacters[sharedPrefixCount..<max(sharedPrefixCount, originalEnd)]
        )
        var suggestedTerm = String(editedCharacters[sharedPrefixCount..<editedEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard containsLetterOrNumber(suggestedTerm) else { return nil }

        if shouldExpandToWord(suggestedTerm) {
            suggestedTerm = expandedTerm(
                in: editedCharacters,
                changedRange: sharedPrefixCount..<editedEnd
            )
            if !originalSegment.isEmpty, shouldExpandToWord(originalSegment) {
                originalSegment = expandedTerm(
                    in: originalCharacters,
                    changedRange: sharedPrefixCount..<originalEnd
                )
            }
        }

        suggestedTerm = suggestedTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard containsLetterOrNumber(suggestedTerm),
              suggestedTerm.count <= maximumTermLength else {
            return nil
        }

        return MacVocabularyCandidate(
            originalSegment: originalSegment,
            suggestedTerm: suggestedTerm
        )
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

    private static func shouldExpandToWord(_ term: String) -> Bool {
        let characters = Array(term)
        guard !characters.isEmpty else { return false }
        return characters.count == 1 || characters.allSatisfy(isASCIIWordCharacter)
    }

    private static func expandedTerm(
        in characters: [Character],
        changedRange: Range<Int>
    ) -> String {
        guard !characters.isEmpty else { return "" }

        var lowerBound = min(changedRange.lowerBound, characters.count - 1)
        var upperBound = min(max(changedRange.upperBound, lowerBound + 1), characters.count)

        if isASCIIWordCharacter(characters[lowerBound]) {
            while lowerBound > 0, isASCIIWordCharacter(characters[lowerBound - 1]) {
                lowerBound -= 1
            }
            while upperBound < characters.count, isASCIIWordCharacter(characters[upperBound]) {
                upperBound += 1
            }
        } else if upperBound < characters.count, isCJKCharacter(characters[upperBound]) {
            upperBound += 1
        } else if lowerBound > 0, isCJKCharacter(characters[lowerBound - 1]) {
            lowerBound -= 1
        }

        return String(characters[lowerBound..<upperBound])
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

    private static func isCJKCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            switch $0.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                true
            default:
                false
            }
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
    static func evaluate(
        range: TrackedPasteRange,
        previousCharacterCount: Int,
        currentCharacterCount: Int,
        caretLocation: Int,
        selectedCorrectionIntersectsRange: Bool,
        isEditingBurst: Bool
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

        if isEditingBurst,
           caretLocation <= range.upperBound + max(1, delta) {
            return .observe(newLength: proposedLength)
        }

        return .ignore
    }
}
