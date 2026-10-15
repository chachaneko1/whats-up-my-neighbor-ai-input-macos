import Foundation

enum NekoHUDPosition: String, CaseIterable {
    case topCenter, bottomCenter
    var displayName: String { self == .topCenter ? "上方中央" : "下方中央" }
}

/// Presentation-only metering. Missing input must never look like speech.
struct NekoSignalMeter {
    private(set) var levels = Array(repeating: 0.0, count: 11)

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

/// A stable preference, intentionally independent of application build numbers.
struct NekoIntroductionPreferences {
    private let defaults: UserDefaults
    private let key = "nekoHUD.hasSeenIntroduction"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var shouldShow: Bool { !defaults.bool(forKey: key) }
    func markShown() { defaults.set(true, forKey: key) }
}
