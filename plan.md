# Groq AI 語音輸入：執行計畫

更新日期：2026-08-08

本文件只追蹤目前工作順序、驗證證據與未完成項目。產品需求、安全約束與功能邊界以 [`PRODUCT_SPEC.md`](PRODUCT_SPEC.md) 為準；兩份文件衝突時，以 `PRODUCT_SPEC.md` 為準。

## 1. 目前目標

先完成 Mac 貼上後修正建議的最終安裝，再把已完成詞典同步的 iPhone `0.6.0 (6)` 安裝到實機並做雙向同步回歸。

目前只供自己使用，因此已知安全問題先保留在待辦；但在把軟體公開推送、分享給朋友或進入 TestFlight 前，必須完成安全修補與必要真機測試。

## 2. 狀態快照

| 工作流 | 目前狀態 | 已有證據 | 尚缺 |
|---|---|---|---|
| Mac 本機語音輸入 | `IMPLEMENTED / UI VERIFIED` | 協定測試、建置、Apple Development 簽章、Accessibility 保留與 TextEdit 修正建議流程通過 | 麥克風與本機快捷鍵完整人工回歸 |
| iPhone 舊有錄音與遠端功能 | `IMPLEMENTED / PARTIALLY VERIFIED` | 原始碼存在，首次 Mac 配對曾完成 | 完整遠端安全情境與目前版本實機回歸 |
| M1 智慧常用詞典 | `IMPLEMENTED LOCALLY` | 14 個核心測試通過，iPhone 模擬器建置通過 | 目前 iPhone 的 10 組流程與 20 詞辨識比較 |
| M3 Mac／iPhone 詞典同步 | `IMPLEMENTED / AUTOMATED VERIFIED` | 協定 v2、穩定 ID、墓碑、決定性合併、雙端儲存與 Mac 管理介面完成 | iPhone `0.6.0 (6)` 實機安裝與雙向同步回歸 |
| 安全審查 | `REVIEW COMPLETE / FIXES DEFERRED` | staged Mac diff 已完成正式安全審查 | 3 個問題修補、4 類真機／傳輸驗證 |
| GitHub 公開版 | `NOT READY` | Mac staged diff 未發現 API Key 或明顯私人機器值 | 乾淨 iPhone Repo、私人設定排除、安全門檻、commit 與 push |

## 3. P0 — 現在：完成 M1 智慧詞典

### 3.1 已完成

- [x] 詞典資料模型與本機儲存。
- [x] 修改前後差異提取。
- [x] 一輪編輯只詢問一次。
- [x] 使用者明確同意才加入。
- [x] 新增、搜尋、編輯、啟用／停用、釘選、刪除與清空。
- [x] Prompt Builder、200 UTF-8 bytes 保守上限與優先順序。
- [x] 14 個核心測試通過，0 failures。
- [x] iPhone 模擬器完整建置成功。
- [x] Mac 詞典管理與雙向同步。
- [x] Mac 只監看 Groq 剛貼入範圍，並排除安全輸入框與「貼上並送出」。
- [x] Mac `Gork → Groq` TextEdit 流程跳出一次可編輯確認框。

### 3.2 尚未完成

- [x] 選定第一批 20 個測試詞，包含品牌、人名、法律與技術詞；測試句與結果表見 `../groq-ai-voice-input-ios/DEVICE_VALIDATION_0.4.0.md`。
- [x] 將含 M1 的 `0.4.0 (5)` 版本簽章建置並安裝到目前這支 iPhone；裝置已讀回相同版本，並透過 iPhone 鏡像完成開發者信任與啟動。
- [ ] 實機完成至少 10 組「加入／這次不要」流程。
- [ ] 對至少 20 個指定詞記錄加入詞典前後的辨識結果。
- [ ] 確認純標點、空白修改不會詢問。
- [ ] 確認不加入時完全不保存。
- [ ] 確認詞典錯誤不阻擋複製、分享或傳送到 Mac。
- [ ] 確認重新錄音、取消與完成後不保留完整逐字稿。
- [ ] 把實機結果與失敗案例回寫到本文件及 `PRODUCT_SPEC.md`。

