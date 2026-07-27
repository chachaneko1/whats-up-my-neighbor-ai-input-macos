# Privacy

## 收集與傳輸

AI 語音輸入本身沒有帳號系統、分析工具、廣告 SDK 或開發者後端。開始錄音後，音訊會直接從使用者的 Mac 傳送至 Groq Speech-to-Text API，以產生文字轉錄。使用者應自行閱讀並同意 Groq 的服務條款與隱私政策。

## 本機資料

- Groq API Key：以 generic password 形式儲存在 macOS Keychain，service 為 `tw.panh.FreeVoiceType.groq`。
- 快捷鍵設定：儲存在 macOS `UserDefaults`，不包含語音或 API Key。
- 暫存錄音：寫入 macOS 暫存目錄。成功轉錄並貼上後立即刪除。若辨識失敗或辨識出使用者未允許的語言，錄音會暫時保留，讓使用者可以重新辨識而不必重講；使用者選擇捨棄、重試成功、暫留超過兩分鐘、App 結束或下次啟動時都會刪除。錄音不會被永久保存，也不會傳送到 Groq 以外的地方。
- 文字後處理：轉錄結果的簡繁轉換、標點與空格正規化、重複詞清理都在這台 Mac 本機完成，不另外連網，也不使用任何聊天或改寫模型。
- 輸出模式設定：儲存在 macOS `UserDefaults`，只記錄「純逐字」或「輕度整理」，不含語音或文字內容。
- 轉錄結果：寫入 macOS 系統剪貼簿，再視輔助使用權限貼入目前 App。
- 配對資訊：附近裝置識別儲存在本機 `UserDefaults`；六位數配對碼只在五分鐘配對期間存在記憶體中。
- App 不保存轉錄歷史。

## 權限

- 麥克風：錄製使用者主動觸發的語音。
- 輔助使用：本機錄音只模擬 `Command + V`。只有已配對 iPhone 明確送出 `貼上並送出` 動作、且 Mac 再次驗證同一輸入框時，才會額外模擬一次 Enter。
- 網路：用於呼叫 Groq Speech-to-Text API，以及透過加密的 Multipeer Connectivity 與附近已配對 iPhone 傳送文字、目標名稱與明確動作。遠端資料不經過開發者後端。

## 刪除

執行 `移除.command` 可刪除 App、本機啟動設定及 Keychain 中的 Groq API Key。剪貼簿內容由 macOS 管理。
