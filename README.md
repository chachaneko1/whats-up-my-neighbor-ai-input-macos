# Groq AI 語音輸入 for macOS

一個輕量的原生 macOS 選單列語音輸入 App。按下自訂全域快捷鍵開始錄音，再按一次停止；音訊會送到 Groq `whisper-large-v3`，轉成繁體中文後貼到原本游標位置。

## 直接交給 AI 安裝

只要把這個 Repo 連結交給能操作 Mac 終端機的 AI，例如 Codex 或 Claude Code：

```text
https://github.com/yuipan0611/groq-ai-voice-input-macos
```

再貼上以下指令：

```text
請幫我安裝這個 GitHub Repo 的最新版 macOS App：
https://github.com/yuipan0611/groq-ai-voice-input-macos

請先閱讀 README、PRIVACY.md 與 Release 說明，再下載最新 Release 的 ZIP 和 .sha256，核對 SHA-256 後解壓縮並執行安裝工具。不要從原始碼或不明分支直接執行檔案，也不要移除或繞過 macOS quarantine；若 Gatekeeper 阻擋，請引導我使用右鍵「打開」或「系統設定 → 隱私權與安全性 → 仍要打開」。

安裝後請確認 AI 語音輸入正在執行、登入啟動項目存在，並告訴我如何允許麥克風與輔助使用權限。保留預設快捷鍵 Option + ↑，並告訴我可以從選單列的「設定快捷鍵…」自行更改。

絕對不要要求我把 Groq API Key 貼進聊天、終端機、程式碼或設定檔。請啟動 App，讓我只在 App 自己的安全輸入視窗中建立並儲存 Groq API Key。
```

AI 應該完成下載、校驗、解壓縮與安裝；使用者只需要親自處理 macOS 安全確認、麥克風／輔助使用權限，以及在 App 內輸入自己的 Groq API Key。

## 特色

- Swift、AppKit、AVFoundation 原生實作，不在本機常駐 Whisper 模型。
- 預設快捷鍵 `⌥↑`，可從選單列的「設定快捷鍵…」錄製任何包含修飾鍵的組合。
- 16 kHz、單聲道 AAC 錄音。
- 固定使用 Groq `whisper-large-v3`，以繁體中文、台灣字形與自然標點為提示。
- Groq API Key 只儲存在 macOS 鑰匙圈。
- 轉錄文字先進入剪貼簿；有輔助使用權限時自動模擬 `⌘V`。
- 沒有輔助使用權限時仍保留剪貼簿文字，不會遺失。
- 暫存錄音在辨識完成後刪除。
- 登入後自動啟動，並提供完整移除工具。
- 不使用 ChatGPT、OpenAI API 或其他聊天模型，也不會自動送出訊息。

## 系統需求

- macOS 13 Ventura 或更新版本。
- Groq 帳號與自己的 API Key。
- 網路連線、麥克風權限及輔助使用權限。

## 下載與安裝

1. 到 GitHub 的 **Releases** 下載最新 ZIP，解壓縮。
2. 因為免費版沒有 Apple Developer ID 公證，第一次請對 `安裝.command` 按右鍵並選「打開」。
3. 若 macOS 仍阻擋，前往「系統設定 → 隱私權與安全性」，找到提示並按「仍要打開」。
4. 安裝完成後，App 會出現在選單列。
5. 依首次啟動畫面取得並貼上自己的 Groq API Key。
6. 允許「麥克風」與「輔助使用」權限。
7. 在任何文字欄位按 `⌥↑` 開始錄音，再按一次停止。

> 請勿使用別人的 Groq API Key。每位使用者應建立自己的 Key，額度與帳務也各自分開。

## 建立 Groq API Key

