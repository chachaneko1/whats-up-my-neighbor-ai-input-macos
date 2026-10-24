# 架構與資料流

這份文件說明 What's up my neighbor（macOS）從按下快捷鍵到文字回到輸入框，中間經過哪些模組、資料在哪裡停留。想修改程式前，先從這裡找到要動的檔案。

對照版本：1.4.5（build 1012）；`main` 另含尚未隨正式版發布的毛色外觀。所有原始碼在 `Sources/GroqVoiceInput/`，共 53 個 Swift 檔（1.4.5 正式版是 50 個，另外 3 個是尚未發布的毛色外觀），沒有第三方相依套件，只有更新功能使用 Sparkle 2.10.0。

## 一句話版本

```text
快捷鍵 → 鎖定輸入目標 → 錄音（指定麥克風）→ 暫存檔 → Groq 雲端辨識
      → 語言檢查 → 本機文字處理 → 剪貼簿 → 驗證目標後模擬 ⌘V → 刪除暫存檔
```

App 是選單列常駐程式（`LSUIElement`），沒有主視窗、沒有自己的後端，也沒有分析工具。網路只用在三個地方：Groq 辨識、Sparkle 檢查更新、選用的 iPhone 附近連線。

## 主要流程

### 1. 快捷鍵與錄音開始

| 步驟 | 負責的檔案 | 說明 |
|---|---|---|
| 註冊全域快捷鍵 | `HotKeyManager.swift`、`ClipboardPasteGesture.swift` | Carbon hot key：錄音 `⌥↑`、iPhone 接力 `⌃⌥↑`、剪貼簿備用 `⌃⌥V`；QA 版另以事件 tap 接回按住 `⌘V` 再按方向鍵的歷史手勢 |
| 串起所有元件 | `main.swift`、`VoiceTypeController.swift` | `main.swift` 只建立 `NSApplication` 並交給 `VoiceTypeController`（`NSApplicationDelegate`）；啟動時建立各服務、請求權限、顯示首次引導 |
| 錄音狀態機 | `DictationCoordinator.swift` | 一次只管一段錄音；狀態 `idle → starting → recording → finalizing → transcribing → delivering`，失敗時進 `awaitingRetry` |
| 鎖定輸入目標 | `FocusTargetService.swift` | 記下當下前景 App、視窗與焦點元素的身分（不讀文字內容、不截圖） |
| 選麥克風 | `AudioInputPolicy.swift`、`AudioInputDevices.swift` | 沿用系統輸入，但排除 iPhone 連續互通麥克風；可固定電腦或外接麥克風 |
| 錄音 | `PinnedMicrophoneRecorder.swift` | 用 `AVCaptureSession` 指定裝置錄 16 kHz 單聲道 AAC；`AVAudioRecorder` 無法指定裝置，所以不用它 |
| 暫存檔 | `TemporaryRecordingStore.swift` | 錄音寫到 macOS 暫存目錄；啟動時清掉上次異常結束留下的檔案 |

`DictationCoordinator` 刻意不 import AppKit，也不碰金鑰；錄音器、辨識器和暫存都透過 protocol 注入，所以能在測試裡用假的元件跑完整個狀態機。

保護機制都在這一層：單段最長 300 秒；靜音自動停止（選用，3／5／10 秒）；辨識失敗時錄音保留 120 秒供重試。

### 2. 雲端辨識

| 步驟 | 負責的檔案 | 說明 |
|---|---|---|
| 讀金鑰 | `KeychainStore.swift` | App 專用的 Keychain 項目（service 以 Bundle ID 開頭，account `api-key`）；成功讀取後在本次執行期間快取 |
| 組請求與解析 | `GroqTranscriptionClient.swift` | `whisper-large-v3`，`POST https://api.groq.com/openai/v1/audio/transcriptions`；只 import Foundation，可單獨編譯測試 |
| 辨識流程轉接 | `GroqDictationTranscriber.swift` | 讀檔、帶入語言與詞典提示、處理取消 |
| 詞典提示 | `MacVocabularyStore.swift` | 啟用的詞條依提示額度組成 prompt；釘選的詞優先 |

錯誤時優先顯示 Groq 回傳的 `error.message`，取不到才顯示「Groq 回傳錯誤（HTTP 狀態碼）」。

### 3. 文字處理

| 步驟 | 負責的檔案 | 說明 |
|---|---|---|
| 招呼彩蛋 | `CatConfiguration.swift`、`CatOverlay.swift` | 在任何處理之前比對完整觸發句；命中就交給貓咪回覆，不輸出文字 |
| 語言閘門 | `LanguagePolicy.swift` | 檢查文字的 Unicode 腳本是否在允許範圍；不符合時用主要語言自動重試一次 |
| 後處理 | `TextPostProcessor.swift` | 純逐字／標準／簡潔三種模式；簡繁、標點、中英文空格、語助詞、數字轉換。只有固定規則，不呼叫任何模型 |

`TextPostProcessor` 有法律用語與詞彙保護表，例如「假扣押」「第159條」不會被拆開或改寫。修改這裡時，`scripts/test-text-pipeline.sh` 是最主要的回歸測試。

### 4. 輸出到輸入框

