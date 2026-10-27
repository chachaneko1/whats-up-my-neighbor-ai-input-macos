import Foundation

// MARK: - 遠端接力通訊協定訊息類型與酬載定義
// 定義 iPhone（GroqVoice / YUI companion）與 Mac 端之間進行近場 MultipeerConnectivity
// 通訊時的統一訊息封包。所有遠端輸入請求、目標視窗鎖定與狀態回報均基於此協議。

enum RemoteMessageKind: String, Codable, Sendable {
    case targetRequest
    case targetResponse
    case executeRequest
    case cancelRequest
    case result
}

// 遠端要求的操作動作：僅貼上或貼上後送出（模擬 Return 鍵）。
enum RemoteAction: String, Codable, Sendable {
    case paste
    case pasteAndSubmit
    case cancel

    var submits: Bool { self == .pasteAndSubmit }
}

// 遠端操作結果碼：精確劃分成功、無障礙權限缺失、目標失效（視窗切換）、逾時或版本不相容。
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

// 傳遞給 iPhone 顯示的目標輸入框資訊（如「Slack — #general」），不洩漏敏感內文。
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

// 操作執行結果詳細酬載。
struct RemoteResultPayload: Codable, Equatable, Sendable {
    let success: Bool
    let code: RemoteResultCode
    let message: String
}

// 雙端通訊的頂層訊息封裝結構。
struct RemoteMessage: Codable, Equatable, Sendable {
    // 協議版本號：若 iPhone 端與 Mac 端的 currentVersion 不相符，直接阻斷連線並提示升級。
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

// 配對邀請封包：包含由 Mac 生成的臨時動態 6 位數配對碼與安裝識別碼。
struct PairingInvitation: Codable, Sendable {
    let code: String?
    let installationID: String
}

// 統一 JSON 編解碼器：強制使用 ISO8601 日期標準，避免雙端系統區域設定不同導致的時間解析差異。
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

// 協議版本檢查政策：目前採取嚴格單一版本比對。
enum RemoteProtocolPolicy {
    static func supports(_ version: Int) -> Bool {
        version == RemoteMessage.currentVersion
    }
}

// 遠端動作執行前置檢查規則：文字、鎖定目標、連線狀態與非等待中四者缺一不可。
enum RemoteActionPolicy {
    static func canExecute(hasText: Bool, hasTarget: Bool, isConnected: Bool, isWaiting: Bool) -> Bool {
        hasText && hasTarget && isConnected && !isWaiting
    }
}
