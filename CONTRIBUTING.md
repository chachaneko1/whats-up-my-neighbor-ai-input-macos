# 參與 What's up my neighbor

謝謝你願意幫忙。這個專案由一個人維護，回報問題、修正文件、送一個小修正都很有幫助。

這份指南說明三種參與方式：回報問題、修正文件、送程式修正。開始前可以先看 [開發環境與本機建置](docs/DEVELOPMENT.md) 和 [架構與資料流](docs/ARCHITECTURE.md)。

## 回報問題

到 [Issues](https://github.com/yuipan0611/whats-up-my-neighbor-ai-input-macos/issues) 開一個新的 Issue，盡量寫下：

- **環境**：macOS 版本、Mac 機型（Apple 晶片或 Intel），以及小黑貓選單顯示的 App 版本。
- **步驟**：從哪個 App、哪個輸入框開始，按了什麼。
- **預期與實際**：你以為會發生什麼，實際發生了什麼。
- **錯誤訊息原文**：可以截圖，但請先遮掉個人資訊。

請**不要**在 Issue、截圖或記錄檔裡貼出 Groq API Key。如果不小心貼了，立刻到 Groq Console 撤銷那把金鑰。

### 安全性問題

可能讓別人讀到資料、繞過貼上驗證或讓 App 送出非預期內容的問題，請不要開公開 Issue。改用 GitHub 的 private vulnerability reporting，詳見 [SECURITY.md](SECURITY.md)。

### 功能建議

歡迎提出。這個 App 刻意保持單純：只做語音轉文字、不做摘要或改寫、本機快捷鍵永遠不按 Enter。建議如果會改變這些原則，請在 Issue 裡說明使用情境，我們先討論再動手。

## 修正文件

錯字、步驟過時、說明和 App 畫面不一致，都可以直接送 PR：

1. Fork 這個 repo，在網頁上編輯對應的 Markdown 檔。
2. 在 PR 說明寫清楚改了什麼、為什麼（例如「1.4.4 的選單名稱已改成『剪貼簿歷史』」）。

文件以繁體中文為主。說明 App 行為的文字要和實際版本一致；不確定的地方寫「待確認」，比寫一個可能錯的說法好。

| 文件 | 內容 |
|---|---|
| `README.md` | 功能總覽、安裝、Groq 額度、設定 |
| `PRIVACY.md` | 資料傳輸與本機儲存的完整說明 |
| `CAT-CONFIG.md` | `cat.config.json` 格式 |
| `Packaging/使用說明.md` | 會放進安裝包給使用者看的說明 |
| `docs/` | 開發者文件 |

## 送程式修正

### 流程

1. 先開 Issue 或在既有 Issue 留言，說明你打算怎麼改。小的錯誤修正可以直接送 PR。
2. Fork 後從 `main` 開新分支，例如 `fix/clipboard-picker-escape`。
3. 修改程式，並補上或更新對應的測試（見 [TESTING.md](docs/TESTING.md)）。
4. 本機跑過相關測試，最好也跑一次 `./scripts/test-all.sh` 和 `./scripts/build.sh`。
5. 送 PR 到 `main`。CI 會建置並跑全部離線測試；PR 拿不到任何發布用的憑證。

### PR 說明請包含

- 改了什麼、為什麼。
- 實際跑過哪些測試，結果如何。
- 有沒有在真實 Mac 上手動試過；沒有的話也請寫出來，例如「只跑了離線測試，未實機錄音」。
- 會不會影響使用者資料、權限或網路請求。

### 需要特別小心的地方

這些改動會影響使用者的資料或安全，PR 需要說明理由並附測試：

- **送出規則**：本機錄音只送 `⌘V`，永遠不送 Enter；iPhone 接力的「貼上並送出」要在送出前再驗證一次目標。
- **App 身分**：Bundle ID、Keychain service、`UserDefaults` key 與安裝路徑。改了會讓既有使用者失去金鑰或設定，更新也可能失敗。
- **資料去向**：新增任何網路請求、檔案寫入或記錄時，同步更新 `PRIVACY.md`。
- **權限**：不新增螢幕錄製、完整磁碟取用等額外權限；不重設使用者的 TCC 權限。
- **相依套件**：目前只有 Sparkle，版本與 SHA-256 固定在 `scripts/fetch-sparkle.sh`。新增相依套件前請先在 Issue 討論。

### 版本與發布

一般 PR **不需要**改版本號。版本與 build 只在 `Resources/Info.plist` 修改，由維護者在發布時同時更新 `CHANGELOG.md` 和 `RELEASE_NOTES.md`；合併到 `main` 後由 GitHub Actions 自動簽章與發布。完整流程見 [UPDATES.md](docs/UPDATES.md)。

## 程式風格

- Swift 5，維持和周邊程式碼相同的命名與註解密度。
- 能只 import Foundation 的邏輯就放在 Foundation 層，AppKit 與系統呼叫留在外層，方便寫測試。
- 註解寫「為什麼」，不寫「做了什麼」。
- 使用者看得到的文字用繁體中文，簡短、說清楚會發生什麼事。

## 授權

送出的貢獻會以本專案的 [MIT License](LICENSE) 授權。
