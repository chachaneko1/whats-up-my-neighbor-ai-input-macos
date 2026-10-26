import Foundation

/// The VPS desktop menu item is clickable only on a Mac with the SSH alias and Node.js.
enum VPSDesktopAvailability {
    static let hostAlias = "neighbor-vps"
    static let nodeCandidates = [
        "/opt/homebrew/opt/node@24/bin/node",
        "/opt/homebrew/bin/node",
        "/usr/local/opt/node@24/bin/node",
        "/usr/local/bin/node",
    ]

    static func isAvailable() -> Bool {
        let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return false }
        return declaresHost(text) && nodePath() != nil
    }

    static func nodePath(isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> String? {
        nodeCandidates.first(where: isExecutable)
    }

    /// Only an exact `Host` entry counts; wildcards, negations and `Include` files are not followed.
    static func declaresHost(_ config: String, alias: String = hostAlias) -> Bool {
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = (rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
                .trimmingCharacters(in: .whitespaces)
            let words = line.split(whereSeparator: { $0 == "=" || $0.isWhitespace })
            guard let keyword = words.first, keyword.lowercased() == "host" else { continue }
            if words.dropFirst().contains(where: { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) == alias }) {
                return true
            }
        }
        return false
    }
}
