# Privacy

## 收集與傳輸

AI 語音輸入本身沒有帳號系統、分析工具、廣告 SDK 或開發者後端。開始錄音後，音訊會直接從使用者的 Mac 傳送至 Groq Speech-to-Text API，以產生文字轉錄。使用者應自行閱讀並同意 Groq 的服務條款與隱私政策。

## 本機資料

- Groq API Key：以 generic password 形式儲存在 macOS Keychain，service 為 `tw.panh.FreeVoiceType.groq`。
- 快捷鍵設定：儲存在 macOS `UserDefaults`，不包含語音或 API Key。
- 暫存錄音：寫入 macOS 暫存目錄，辨識完成後刪除。
- 轉錄結果：寫入 macOS 系統剪貼簿，再視輔助使用權限貼入目前 App。
- App 不保存轉錄歷史。

## 權限

- 麥克風：錄製使用者主動觸發的語音。
- 輔助使用：只用於模擬 `Command + V`；App 不會模擬 Enter 或自動送出文字。
- 網路：只用於呼叫 Groq Speech-to-Text API。

## 刪除

執行 `移除.command` 可刪除 App、本機啟動設定及 Keychain 中的 Groq API Key。剪貼簿內容由 macOS 管理。
