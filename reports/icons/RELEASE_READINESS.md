# 圓臉圖示套用與發布前確認

核對日期：2026-10-20（台北）。本次只在本機隔離工作區修改、建置與檢查；沒有開啟新 App、替換現用 App、安裝、推送、合併、建立 PR／tag／Release，或修改公開更新清單。

## 套用內容

- 沿用使用者核准的專案原稿 `Resources/DesktopPet/walk-front-face.svg`，保留原有臉型、左 X、右勾與 ω 嘴，不再加圓。
- App 圖示沿用已保留的白底版本；16–1024 px、外側透明邊距、底板純白；與先前白底版本的 PNG、ICNS 完全相同。
- 選單列的一般狀態與核准原稿幾何一致；24 × 18 pt、固定黑貓、透明五官。錄音、處理中、重試及遠端模式的狀態符號繼續保留。
- 每次建置會從原稿重新產生白底 App 圖示，避免建置再帶入舊的灰底 ICNS。
- 錄音 HUD 的長臉素材 `Resources/neko-base.png`、桌面貓動畫、Bundle ID、版本／build、更新設定與金鑰均不改動。

## 工作區與來源

| 用途 | 隔離工作區／分支 | 精確基準 |
| --- | --- | --- |
| 正式 Mac App 與選單列 | `worktrees/neighbor-approved-cat-icons`／`codex/approved-cat-icons` | `bdf8bd6c42372c588f468dc859d7fc8e68303e71`，本次即時核對與遠端 main 相同 |
| VPS 遠端分身預覽 App | `worktrees/neighbor-remote-approved-cat-icons`／`codex/remote-approved-cat-icons` | `a91b33c1114c05ef2730f129dfb972993d4ea284` |

原 `neighbor-round-logo` 分支仍是舊的 1.4.4／1011，與最新 main 相比缺少後來功能。此次只取用它的核准白底圖示產生方式，沒有合併整條舊分支。原 `neighbor-remote-agent` 中其他 AI 尚未提交的 VPS／Docker 相關工作也未改動、未攜入本次隔離版本。

## 本次即時核對到的發布現況

