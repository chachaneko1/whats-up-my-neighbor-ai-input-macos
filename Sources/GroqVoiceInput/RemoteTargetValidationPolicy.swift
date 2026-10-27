import Foundation

// MARK: - 遠端輸入目標有效性評估政策
// 評估 Mac 端在執行手機傳送過來的貼上或送出前，當前前景聚焦的視窗是否與當初鎖定的一致。
// 避免因使用者在手機錄音期間切換了視窗，導致語音文字被誤貼至不相干甚至機密的視窗（例如終端機或聊天室）。

enum RemoteTargetValidationFailure: Equatable {
    case expired
    case changed
}

enum RemoteTargetValidationPolicy {
    // 嚴格檢驗目標是否依舊合法：
    // 1. 未逾時（預設 TTL 300 秒）。
    // 2. PID 與 Bundle Identifier 完全匹配（防止相同名稱的進程欺騙）。
    // 3. 視窗標題完全一致（防止在同一個瀏覽器或通訊軟體內切換了分頁或對話視窗）。
    // 4. Accessibility 元件指針匹配且仍然處於可編輯狀態。
    static func evaluate(
        expectedPID: pid_t,
        currentPID: pid_t?,
        expectedBundleIdentifier: String,
        currentBundleIdentifier: String?,
        expectedWindowTitle: String,
        currentWindowTitle: String?,
        elementMatches: Bool,
        isEditable: Bool,
        expiresAt: Date,
        now: Date = Date()
    ) -> RemoteTargetValidationFailure? {
        guard expiresAt > now else { return .expired }
        guard currentPID == expectedPID,
              currentBundleIdentifier == expectedBundleIdentifier,
              currentWindowTitle == expectedWindowTitle,
              elementMatches,
              isEditable else { return .changed }
        return nil
    }
}
