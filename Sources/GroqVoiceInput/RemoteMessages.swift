import Foundation

enum RemoteMessageKind: String, Codable, Sendable {
    case targetRequest
    case targetResponse
    case executeRequest
    case cancelRequest
    case result
}

enum RemoteAction: String, Codable, Sendable {
    case paste
    case pasteAndSubmit
    case cancel

    var submits: Bool { self == .pasteAndSubmit }
}

enum RemoteResultCode: String, Codable, Sendable {
    case targetReady
    case pasted
    case submitted
    case cancelled
    case notConnected
    case accessibilityDenied
    case noEditableTarget
    case targetChanged
    case targetExpired
    case invalidRequest
    case unsupportedVersion
    case internalError
}

struct RemoteTargetDescriptor: Codable, Equatable, Sendable {
    let sessionID: String
    let macName: String
    let appName: String
    let windowTitle: String
    let expiresAt: Date

    var displayName: String {
        windowTitle.isEmpty ? appName : "\(appName) — \(windowTitle)"
    }
}

struct RemoteResultPayload: Codable, Equatable, Sendable {
    let success: Bool
    let code: RemoteResultCode
    let message: String
}

struct RemoteMessage: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let protocolVersion: Int
    let id: String
    let kind: RemoteMessageKind
    let replyTo: String?
    let action: RemoteAction?
    let text: String?
    let target: RemoteTargetDescriptor?
    let targetSessionID: String?
    let result: RemoteResultPayload?

    init(
        id: String = UUID().uuidString,
        kind: RemoteMessageKind,
        replyTo: String? = nil,
        action: RemoteAction? = nil,
        text: String? = nil,
        target: RemoteTargetDescriptor? = nil,
        targetSessionID: String? = nil,
        result: RemoteResultPayload? = nil,
        protocolVersion: Int = RemoteMessage.currentVersion
    ) {
        self.protocolVersion = protocolVersion
        self.id = id
        self.kind = kind
        self.replyTo = replyTo
        self.action = action
        self.text = text
        self.target = target
        self.targetSessionID = targetSessionID
        self.result = result
    }
}

struct PairingInvitation: Codable, Sendable {
    let code: String?
    let installationID: String
}

enum RemoteMessageCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

enum RemoteProtocolPolicy {
    static func supports(_ version: Int) -> Bool {
        version == RemoteMessage.currentVersion
    }
}

enum RemoteActionPolicy {
    static func canExecute(hasText: Bool, hasTarget: Bool, isConnected: Bool, isWaiting: Bool) -> Bool {
        hasText && hasTarget && isConnected && !isWaiting
    }
}