- [公開最新版](https://github.com/yuipan0611/whats-up-my-neighbor-ai-input-macos/releases/tag/v1.4.5) 是 **1.4.5／1012**，正式、非預發行；發行時間為 2026-10-19 10:55（台北）。本次沒有提高版本號。
- 公開版有 app-only 更新 ZIP、首次安裝 ZIP、兩份校驗清單與 appcast。**目前該公開版沒有 `install.sh`**；最新 main 的包裝腳本已會產生它，下一版發布時須確認真的上傳且可下載。
- 最新 main 的 [Build](https://github.com/yuipan0611/whats-up-my-neighbor-ai-input-macos/actions/runs/39383039148) 與 [Release macOS](https://github.com/yuipan0611/whats-up-my-neighbor-ai-input-macos/actions/runs/39383038802) 成功。這是 main 基準的 CI，**不代表本次尚未推送的修改已通過雲端 CI**。
- Repository 層級已設定三個發布 Secret 名稱（固定簽章 p12／密碼、Sparkle 私鑰）及固定憑證指紋 Variable；本次只查名稱，未讀取或匯出密值。憑證是否仍有效、是否與私鑰相符，要在授權的正式簽署階段驗證。

## 發布前需要完成

### 1. 先確定發布範圍與觸發時間

- [ ] 只整合本次圖示變更到最新 main；不要用舊圓臉分支覆蓋近期功能。
- [ ] 把實驗用 VPS 預覽與正式 App 分開；本次沒有重做真實 VPS、供應商登入、遠端桌面完整流程驗收，不得把換圖示描述為 VPS 功能正式完成。
- [ ] 在要發布時才提高 `Resources/Info.plist` 的版本和 build；兩者都必須大於已公開版本。若沒有其他版本先行發布，候選可為 **1.4.6／1013**，目前尚未設定。
- [ ] 同步 `RELEASE_NOTES.md`、`CHANGELOG.md`，說清楚圖示與同次實際包含的其他變更。
- [ ] **注意自動觸發**：`.github/workflows/release-macos.yml` 會在 main 收到 `Resources/Info.plist`、`RELEASE_NOTES.md` 或該發布 workflow 變更時執行；也接受 `v*` tag／手動指定 tag。不要在尚未準備發布時合併已提高版本的變更。本次三個觸發檔案都沒改。

### 2. 在最終版本跑 CI 與實機檢查

- [ ] 最終不可變 commit 的離線測試與 arm64／x86_64 建置通過。不要把這次本機建置簽章當正式發布簽章。
- [ ] 在獲准啟動／安裝後確認 Dock、Finder、更新視窗與 VPS 預覽 App 的白底；確認一般、錄音、處理中、重試、遠端模式五種選單列圖示在實際選單列可辨識。
- [ ] 確認 macOS 圖示快取更新；顯示舊圖示時先比對 bundle 內 ICNS，不為了刷快取改 Bundle ID、重設 TCC 或刪除使用者設定。
- [ ] 確認語音輸入、貼上、桌面貓、快捷鍵、麥克風與輔助使用授權保持原行為。原生離線渲染不能取代上述實機驗收。

### 3. 簽章與新使用者首次開啟

- [ ] 沿用現有正式簽章身分、Bundle ID 與 designated requirement；驗證憑證未到期、指紋一致、strict code signature 成功，Sparkle 內嵌 helpers 的簽章完整。
- [ ] **目前專案刻意沿用非公證發布流程**，沒有 Apple notarization／Hardened Runtime 步驟。這是既有分發限制，圖示修正不會改善它；本機 ad-hoc 建置也不能證明首次下載能順利開啟。
- [ ] 若要提供 Developer ID＋Apple 公證的分發體驗，另行規劃憑證與更新相容性，不能在這次圖示修改中直接換簽章。若沿用現有路線，需在乾淨使用者環境以實際瀏覽器下載包驗證 Gatekeeper 與首次開啟流程，不能宣稱沒有安全提示。

Apple 官方說明指出 Developer ID 用於讓 Gatekeeper 驗證站外分發的開發者身分；公證會進行掃描並提供驗證票證。來源：[Developer ID](https://developer.apple.com/developer-id/)、[Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

### 4. 發布包與更新清單

- [ ] 用正式固定憑證簽署；維持既有 Sparkle Ed25519 金鑰，不改公鑰／重新生一組替代。
- [ ] 以保留 symlink 的方式產生 app-only 更新 ZIP 與首次安裝 ZIP，再產生 SHA-256、簽署 appcast；本專案也要求清單簽章。
- [ ] Draft Release 先上傳全部資產：更新 ZIP、appcast、更新 ZIP 校驗清單、首次安裝 ZIP 與校驗檔、`install.sh`、更新紀錄；全部通過後才標記正式 latest。
- [ ] 從公開下載位置重新取得所有成品，驗證雜湊、Ed25519、Bundle ID、簽章、版本／build、ICNS 與白底；`install.sh` 必須固定本次 ZIP 的正確 SHA-256。
- [ ] 已公開 1.4.5 的成品不覆寫；錯誤應以更高版本修正。只有 Mac 正式 Release 可佔用目前這個 updater 的 latest。

Sparkle 官方要求簽署更新、保留封裝 symlink，並以內部 build 區分版本。來源：[Publishing an update](https://sparkle-project.org/documentation/publishing/)。

### 5. 保留資料與回復

- [ ] 保留原安裝位置、登入啟動設定、Keychain、UserDefaults、快捷鍵、外部 `cat.config.json` 與自訂圖片；不能先移除再升級。
- [ ] 更新只通知，由使用者選擇是否安裝；錄音／辨識中不強制重新啟動。
- [ ] 在獲准安裝時保存舊 App 備份並檢查設定指紋；回復與下一版修正方案要可追溯。

## 本次驗證結果

完整結果記錄於同目錄 `VERIFICATION.md`。仍未執行安裝、真實 Dock／選單列驗收、正式憑證簽署、公證或公開更新驗證；上述未勾項保留為發布階段事項。