| 步驟 | 負責的檔案 | 說明 |
|---|---|---|
| 寫入剪貼簿並貼上 | `TextInsertionService.swift` | 先把文字寫進剪貼簿，再驗證目標，通過才送出 `⌘V` 鍵盤事件 |
| 驗證目標 | `FocusTargetService.swift` | 比對錄音開始時記下的 App、視窗與焦點元素；不一致就停在剪貼簿，不貼到別處 |
| 刪除暫存 | `DictationCoordinator.swift` | 文字成功寫進剪貼簿後立刻刪除錄音檔，即使自動貼上被拒絕 |

**本機錄音只會送出 `⌘V`，永遠不送 Enter。** 「貼上並送出」只存在於 iPhone 接力，而且要使用者在手機上明確按下、Mac 再驗證一次目標。這條規則是產品的安全底線，修改相關程式時要附上測試。

## 周邊功能

| 功能 | 檔案 | 資料停在哪裡 |
|---|---|---|
| 剪貼簿歷史 | `ClipboardHistoryMonitor.swift`、`ClipboardHistoryStore.swift`、`ClipboardPickerController.swift`、`ClipboardHistoryMenuController.swift` | 本機 `~/Library/Application Support/AI語音輸入/ClipboardHistory`，最多 10 筆、每筆 8 MiB |
| 修正學習 | `PasteCorrectionMonitor.swift`、`MacVocabularyCorrection.swift`、`VocabularyLearningStore.swift`、`VocabularyLearningToastController.swift`、`VocabularyToastPresentation.swift`、`VocabularyLearningBubbleView.swift` | 貼上後最多觀察兩分鐘；提示泡泡與選單裡的預覽共用同一套顯示流程，但預覽不會建立或刪除詞條；候選只存修正片段，存在 `UserDefaults` |
| 詞典管理 | `VocabularyWindowController.swift`、`MacVocabularyStore.swift` | `UserDefaults` 的 `smartVocabulary.entries.v1` |
| 錄音浮窗 | `NekoRecordingHUD.swift`、`NekoSignalMeter.swift` | 不搶焦點的面板；左眼取消、右眼完成；`cat.config.json` 指定圖片時改用該圖片 |
| 選單列 | `StatusMenuController.swift`、`NekoMenuBarIcon.swift` | 黑貓圖示與所有設定入口 |
| 設定 | `SettingsStore.swift`、`SettingsViews.swift` | `UserDefaults`（App 的 Bundle ID 網域），沿用既有 key 與遷移 |
| 桌面小黑貓 | `DesktopPetController.swift`、`DesktopPetModel.swift`、`DesktopPetView.swift`、`DesktopPetGroomingPalm.swift`、`DesktopPetLift.swift`、`DesktopPetDesktopReader.swift` | 只在記憶體讀桌面資料夾位置；不連網、不開麥克風。1.4.5 起只有貓咪輪廓接收滑鼠（點擊回應、抓起、放下），透明處穿透、不取得鍵盤焦點 |
| 貓咪外觀（毛色，`main` 上尚未發布） | `CatAppearance.swift`、`CatAppearanceArtwork.swift`、`CatAnatomy.swift` | `cat.config.json` version 2 的 `appearance`；只重新上色隨 App 打包的原圖，保留原本輪廓與透明度，使用者 PNG 不進這個繪製器 |
| 更新 | `AppUpdateController.swift`、`UpdateReminderPolicy.swift`、`UpdateDiagnostics.swift` | Sparkle 每日讀 GitHub 上的 appcast；由使用者決定安裝 |
| iPhone 接力（選用） | `MacRemoteBridge.swift`、`RemoteTargetController.swift`、`RemoteTargetValidationPolicy.swift`、`RemoteMessages.swift`、`VocabularySyncModels.swift` | 加密 Multipeer Connectivity；每次啟動預設關閉，協定版本 1 只支援文字接力 |
| 診斷 | `PasteDiagnostics.swift` | 只有明確開啟時才在本機寫入有大小上限的 JSON；欄位型別固定，不能記錄文字、剪貼內容、App 與視窗名稱、API Key 或路徑 |

## 修改時的界線

這些地方動到就會影響使用者的資料或安全，送 PR 前要特別說明並補測試：

- **App 身分**：Bundle ID（見 `Resources/Info.plist`）、Keychain service、`UserDefaults` key、安裝路徑 `~/Applications/AI語音輸入.app`。改了會讓既有使用者的金鑰、設定或更新失效。
- **送出規則**：`TextInsertionService` 只送 `⌘V`；`RemoteTargetController` 的「送出前再驗證一次」規則不要放寬。
- **資料去向**：任何新的網路請求、檔案寫入或記錄，都要同步更新 `PRIVACY.md`。
- **權限**：不要新增需要螢幕錄製或完整磁碟取用的功能；不要呼叫 `tccutil` 重設權限。
- **版本**：版本與 build 只在 `Resources/Info.plist` 修改，見 [UPDATES.md](UPDATES.md)。

## 建置產物

`scripts/build.sh` 用 `swiftc` 分別編譯 arm64 與 x86_64，再用 `lipo` 合成 Universal 2 執行檔，打包成 `build/AI語音輸入.app`（執行檔名 `FreeVoiceType`）。不使用 Xcode 專案，也不需要 Swift Package Manager。詳見 [DEVELOPMENT.md](DEVELOPMENT.md)。
