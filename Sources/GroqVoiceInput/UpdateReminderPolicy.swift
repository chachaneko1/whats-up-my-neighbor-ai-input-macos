import Foundation

// MARK: - 軟體更新提醒政策狀態機
// 純邏輯狀態機：負責管理新版本提醒狀態，確保「得知有新版本」絕不等於「獲得授權安裝」。
// 嚴格落實防干擾與隱私保護：
// 1. 錄音或重試中（isBusy == true）絕對不彈窗打擾使用者。
// 2. 若使用者允許系統通知，以低干擾的系統通知橫幅（Banner）提醒；若未開啟通知才直接開啟更新對話框。
// 3. 使用者手動點擊「檢查更新」時，標記 presentationRequested，在工作結束後立刻呈現更新介面。

/// Pure reminder policy: learning about a release never authorizes installation.
struct UpdateReminderPolicy {
    enum Action: Equatable { case none, notify, showUpdate }
    private(set) var version: String?
    private var reminded = false
    private var presentationRequested = false

    mutating func receive(version: String) {
        guard self.version != version else { return }
        self.version = version
        reminded = false
    }

    mutating func requestPresentation() { presentationRequested = true }

    // 決策下一個提醒動作：
    // - 忙碌中（isBusy）-> 不做任何事（.none）。
    // - 使用者手動請求（presentationRequested）-> 呈現更新視窗（.showUpdate）。
    // - 首次偵測到新版本且尚未提醒 -> 依通知權限決定發通知（.notify）或彈窗（.showUpdate）。
    mutating func nextAction(isBusy: Bool, notificationsAllowed: Bool) -> Action {
        guard !isBusy else { return .none }
        if presentationRequested {
            presentationRequested = false
            reminded = true
            return .showUpdate
        }
        guard version != nil, !reminded else { return .none }
        reminded = true
        return notificationsAllowed ? .notify : .showUpdate
    }

    mutating func clear() { self = UpdateReminderPolicy() }
}
