# 測試方式與驗證範圍

這份文件說明哪些行為有自動化測試保護、怎麼執行，以及哪些事情**只能在真實 Mac 上用手驗收**。送 PR 前，至少跑過和你改動相關的那幾組。

對照版本：1.4.4（build 1011）。

## 怎麼跑

全部：

```bash
./scripts/test-all.sh
```

單組：

```bash
./scripts/test-text-pipeline.sh
```

每組測試都是一個獨立的 shell 腳本：用 `swiftc` 把被測的原始碼和 `Tests/` 裡對應的測試檔編成一個小執行檔，執行後印出通過訊息，失敗時以非零狀態結束。沒有使用 XCTest，所以只需要 Command Line Tools。

`test-all.sh` 遇到第一個失敗就會停下來。修正後重跑，或先單獨跑失敗的那一組。

## 執行環境的前提

- **不需要網路、不需要 Groq Key**：辨識相關測試用假的辨識器與假的 HTTP 回應。
- **不碰你的資料**：剪貼簿測試使用私有的 `NSPasteboard`，金鑰與更新測試使用拋棄式的暫存 keychain 和檔案，不讀寫系統剪貼簿與你的鑰匙圈。
- **需要解鎖的桌面**：錄音浮窗、貓咪、桌面夥伴、剪貼簿選單與詞典提示的測試會開出不搶焦點的原生視窗，檢查繪製與動畫。螢幕鎖定或休眠時，動畫計時不會前進，這幾組可能失敗。
- 部分測試會在 `build/cat-render/` 輸出貓咪畫面截圖，CI 會把它們上傳成 artifact 供人工檢查。

## 每一組在保護什麼

| 腳本 | 主要內容 |
|---|---|
| `test-text-pipeline.sh` | 簡繁轉換、標點、中英文空格、三種輸出模式、法律用語不被改寫、中文數字轉換、語言閘門與設定遷移 |
| `test-transcription-client.sh` | Groq 請求的欄位、標頭與 multipart 內容；回應與錯誤訊息解析 |
| `test-legacy-parity.sh` | 重構後的請求、回應與錯誤訊息和舊版完全一致 |
| `test-dictation-coordinator.sh` | 錄音狀態機：只上傳有效錄音、自動重試一次、失敗保留錄音與期限、取消、彩蛋指令不輸出文字 |
| `test-text-insertion.sh` | 本機只貼上、密碼欄位排除、目標驗證；iPhone 接力的送出前再驗證、過期與重複請求 |
| `test-audio-input-policy.sh` | 排除 iPhone 連續互通麥克風、預設裝置退回內建麥克風、固定麥克風偏好 |
| `test-remote-protocol.sh` | iPhone 接力的訊息格式與協定版本相容 |
| `test-settings-store.sh` | 既有偏好設定 key、預設值與遷移；桌面夥伴首次預設收回 |
| `test-clipboard-history-store.sh` | 10 筆上限、重複合併、單筆大小限制與持久化 |
| `test-clipboard-history-monitor.sh` | 只收新變更、排除敏感與暫存標記、檔案與圖片不收錄 |
| `test-clipboard-history-insertion.sh` | 語音結果寫入歷史，即使自動貼上被拒絕也保留 |
| `test-clipboard-history-menu.sh`、`test-clipboard-picker.sh` | 剪貼簿選單與快捷視窗的選取、Enter 只貼上、Esc 關閉 |
| `test-paste-correction-monitor.sh` | 貼上後修正的觀察範圍、時限、競態與診斷 |
| `test-vocabulary-correction.sh`、`test-vocabulary-learning.sh` | 修正候選的萃取、六秒提示後加入、拒絕與提示額度 |
| `test-vocabulary-toast.sh` | 學習提示的倒數、滑鼠停留暫停與畫面位置 |
| `test-paste-diagnostics.sh` | 診斷記錄不包含剪貼內容與來源 App 名稱 |
| `test-neko-hud.sh` | 錄音浮窗的狀態、首次引導與位置 |
| `test-cat.sh` | `cat.config.json` 的格式驗證（317 項）、招呼觸發與冷卻、浮窗與嘴型動畫 |
| `test-desktop-pet.sh` | 桌面小黑貓的動作循環、資料夾停靠、減少動態效果、點擊穿透與焦點保留 |
| `test-updates.sh` | 更新提醒延後與去重；發布檔的版本、簽章、SHA-256 與 Sparkle Ed25519 驗證（含竄改拒絕） |

## 只能在真實 Mac 上確認的事

自動化測試能證明邏輯正確，但下面這些牽涉到 macOS 權限、真實裝置或長時間使用，測試**不會**假裝已經驗證：

- 第一次安裝時的 Gatekeeper 提示、麥克風與輔助使用授權流程。
- 真實麥克風錄音、Groq 實際辨識品質與網路中斷時的重試。
- 在各種 App（瀏覽器、Electron 編輯器、聊天軟體）裡的自動貼上相容性。
- 系統通知、使用者選擇安裝更新、錄音中延後重新啟動。
- 從舊版升級後的鑰匙圈與權限沿用。
- 多螢幕切換、整晚放著的耗電，以及桌面圖示長時間變動時的小黑貓行為。
- iPhone 與 Mac 兩台實機的配對、收音、只貼上與貼上並送出。

回報這類結果時，請寫明 macOS 版本、Mac 機型、App 版本與實際步驟。

## CI

`.github/workflows/build.yml` 在每次 push 與 PR 執行：建置 Universal 2 App、跑 `test-all.sh`、打包開發用安裝包並保留七天。PR 與 fork 的工作拿不到任何發布用的憑證。

正式發布另有流程與額外驗證，見 [UPDATES.md](UPDATES.md)。

## 新增測試的方式

1. 在 `Tests/` 新增 `XxxTests.swift`，用 `@main` 寫一個執行檔，失敗時 `preconditionFailure` 或以非零狀態結束。
2. 在 `scripts/` 新增 `test-xxx.sh`，用 `swiftc` 把需要的原始碼和測試檔編在一起執行（可以參考 `test-text-pipeline.sh`）。
3. `test-all.sh` 會自動找到新的 `test-*.sh`，不用另外登記。

被測的模組最好像 `GroqTranscriptionClient.swift`、`DictationCoordinator.swift` 一樣只 import Foundation，把 AppKit 和系統呼叫放在外層，測試就不需要開視窗。
