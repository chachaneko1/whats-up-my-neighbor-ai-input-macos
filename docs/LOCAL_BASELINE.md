# 本機未提交內容與主分支盤點

盤點日期：2026-10-14。本輪從主分支另開隔離 worktree 重構，不覆蓋原本的本機工作目錄（下稱 original local checkout），不重設其 index、檔案或分支。

## 三份狀態分開判讀

| 狀態 | 盤點結果 |
|---|---|
| Original local checkout 分支 | `agent/merge-local-remote-features` |
| Original local checkout HEAD | `39f47ea153b9acf8ece53c72caf41dd5337f1985` |
| 本輪主分支基線 | `ee0467724d80f3738ad386f72a2b008decaacd86` |
| 原 HEAD 與基線距離 | ahead 0、behind 9 |
| 原工作目錄狀態 | 20 個路徑；14 staged、11 unstaged、6 untracked，分類重疊 |

本機 HEAD 較舊，因此 `git diff main` 中看似刪除的檔案，有些只是原本尚未合併較新主分支，不能當成使用者刻意刪除。staged 和 unstaged 也包含不同時間的工作，不能整棵覆蓋主分支或把所有 staged 新增視為新功能。

## 已進主分支的部分

以下 original local checkout 的 **index blob 與本輪 main 基線完全相同**：

- `Sources/GroqVoiceInput/RemoteMessages.swift`
- `Sources/GroqVoiceInput/RemoteTargetController.swift`
- `Sources/GroqVoiceInput/RemoteTargetValidationPolicy.swift`
- `Tests/RemoteProtocolTests.swift`
- `Resources/Info.plist`

這些 staged 遠端貼上、目標驗證、協定測試與權限宣告已在主分支。除 `RemoteTargetValidationPolicy.swift` 外，其餘檔案又有更後期的 unstaged 修改，須另行分類。

## 僅在原本本機工作的功能

| 類別 | 檔案與差異 |
|---|---|
| 詞典與同步 | untracked `MacVocabularyStore.swift`、`VocabularySyncModels.swift`、`VocabularyWindowController.swift` |
| 貼上後修正 | untracked `MacVocabularyCorrection.swift`、`PasteCorrectionMonitor.swift` |
| 協定 | `RemoteMessages.swift` 由 v1 改為 v2，加入 `vocabularySync`、`vocabularySyncAck` 與詞典 payload |
| 功能整合 | `main.swift` 的詞典選單、提示詞、管理介面、確認與同步；`MacRemoteBridge.swift` 的連線狀態回呼與 paired-peer 篩選；`RemoteTargetController.swift` 的純貼上回呼 |
| 測試 | `RemoteProtocolTests.swift` 新增詞典合併、儲存、修正與範圍策略；測試腳本加入對 sibling iOS 詞典模型的比對 |
| 版本 | 工作目錄 `1.3.0 (5)`，主分支 `1.1.0 (3)` |
| 簽章 | 本機 `scripts/build.sh` 可指定 `MAC_CODESIGN_IDENTITY`，或自動選 Apple Development 身分；主分支保留原 ad-hoc 策略 |
| 文件 | 本機 `PRODUCT_SPEC.md`、untracked `plan.md`、README／PRIVACY 詞典增補、`.codex/` ignore 規則 |

以上是需保全的整合候選；**第一批重構沒有將本機詞典、協定 v2、版本號或 Apple Development 簽章移植進來**。原檔與 staged／unstaged 分層仍留在 original local checkout，不能將此隔離分支當作它們已整合完成的交付。

## 較新主分支的能力

主分支新增 `AudioInputDevices`、`AudioInputPolicy`、`PinnedMicrophoneRecorder`、`GroqTranscriptionClient`、`LanguagePolicy`、`TextPostProcessor` 與對應的四套測試。它也已有 Keychain 程序內快取、文字模式、語言限制／重試、指定麥克風與明確開啟的 iPhone 接力模式。

本機舊 `MacRemoteBridge` 使用常駐 session，初始化後會開始廣播。主分支則要求明確開啟接力模式，關閉時拒絕新的邀請、停止廣播並中斷 session。若直接用本機整檔替換，會回退這些保護與語音功能。

## 後續合併容易衝突的位置

- `main.swift`：本機詞典流程與主分支麥克風、重試、設定功能同時修改控制器。
- `MacRemoteBridge.swift`：本機同步回呼／paired-peer 篩選須與主分支 relay lifecycle 合併。
- `RemoteMessages.swift`、`RemoteTargetController.swift`、`RemoteProtocolTests.swift`：協定版本與訊息分流不同。
- `scripts/build.sh`、`Resources/Info.plist`：簽章、CoreAudio framework 與版本不同。
- `scripts/test-remote-protocol.sh`：本機 v2 模型依賴與主分支 v1 測試不同。
- README、PRIVACY、`PRODUCT_SPEC.md`、`plan.md`：需對照實際功能，不能以舊文件覆蓋新行為。

## 保留規則與未驗證邊界

1. 原工作目錄、index 與 untracked 檔案不變；重構從 main 基線在新分支進行。
2. 保留 `tw.panh.FreeVoiceType`、Keychain service/account、所有既有 UserDefaults keys、安裝位置與 LaunchAgent 身分。
3. 保留主分支的指定麥克風、三種文字模式、語言選擇、有限重試與 relay 預設關閉。Keychain 與 Groq 行為不因拆檔增加供應商、模型或請求。
4. 本機永不送 Enter；遠端送出僅接受明確 action，並重新驗證 App、視窗、元素、session 與期限。
5. 未來詞典移植須保留 `smartVocabulary.entries.v1`、穩定 UUID、counter/deviceID revision、刪除墓碑及決定性合併；僅同步已確認詞條及管理欄位。
6. 本機詞典容量為 200 詞、每詞最多 40 字；提示詞上限 200 UTF-8 bytes。貼上後監看規格限同一元素內的精確貼入範圍、最長 120 秒；排除安全欄位與 pasteAndSubmit。
7. v2 契約仍需與 sibling iOS 同步驗證，不應只移植 Mac 端訊息格式。
8. 自動測試與編譯不等同實機完成；麥克風、Accessibility、焦點切換、iPhone 配對與詞典辨識效果須另有直接證據。

本機 `PRODUCT_SPEC.md` 有段落將同步標為已實作，後段仍標 M3 `PLANNED`；`plan.md` 也保留舊安全待辦。該紀錄可供追溯，但不表示問題仍完整存在或已完整修復。例如本機 `send()` 已篩選 paired peers，完整重新配對／多 peer 情境仍待驗證。新文件應標註此差異，不能將歷史驗證當成本輪結果。

本輪的修改範圍與驗證方法見 [REFACTOR_PLAN.md](REFACTOR_PLAN.md)。
