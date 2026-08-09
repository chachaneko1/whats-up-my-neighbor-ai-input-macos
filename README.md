# Groq AI 語音輸入 for macOS

一個輕量的原生 macOS 選單列語音輸入 App。按下自訂全域快捷鍵開始錄音，再按一次停止；音訊會送到 Groq `whisper-large-v3`，轉成繁體中文後貼到原本游標位置。也可與配套 iPhone App 在附近直接連線，從手機修改轉錄文字並明確選擇「只貼上」或「貼上並送出」。

## 非工程師技術教學

想了解原本 Mac 功能、新增的 iPhone／遠端功能、附近裝置配對，以及為什麼不會隨便按 Enter，請閱讀 [Groq AI 語音輸入：給非工程師看的技術教學](../../TECHNICAL_GUIDE_FOR_BEGINNERS.md)。

## 文字輸出模式

從選單列的「文字輸出模式」可以切換三種模式，預設是純逐字：

| 模式 | 會做什麼 | 適合 |
|---|---|---|
| 純逐字（預設） | 只修格式：簡體轉繁體、標點正規化、中英文之間補空格 | 逐字紀錄、訪談、會議、法律內容 |
| 標準 | 純逐字的全部，再移除句首「呃、嗯」與明顯重複詞 | 一般筆記 |
| 簡潔 | 標準的全部，再移除句尾語氣詞（啊、啦、喔） | 傳訊息 |

同一句話的差別：

```text
輸入：嗯，好啊，那個報告我明天再給你喔
純逐字：嗯，好啊，那個報告我明天再給你喔
標準：  好啊，那個報告我明天再給你喔
簡潔：  好，那個報告我明天再給你
```

> 簡潔模式會改變語氣（「好啊」→「好」），傳訊息時可能顯得比較冷淡，所以它不是預設，要自己開。

三種模式都**不會**摘要、不會改寫成 Email、不會自動條列、不會重組句子。所有處理都是本機的固定規則，不使用任何聊天或改寫模型，也不額外連網。

法律用語（假扣押、證據能力、不起訴處分、強制執行法等）在三種模式下都不會被改寫；「第159條」「新台幣50萬元」也不會被拆開加空格。詞彙保護表確保「我們去酒吧」不會被切成「我們去酒」。

## 語言設定與保護

從選單列的「語言設定…」可以設定最多三種語言：一個主要語言，加上最多兩個允許混用的語言。預設是繁體中文＋英文。

主要語言會同時決定辨識語言、提示字串，以及是否套用中文專屬的後處理——選日文時不會做簡繁轉換，避免破壞日文漢字。

> 語言檢查看的是文字系統，不是語言本身。英文、西班牙文、越南文都寫成拉丁字母，無法互相區分。

轉錄結果如果大量出現允許範圍以外的文字——例如音訊過短或沒有出聲時模型憑空產生的泰文——App 不會直接貼出來，而是保留錄音、指定主要語言自動重試一次；仍然失敗才顯示錯誤並讓你選擇重新辨識或捨棄。單次誤判不會改變任何設定。

錄音在成功貼上前不會被刪除，所以辨識失敗或網路中斷時不需要重講。

## 其他設定

從選單列的「文字與錄音設定…」可以調整：

- **中文數字轉阿拉伯數字**（預設關閉）：只轉法條、金額與百分比，「第一百五十九條」→「第159條」。成語裡的數字不會被動到，「我一直在等」不會變成「我1直在等」。
- **第二快捷鍵**：設定後可以一鍵用另一種模式錄音，只影響當次，不改變預設。例如平常用純逐字，傳訊息時按第二快捷鍵用簡潔。
- **靜音自動停止**（預設關閉，可選 3／5／10 秒）：講完停頓後自動結束錄音。
- 錄音最長 5 分鐘的保護一律啟用，避免忘記按第二次快捷鍵。

## 產品規劃

以下功能仍在規劃階段，**目前版本尚未具備**：

- 多次偵測到新語言後詢問是否加入允許清單（目前只能在語言設定裡手動加）。
- 個人詞典管理介面與預載的台灣法律／科技詞庫。
- 智慧常用詞典（iPhone 端）與主要／備用 API 金鑰備援。

規劃文件（存放在私人工作區，不在本 Repo 內）：

- [文字輸出模式與語言控制 PRD](../../product/PRD_TEXT_OUTPUT_MODES.md)
- [智慧常用詞典 PRD](../../product/PRD_SMART_VOCABULARY.md)
- [Groq 多金鑰與安全備援 PRD](../../product/PRD_MULTI_API_KEY.md)
- [產品 Roadmap](../../product/ROADMAP.md)

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
- 純逐字／輕度整理兩種輸出模式，本機固定規則處理，不使用改寫模型。
- 未允許語言的轉錄結果會被攔截並自動重試一次，不會直接貼出。
- 暫存錄音在成功貼上後刪除；失敗時暫時保留，可直接重新辨識。
- 登入後自動啟動，並提供完整移除工具。
- 錄音一律指定 Mac 端的麥克風，不會被 macOS 的 iPhone 連續互通麥克風搶走。
- iPhone 接力模式預設關閉，必須按快捷鍵或從選單列明確開啟。
- 可與 iPhone 經加密的 Multipeer Connectivity 直接通訊，不需要 VPS 或開發者後端。
- Mac 本機快捷鍵永遠只貼上；只有已配對 iPhone 上實際按下「貼到 Mac 並送出」才會模擬 Enter。
- 不使用 ChatGPT、OpenAI API 或其他聊天模型。