首次啟動畫面可直接開啟 [Groq API Keys](https://console.groq.com/keys)：

1. 登入或建立 Groq 帳號。
2. 按 `Create API Key`。
3. 複製以 `gsk_` 開頭的金鑰。
4. 回到 App 貼上並按「安全儲存」。

App 不會把 Key 寫入設定檔、Repo 或日誌，只會保存在這台 Mac 的鑰匙圈。之後可從選單列選「設定／更換 Groq API 金鑰…」。

## Groq 免費方案限制 / Groq Free Tier Limits

本專案固定使用 Groq `whisper-large-v3` 進行語音轉文字。以下是截至 **2026-07-15**，[Groq 官方 Rate Limits](https://console.groq.com/docs/rate-limits) 公開的 Free Plan 限制：

| 限制 | 數值 |
|---|---:|
| 每分鐘請求數（RPM） | 20 |
| 每日請求數（RPD） | 2,000 |
| 每小時音訊秒數（ASH） | 7,200 秒（2 小時） |
| 每日音訊秒數（ASD） | 28,800 秒（8 小時） |

### 這對日常使用代表什麼？

一般語音輸入通常每段只有 5–30 秒，因此很難碰到上述限制。例如每天使用 200 次、每次錄音 10 秒：

- 總音訊量為 2,000 秒，約 33 分鐘。
- 只使用約 **7%** 的每日免費音訊額度。
- 200 次請求也只使用每日 2,000 次請求上限的 10%。

非常適合語音打字、程式開發口述、ChatGPT 提示詞輸入、短篇會議筆記及一般生產力工作。較可能超過限制的情境包括：轉錄數小時的會議、處理長篇影片、批次轉錄大量音訊檔，或持續不中斷地錄音。

> [!NOTE]
> Groq 目前公開的是 RPM、RPD、ASH、ASD 等速率限制，官方並未另外公布固定的「每月免費 X 小時」轉錄配額。這不代表免費方案永久無限量；Groq 可能調整限制，而且不同帳號可能有例外。請以 [Groq Console](https://console.groq.com/) 中自己帳號顯示的最新 Limits 為準。

> [!WARNING]
> 到達任何一項限制後，Groq API 會回傳 `429 Too Many Requests`，App 在限制重置前將無法完成轉錄。請勿透過多帳號或其他方式規避免費方案限制。

### English

This project uses Groq `whisper-large-v3` for speech-to-text. As of **2026-07-15**, the public [Groq Rate Limits](https://console.groq.com/docs/rate-limits) list the following Free Plan limits:

| Limit | Value |
|---|---:|
| Requests per minute (RPM) | 20 |
| Requests per day (RPD) | 2,000 |
| Audio seconds per hour (ASH) | 7,200 seconds (2 hours) |
| Audio seconds per day (ASD) | 28,800 seconds (8 hours) |

For normal voice dictation, recordings are usually only 5–30 seconds long, so these limits are unlikely to be reached. For example, 200 ten-second recordings per day use 2,000 audio seconds (about 33 minutes), approximately **7%** of the daily audio allowance and 10% of the daily request allowance.

This is well suited to voice typing, coding dictation, ChatGPT prompt input, short meeting notes, and everyday productivity. You are more likely to exceed the limits when transcribing multi-hour meetings, long videos, large batches of audio files, or continuous recordings.

> [!NOTE]
> Groq currently publishes rate limits such as RPM, RPD, ASH, and ASD; it does not separately publish a fixed “X free transcription hours per month” quota. This does not mean the Free Plan is permanently unlimited. Limits may change, and exceptions may apply to individual accounts. Always check the latest Limits shown for your account in the [Groq Console](https://console.groq.com/).

> [!WARNING]
> When any applicable limit is reached, the Groq API returns `429 Too Many Requests`, and the app cannot complete transcription until the limit resets. Do not use multiple accounts or other methods to circumvent Free Plan limits.

## 自訂快捷鍵

1. 點選單列的麥克風圖示。
2. 選「設定快捷鍵…」。
3. 在錄製區按下想要的組合，例如 `⌥↑`、`⌃Space` 或 `⇧⌘D`。
4. 按「儲存」。

快捷鍵至少要包含一個修飾鍵。若組合已被其他 App 使用，AI 語音輸入會保留原本設定。

## 隱私與資料

- 錄音只為轉錄而傳到 Groq Speech-to-Text API。
- App 不包含分析、廣告或自有後端。
- Groq API Key 儲存在 Keychain。
- 轉錄歷史不會由 App 保存；最後結果會放入系統剪貼簿。
- 詳細內容見 [PRIVACY.md](PRIVACY.md)。

## 從原始碼建置

需要安裝 Xcode Command Line Tools：

```bash
./scripts/build.sh
```

輸出位於 `build/AI語音輸入.app`。建立可分享 ZIP：

```bash
./scripts/package-release.sh
```

## 免費簽章限制

Release 使用 ad-hoc 簽章與固定 Bundle ID，沒有 Apple Developer ID 公證。macOS 第一次開啟時會顯示安全確認；這不等於程式通過 Apple 審查。正式無警告分發需要 Apple Developer ID 簽署及 notarization。

## 移除

執行 Release 裡的 `移除.command`，會停止 App、移除登入啟動設定、App 本體與其 Keychain API Key。

## 授權

[MIT License](LICENSE)
