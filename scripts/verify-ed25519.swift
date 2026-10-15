import CryptoKit
import Foundation

// Only public verification material is passed on the command line.
guard CommandLine.arguments.count == 5,
      let key = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[2]),
      let length = Int(CommandLine.arguments[4]), length >= 0 else { exit(1) }
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
    guard length <= data.count else { exit(1) }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
    guard publicKey.isValidSignature(signature, for: data.prefix(length)) else { exit(1) }
} catch { exit(1) }