### 3.3 M1 完成門檻

只有同時符合下列條件，才可把 M1 標成 `VERIFIED`：

1. 14 個自動化測試仍為 0 failures。
2. iPhone 模擬器建置成功。
3. 10 組實機加入／拒絕流程完成。
4. 20 個指定詞有加入前後紀錄。
5. 複製、分享與遠端 Mac 功能沒有回歸。

## 4. P1 — 詞典驗證後：遠端可靠性與安全

這一階段目前是 `DEFERRED UNTIL M1 VALIDATION`，不阻擋自己使用詞典，但會阻擋公開分享。

### 4.1 已確認但尚未修補

- [ ] P2：五分鐘配對期間沒有錯誤次數上限、冷卻或鎖定。
- [ ] P3：更換配對裝置後，回應可能仍廣播給舊的已連線 peer。
- [ ] P3：遠端「貼上並送出」前沒有把授權文字重新綁定到可變的系統剪貼簿內容。

### 4.2 尚未完成的真機情境

- [ ] 背面點三下開啟並立即錄音。
- [ ] iPhone 顯示正確的 Mac App、視窗與輸入目標。
- [ ] 「只貼上」永遠不按 Enter。
- [ ] 「貼上並送出」只執行一次。
- [ ] Mac 焦點改變時拒絕命令。
- [ ] Accessibility 關閉時保留剪貼簿並回報失敗。
- [ ] 睡眠、鎖定與連線中斷時安全失敗。
- [ ] Mac 本機 `Option + ↑` 仍只貼上。

### 4.3 安全審查留下的證據缺口

- [ ] 量測五分鐘內 Multipeer pairing invitation 的可達次數與大小。
- [ ] 驗證獨立裝置是否能重用已配對的 `MCPeerID`。
- [ ] 用三台 peer 驗證更換配對後的實際回應收件者。
- [ ] 在受控 Mac 帳號重現或排除剪貼簿與焦點競態。

## 5. P2 — 後續產品工作

開始以下項目前，必須先完成 M1 驗證；實際順序再由使用者確認。

- [ ] COR-1：同一音訊重新辨識原型、額度提示與音檔生命週期。
- [ ] M2：多處修改集中審核、品質統計與 200 筆效能測試。
- [ ] M1.5：主要／備用 Groq Key；只在 `401/403` 明確確認後重試一次。
- [ ] COR-2：先驗證 ASR 是否真的提供 N-best、時間資訊與信心度。
- [x] M3（必做）：Mac 與 iPhone 雙向同步已確認詞彙及啟用／釘選等管理狀態。
  - [x] 定義跨裝置穩定 ID、重複詞合併、刪除墓碑與決定性衝突規則。
  - [x] 擴充並同步兩端 `RemoteMessages.swift`，加入版本化同步訊息與協定測試。
  - [x] 建立 Mac 詞典儲存與管理入口，並讓 Mac Prompt 使用同步後的啟用詞。
  - [ ] 實機驗證離線各自修改、重新連線收斂、未配對拒絕及版本不相容。
  - [x] 確認封包模型不含 API Key、錄音、完整逐字稿或來源 App。
- [ ] COR-3：選取範圍後語音替換與復原。
- [ ] COR-4：串流辨識與主動候選，保留非串流 fallback。
- [ ] M4：Apple Developer Program 與 TestFlight。
- [ ] M5：Developer ID、公證、App Store／公開維護。

### 5.1 M6 — 未來多人會議 Web 微型服務

狀態：`ROADMAP ONLY / NOT STARTED`

這個方向已列入正式 Roadmap，但目前不取代 M1 實機驗證、安全修補、公開版門檻與原生 App 產品化工作，也尚未授權開始建立後端或部署服務。

