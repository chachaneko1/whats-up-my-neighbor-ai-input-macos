# Groq AI 語音輸入 for macOS

一個輕量的原生 macOS 選單列語音輸入 App。按下自訂全域快捷鍵開始錄音，再按一次停止；音訊會送到 Groq `whisper-large-v3`，轉成繁體中文後貼到原本游標位置。

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