## 系統需求

- macOS 13 Ventura 或更新版本。
- Groq 帳號與自己的 API Key。
- 網路連線、麥克風權限及輔助使用權限。
- 選用 iPhone 遠端功能時，兩台裝置需在附近並允許區域網路。

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

## 錄音麥克風與 iPhone 接力模式

這兩件事看起來都像「它自己連到手機」，但其實是兩個各自獨立的機制，設定也分開。

### 錄音麥克風：一律排除 iPhone

macOS 的「連續互通麥克風」會把 iPhone 註冊成這台 Mac 的輸入裝置。它是系統層級的功能，
**手機 App 沒開、手機鎖屏、手機放在別的房間都會出現在裝置清單裡**。一旦 macOS 把系統
預設輸入切到它，按下快捷鍵就只會錄到一段靜音，而且遠處的手機還會被隔空叫醒。

AI 語音輸入錄音時會明確指定裝置，不跟著系統預設走：

- 沿用系統目前的輸入裝置，但**排除 iPhone 連續互通麥克風**。
- AirPods、USB 麥克風、虛擬音訊裝置都不受影響，行為與以前相同。
- 系統預設被切到 iPhone 時，自動改用內建麥克風。
- 不會去修改系統設定，因此 Zoom、Teams 等其他 App 的輸入裝置不受影響。

可在選單列 →「iPhone 接力與麥克風設定…」改成固定使用某一個裝置，或在確實需要時
勾選「允許使用 iPhone 連續互通麥克風錄音」。

### iPhone 接力模式：預設關閉

接力模式管的是「iPhone 能不能連上來貼字」，預設是關的：

| 狀態 | 行為 |
|---|---|
| 關閉（預設） | Mac 不廣播、不接受任何 iPhone 連線，已連線的 iPhone 會被斷開 |
| 開啟 | 接受已配對 iPhone 連線，可從手機貼上與送出 |

用預設快捷鍵 `⌃⌥↑`，或從選單列的「iPhone 接力模式」切換。快捷鍵可在
「iPhone 接力與麥克風設定…」中自訂或清除。

**App 每次啟動一律是關閉狀態**，不會記住上次開著的設定。

## 從 iPhone 修改、貼上並送出

第一次使用：

1. 先安裝配套的 iPhone App，並讓 iPhone 與 Mac 開啟 Wi-Fi、藍牙及區域網路權限。
2. 確認 Mac 選單列的「AI 語音輸入」正在執行。
3. 點 Mac 選單列麥克風圖示 →「配對 iPhone…」，保持畫面開啟並記下新的六位數配對碼。
   配對期間會暫時開啟接力模式，關閉視窗後恢復原狀。
4. 在 iPhone App 點右上角齒輪 →「Mac 連線／配對」，輸入配對碼後再點找到的 Mac。
5. 配對完成後，之後只要開啟接力模式且兩端在附近，就會自動重新連線。

配對碼有效五分鐘，成功使用後立即失效。若第一次沒有成功，請從 Mac 重新產生新碼，不要繼續使用舊碼。

日常使用：

1. 在 Mac 按 `⌃⌥↑` 開啟接力模式（選單列圖示會改變）。
2. 讓 Mac 停在準備輸入的聊天文字框。
3. 從 iPhone 背面點三下或 App Shortcut 開始錄音。Mac 會鎖定當下的 App、視窗與文字框五分鐘。
4. 停止並完成 Groq 辨識後，在 iPhone 的可編輯文字框修正內容。
5. 確認 iPhone 顯示的目標，例如 `Google Chrome — ChatGPT`。
6. 選「只貼上」、「貼到 Mac 並送出」或「取消」。

Mac 在執行前與貼上後都會重新確認焦點。若 App、視窗或輸入框已改變，操作會被拒絕；文字仍保存在剪貼簿，iPhone 會顯示失敗原因。Mac 本機 `⌥↑` 錄音不會自動按 Enter。

### iPhone 配對故障排除

1. **iPhone 沒看到 Mac：**先確認 **Mac 的接力模式已開啟**（選單列「iPhone 接力模式」有勾選，或按 `⌃⌥↑`）。接力模式關閉時 Mac 不會廣播，iPhone 一定掃不到。接著確認 App 正在執行、兩台裝置的 Wi-Fi 與藍牙都已開啟，等待 5–10 秒重新探索。
2. **iPhone 曾拒絕區域網路：**前往 iPhone `設定 → 隱私權與安全性 → 區域網路 → Groq 語音輸入` 開啟權限。
3. **六位數配對碼失敗：**在 Mac 關閉舊配對畫面，再選一次「配對 iPhone…」取得新碼，並在五分鐘內完成。
4. **配對後無法自動重連：**喚醒並解鎖兩端。仍失敗時，兩端各自忘記舊配對，再用新碼重新配對。
5. **顯示版本不相容：**更新 Mac 與 iPhone App，確保兩端採用相同遠端協定。

附近連線使用加密的 Apple Multipeer Connectivity；它不是 AirDrop，不需要 Tailscale、VPS、固定 IP 或額外帳號。

## 隱私與資料

- 錄音只為轉錄而傳到 Groq Speech-to-Text API。
- App 不包含分析、廣告或自有後端。
- iPhone 遠端文字與明確動作只在已配對裝置間加密傳送，不經過開發者伺服器。
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
