// Translate a public English test sentence with macOS's installed local model.
import Foundation
import Translation

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let sentence = String(data: input, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !sentence.isEmpty else { throw NSError(domain: "empty input", code: 1) }
let session = TranslationSession(installedSource: Locale.Language(identifier: "en"),
                                 target: Locale.Language(identifier: "zh-Hant"))
var parts: [String] = []
sentence.enumerateSubstrings(in: sentence.startIndex..<sentence.endIndex,
                             options: .bySentences) { part, _, _, _ in
    if let part { parts.append(part.trimmingCharacters(in: .whitespacesAndNewlines)) }
}
for (index, part) in parts.enumerated() {
    let start = ProcessInfo.processInfo.systemUptime
    let response = try await session.translate(part)
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    print("segment=\(index + 1) seconds=\(String(format: "%.3f", elapsed))")
    print(response.targetText)
}
