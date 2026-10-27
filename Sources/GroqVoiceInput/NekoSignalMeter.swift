import Foundation

// MARK: - 錄音 HUD 音量信號測量與展示邏輯
// 純呈現層的音量計算器與狀態對照表，絕對不直接接觸底層音訊資料流。
// 設計核心：
// 1. 嚴格閾值過濾：將 -48 dB 以下的音量直接視為 0（靜音），防止麥克風底噪或微弱環境音被誤判為說話。
// 2. 波形動畫：採用 11 格水平波形隊列，新音量由左耳進入並流向右耳（左進右出）。
// 3. 減弱動態效果（reducedMotion）：開啟時改為全域整體跳動，不產生水平流動動畫。

enum NekoHUDPosition: String, CaseIterable {
    case topCenter, bottomCenter
    var displayName: String { self == .topCenter ? "上方中央" : "下方中央" }
}

/// Presentation-only metering. Missing input must never look like speech.
struct NekoSignalMeter {
    private(set) var levels = Array(repeating: 0.0, count: 11)

    // 正規化音量：將 [-48 dB, -12 dB] 區間線性映射為 [0.0, 1.0] 浮點數值。
    static func normalizedPower(_ decibels: Float?) -> Double {
        guard let decibels, decibels.isFinite, decibels > -48 else { return 0 }
        return min(1, max(0, Double(decibels + 48) / 36))
    }

    mutating func update(decibels: Float?, reducedMotion: Bool = false) {
        let power = Self.normalizedPower(decibels)
        guard power > 0 else { reset(); return }
        if reducedMotion {
            levels = Array(repeating: power, count: levels.count)
        } else {
            // New sound enters at the left ear and travels toward the right ear.
            levels.removeLast()
            levels.insert(power, at: 0)
        }
    }

    mutating func reset() { levels = Array(repeating: 0, count: 11) }
}

// 錄音狀態與 HUD 視覺呈現的對照表：動態決定標題、取消按鈕標籤與可操作性。
struct NekoHUDPresentation {
    let title: String
    let cancelLabel: String
    let canCancel: Bool
    let canFinish: Bool

    init(state: DictationState) {
        canFinish = state == .recording
        canCancel = state != .idle && state != .delivering
        cancelLabel = state == .starting || state == .recording ? "取消錄音" : "取消處理"
        switch state {
        case .idle: title = "準備好了，慢慢說。"
        case .starting: title = "正在準備麥克風…"
        case .recording: title = "正在聽你說"
        case .finalizing: title = "正在完成錄音…"
        case .transcribing: title = "正在辨識…"
        case .awaitingRetry: title = "辨識未完成，等待重試"
        case .delivering: title = "正在貼入文字…"
        }
    }
}

// 記錄使用者是否看過初次操作引導（左眼取消、右眼完成），純偏好設定，不依賴 App 版本號。
/// A stable preference, intentionally independent of application build numbers.
struct NekoIntroductionPreferences {
    private let defaults: UserDefaults
    private let key = "nekoHUD.hasSeenIntroduction"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var shouldShow: Bool { !defaults.bool(forKey: key) }
    func markShown() { defaults.set(true, forKey: key) }
}
