import Foundation

/// 一個可以用來錄音的輸入裝置。
///
/// `uid` 對應 CoreAudio 的 `kAudioDevicePropertyDeviceUID`。實機驗證過它與
/// `AVCaptureDevice.uniqueID` 完全一致（內建麥克風、iPhone 連續互通、虛擬裝置
/// 四者全部對得上），所以可以用 CoreAudio 分類、用 AVFoundation 選取，
/// 兩邊共用同一個字串當識別碼。
struct AudioInputDevice: Equatable {
    let uid: String
    let name: String
    let transportType: UInt32
    let isSystemDefault: Bool
}

/// 決定每次錄音要用哪一個輸入裝置。
///
/// 這是純決策邏輯，不碰 CoreAudio 也不碰 AVFoundation，所以能單獨編譯測試
/// （見 `scripts/test-audio-input-policy.sh`）。實際的裝置列舉在
/// `AudioInputDevices.swift`。
enum AudioInputPolicy {
    /// 連續互通擷取（Continuity Capture）裝置的 transport type。
    ///
    /// 這是 iPhone 被 macOS 註冊成 Mac 輸入裝置時的身分，跟本 App 的 iPhone
    /// 接力功能完全無關：手機 App 沒開、手機鎖屏、手機在別的房間，這個裝置
    /// 都存在。一旦它被選為錄音來源，macOS 會隔空把手機的麥克風叫醒，而使用者
    /// 這端只會錄到一段靜音。
    static let continuityCaptureWired: UInt32 = 0x6363_7764 // 'ccwd'
    static let continuityCaptureWireless: UInt32 = 0x6363_776C // 'ccwl'
    /// macOS 13 起已棄用，仍保留判斷以涵蓋舊系統回報的舊值。
    static let continuityCaptureLegacy: UInt32 = 0x6363_6170 // 'ccap'
    /// 內建麥克風，被 macOS 搶走預設輸入時的退路。
    static let builtIn: UInt32 = 0x626C_746E // 'bltn'

    static func isContinuityCapture(_ transportType: UInt32) -> Bool {
        transportType == continuityCaptureWired
            || transportType == continuityCaptureWireless
            || transportType == continuityCaptureLegacy
    }

    /// 依序決定這次錄音要用哪個裝置。
    ///
    /// 規則的重點是「排除連續互通」而不是「強制內建」：AirPods、USB 麥克風
    /// 都是合理的 Mac 端輸入來源，不該因為這次修正被改掉。只有當 macOS 把
    /// 預設輸入切到 iPhone 時才介入。
    ///
    /// 回傳 nil 表示完全沒有可用的輸入裝置，呼叫端應視為無法錄音。
    static func selectDevice(
        from devices: [AudioInputDevice],
        preferredUID: String?
    ) -> AudioInputDevice? {
        // Desktop dictation never opens phone hardware, including a UID saved
        // by an older version. Phone audio belongs to explicit phone relay.
        let localDevices = devices.filter { !isContinuityCapture($0.transportType) }
        // 使用者指定的固定裝置優先。找不到時（例如 USB 麥克風被拔掉）不報錯，
        // 直接往下走自動規則，避免拔個線就完全不能錄音。
        if let preferredUID,
           let pinned = localDevices.first(where: { $0.uid == preferredUID }) {
            return pinned
        }

        let systemDefault = localDevices.first { $0.isSystemDefault }

        // 系統預設不是 iPhone 就直接用它，維持既有行為。
        if let systemDefault, !isContinuityCapture(systemDefault.transportType) {
            return systemDefault
        }

        // 到這裡表示系統預設被 macOS 切到了 iPhone（或根本沒有預設裝置）。
        if let builtInDevice = localDevices.first(where: { $0.transportType == builtIn }) {
            return builtInDevice
        }

        // 沒有內建麥克風的機型（例如接外接螢幕的 Mac mini）：退回任一非連續互通裝置。
        return localDevices.first
    }
}
