# 第一批重構：影響範圍與驗證

日期：2026-10-14。基線：GitHub main `ee0467724d80f3738ad386f72a2b008decaacd86`。
使用者授權：先比較本機未提交工作，在新分支保留語音輸入功能並重構；不得覆蓋本機改動或直接修改 main。

## 範圍與順序

1. 讓五套離線測試可從乾淨 checkout 執行；跨 repo 協定一致性獨立檢查，CI 執行測試。
2. 抽離設定視圖、快捷鍵、偏好與 Keychain；入口只啟動 App，依賴由控制器組裝。
3. 將錄音、完成、轉錄、有限重試、取消及暫存生命週期集中到可注入的 DictationCoordinator。每次工作固定設定、使用 session/request ID 拒絕過期回呼。
4. 共用原有遠端焦點擷取／驗證能力，本機開始時記錄目標、完成時先複製再驗證及發送 Cmd+V。回報發送事件與複製降級，不能假稱目標已確認插入。
5. 執行新增流程測試、既有 consumer 測試、建置／簽章及差異檢查；比對原本 dirty checkout 的內容、index 與 branch 指紋。

## 消費者與保護範圍

- 錄音器、轉錄器、語言與文字規則供本機 dictation；新 coordinator 透過介面呼叫。
- 選單與 Carbon 三組快捷鍵仍觸發既有操作；UI 主執行緒更新。
- RemoteTargetController 與本機輸出共用焦點服務；RemoteMessages v1、MacRemoteBridge 配對／加密／接力預設關閉不變。
- Groq endpoint、whisper-large-v3、plain JSON、設定的主要語言、固定文字規則不變。不增加聊天模型、資料庫、付費、網路 provider 或長期歷史。
- Bundle ID、UserDefaults key、Keychain service/account、安裝及簽章策略不變。本輪不安裝或替換執行中的 App，不存取真實 API Key。
- 本機詞典、protocol v2、Apple Development 簽章與版本號留在原工作目錄，另作整合候選；不整棵套入 main。

## 預先釐清的行為

- 目標在錄音後改變：仍複製文字，但不對另一個輸入框發貼上事件。本機始終不送 Enter。
- 回應採錄音開始時的語言、文字模式、數字轉換設定，避免途中更改設定影響已錄內容。
- 失敗等待重試有兩分鐘期限；明確捨棄、取消、成功交付或新錄音取代時刪除舊錄音。語言自動重試維持一次。
- 交付成功指剪貼簿寫入成功（可帶已發送貼上事件），不等同於已確認目標 App 接收；文件同步使用這個定義。

## 風險與證據

風險：高。變更集中在非同步共享狀態與跨 App 貼上；採純流程測試、注入依賴與既有目標驗證來限制風險，不擴張遠端動作範圍。

基線：四支現有測試腳本通過；remote 原腳本因缺外部 iOS 檔案在 cmp 階段失敗，但本 repo 的 RemoteProtocolTests 直接編譯執行通過。前一輪同 commit 建置及嚴格簽章通過；本輪修改後須重新執行。

自動化驗收：熱鍵忙碌拒絕、檔案完成才上傳、設定快照、單次自動重試、人工重試、過期結果、取消、保留逾時、五分鐘錄音限制、靜音停止、剪貼簿降級與目標變更拒絕。

實機驗收仍需後續對麥克風、全域快捷鍵、TextEdit／瀏覽器焦點與 iPhone 做回歸；不能用編譯成功代替。

## 完成紀錄

上述五個步驟已實作。最終模組、行為差異、驗證結果與人工回歸項目集中在 [REFACTOR_VALIDATION.md](REFACTOR_VALIDATION.md)。離線測試已擴充為八套；dictation 測試包含 17 組情境，另以隔離的 URLSession 驗證暫停、恢復及取消請求，不呼叫真實 API。
