# 第一批重構交接

後續詞典開發進度見 [詞典學習修正](VOCABULARY_IMPLEMENTATION.md)；下文是第一批重構完成時的紀錄。

日期：2026-10-14。分支：`codex/neko-foundation-refactor`。基線：GitHub main `ee0467724d80f3738ad386f72a2b008decaacd86`。

本批完成語音輸入核心拆分，供之後的 YUI Neko 視窗、對話及記憶功能接入。App 仍是原生 macOS 選單列語音輸入，使用既有 Groq 轉錄與固定文字規則；本批沒有新增桌面黑貓、聊天模型、螢幕擷取或資料庫。

## 原工作保全

實作位於獨立 Git worktree，原工作目錄仍停在 `agent/merge-local-remote-features`。前後核對 HEAD、分支、工作狀態、staged 與 unstaged 差異的 SHA-256，以及 28 個 tracked／untracked 檔案的 SHA-256，全部一致。main 沒有新增 commit。

原工作包含尚未整合的詞典、協定 v2、版本及簽章變更，細節見 [LOCAL_BASELINE.md](LOCAL_BASELINE.md)。這些內容保留在原處，沒有混入或刪除。本分支也未安裝或取代使用者目前的 App，沒有讀取真實 API Key、發送錄音或更動系統權限。

## 現在的模組

| 模組 | 責任 |
|---|---|
| `main.swift` | 6 行 App 啟動入口；原先為 1,648 行 |
| `VoiceTypeController` | 組裝服務、連接選單／對話框與 App 生命週期 |
| `StatusMenuController`、`SettingsViews` | 選單與原設定介面 |
| `HotKeyManager` | 管理三組 Carbon 全域快捷鍵與解除註冊 |
| `SettingsStore`、`KeychainStore` | 沿用既有偏好鍵值及 API Key 儲存方式 |
| `DictationCoordinator` | 錄音到文字交付的狀態、設定快照、取消、重試及期限 |
| `PinnedMicrophoneRecorder` | 既有指定麥克風與 AVCaptureSession；完成檔案後才回報 |
| `GroqDictationTranscriber` | 非同步轉錄、主執行緒回呼與可取消請求 |
| `TemporaryRecordingStore` | 產生錄音路徑與清理本 App 暫存 |
| `FocusTargetService`、`TextInsertionService` | 本機與遠端共用焦點驗證、複製及貼上事件 |
| `RemoteTargetController` | 保留原 iPhone v1 動作與明確送出流程 |

依賴方向為「UI → coordinator → 錄音／轉錄／暫存介面」。Coordinator 只依賴 Foundation 與既有語言、文字規則，不需要 AppKit 或 Keychain；測試可注入錄音器、轉錄器、時鐘與排程器。

## 保留與明確調整的行為

- 保留指定麥克風、三種文字模式、語言設定、第二快捷鍵、五分鐘上限與可選靜音停止。App 身分、版本、所有原偏好鍵值及 Keychain service/account 不變。
- Groq endpoint、模型、請求欄位及錯誤處理沿用原契約；轉錄客戶端增加可取消回傳值與預設立即啟動的選項。Adapter 先建立暫停的請求，再原子地接上取消控制，避免取消期間意外開始上傳。
- 每次工作固定開始時的設定，並以 session/request ID 忽略舊回呼。自動語言重試最多一次，遵守使用者開關；人工重試也必須通過語言檢查。
- 選單新增取消與重新辨識保留錄音。取消錄音後，錄音器仍維持忙碌至檔案收尾完成，避免舊完成回呼停止下一次錄音。
- 本機開始錄音時記錄目標；完成後先複製，再驗證同一 App、視窗與元素才發送 Cmd+V。無法驗證時提示手動貼上，本機仍不送 Enter。
- 剪貼簿寫入成功即算文字已交付並清除錄音；「發送貼上事件」不表示已證實對方 App 接收。剪貼簿失敗時保留錄音供重試。
- 失敗錄音每次保留兩分鐘；取消、捨棄、過期、新錄音取代、成功交付及正常結束時清理。異常結束的殘留檔由下次啟動清理。
- 接力模式仍每次啟動關閉，MacRemoteBridge 與 RemoteMessages v1 沒有更動。遠端延遲完成只清除自己的 session，不會清掉新鎖定的目標。

## 驗證

- `./scripts/test-all.sh`：八套離線測試，涵蓋原音訊政策、文字處理、舊版結果對照、遠端協定，以及新增設定、焦點／貼上與 dictation 生命週期。
- `./scripts/build.sh`：完整編譯成功，ad-hoc 簽章的嚴格驗證通過。輸出為本 worktree 的 `build/AI語音輸入.app`。
- `git diff --check`：通過。
- 原工作目錄的上述指紋比對：全部一致。
- `Info.plist`、建置／簽章腳本、RemoteMessages、MacRemoteBridge、LanguagePolicy、TextPostProcessor 與 main 基線逐檔比較：未修改。

CI 現在先執行離線測試，再建置。原 remote 測試腳本要求外部 iOS repo，乾淨 clone 會失敗；已將本 repo 測試與跨 repo 比對分開。實際 iOS 協定一致性需另外提供檔案執行 `scripts/check-remote-protocol-parity.sh`，不包含在本輪「通過」的範圍。

## 尚待實機驗證

本輪沒有啟動、安裝新 App，也沒有使用真正麥克風或 iPhone。以下是進入日常使用或合併前的人工回歸項目：

1. TextEdit 與瀏覽器輸入框：快捷鍵／選單開始停止、三種模式、第二快捷鍵與設定保留。
2. 開始、錄音、收尾與辨識期間取消，再快速重新錄音；確認麥克風釋放及沒有舊文字輸出。
3. 切換 App／視窗／輸入框、拒絕輔助使用權限，以及安全欄位的手動貼上提示。
4. 網路錯誤、人工重試、錄音逾時與靜音停止。
5. iPhone 配對、接力開關、只貼上及明確貼上並送出；以相同 v1 協定版本測試。

相容性限制：部分 App 接受 Cmd+V，但不透過 Accessibility 提供可寫入的文字元素；新驗證會轉為只複製。選單觸發時的焦點擷取也需實機確認。離線測試與成功建置不能取代上述回歸。

## 下一批接點

先在這些模組上完成實機驗收，再新增獨立的桌面角色視窗。角色狀態可訂閱 coordinator 的工作狀態；未來對話、螢幕與記憶服務分別接入，不把邏輯加回啟動入口。原本機詞典及協定 v2 應以獨立整合批次逐項移植並同時驗證 iPhone 端。