- [ ] 建立獨立的 Web 微型服務 PRD、架構與成本模型。
- [ ] 準備 10–20 段已取得同意的繁中多人測試音檔與人工參考標註。
- [ ] 分開測試 ASR 文字正確率與 `pyannote.audio` 等工具的說話者分段品質。
- [ ] 比較至少兩種供應商／模型組合的品質、延遲、費用、部署與隱私風險。
- [ ] 定義 Upload-first MVP：上傳、說話者 A／B／C、時間戳播放、修改、重新命名、匯出及立即刪除。
- [ ] 定義保存期限、存取權限、加密、使用者同意與刪除政策；第一版不建立跨會議真人聲紋身分庫。
- [ ] 確認服務應獨立 Repo／部署，不把 Python／PyTorch 說話者模型塞進目前的輕量 Mac／iPhone 日常輸入流程。

進入條件：由使用者另行確認開始 Phase 0；在此之前只保留文件，不寫服務程式、不建立雲端資源、不產生費用。

## 6. GitHub 公開版門檻

目前不要直接把整個本機 iPhone 資料夾推上 GitHub。`../groq-ai-voice-input-ios/` 目前不是 Git Repo，而且包含機器本地設定與 Xcode 使用者資料。

公開前必須：

- [ ] 建立乾淨的 iPhone Repo 或乾淨輸出目錄。
- [ ] 排除 `Config/Local.xcconfig`、私人簽章設定、`xcuserdata`、`.build`、DerivedData 與本機產物。
- [ ] 不讀取、不複製、不提交任何已存在的 API Key。
- [ ] 檢查 Mac 與 iPhone 的 `.gitignore`、README、PRIVACY、SECURITY 與 LICENSE。
- [ ] 完成 P1 已確認安全問題的修補或明確公開風險決策。
- [ ] 再做 secrets／私人路徑掃描。
- [ ] 產生乾淨 diff，經使用者確認後才 commit 與 push。

目前 Git 狀態：

- Mac 合併版：本機已有 staged changes，尚未 commit、尚未 push。
- iPhone 版：本機專案存在，但尚未建立乾淨的 Git 版本。

## 7. 2026-07-27 驗證紀錄

| 檢查 | 結果 |
|---|---|
| `./scripts/test-remote-protocol.sh` | 通過 |
| `./scripts/build.sh` | 通過 |
| Mac `codesign --verify --deep --strict` | 通過 |
| Mac Accessibility 與事件送出權限 | 通過；相同 Apple Development 簽章更新後仍保留 |
| Mac 修正建議 TextEdit 流程 | `Gork → Groq` 後顯示一次「加入常用詞典？」；建議欄為 `Groq` |
| Mac 修正提取與範圍策略測試 | 通過；含完整英文詞、純標點、純刪除與範圍外輸入 |
| iPhone 0.6.0 簽章建置 | `BUILD SUCCEEDED`；實機安裝待完成 |
| iPhone `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test` | 14 tests，0 failures |
| iPhone 模擬器完整 Xcode build | `BUILD SUCCEEDED` |
| iPhone 0.4.0 實機測試表 | 已建立 20 詞加入前後比較與 10 組加入／拒絕流程 |
| iPhone 0.4.0 實機簽章建置與安裝 | `BUILD SUCCEEDED`；嚴格簽章驗證通過；裝置讀回 `0.4.0 (5)` |
| iPhone 0.4.0 啟動 | 已透過 iPhone 鏡像完成開發者信任並正常啟動 |
| iPhone 0.4.0 M1 介面 | 「常用詞典」入口、空狀態與新增按鈕正常顯示 |
| iPhone 鏡像錄音限制 | 已確認鏡像控制期間無法使用 iPhone 麥克風；真實辨識必須在實體 iPhone 上操作 |

這台 Mac 的全域 `xcode-select` 目前指向 Command Line Tools；直接執行 `swift test` 會找不到 `XCTest`。本次沒有修改全域設定，而是只在驗證命令中指定已安裝的 `/Applications/Xcode.app`。

## 8. 下一次接手時的第一步

1. 先讀 `PRODUCT_SPEC.md` 與本文件。
2. 確認 Mac 最終版不含測試鉤子，完成建置、簽章與安裝。
3. 將 iPhone `0.6.0 (6)` 安裝到目前裝置，回歸新增、修改、停用、釘選與刪除的雙向同步。
4. 再逐項記錄 10 組流程與 20 詞加入前後結果；不要把建置成功誤寫成完整實機驗證。
