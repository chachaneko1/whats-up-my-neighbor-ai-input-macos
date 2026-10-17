# Privacy

## 收集與傳輸

AI 語音輸入本身沒有帳號系統、分析工具、廣告 SDK 或開發者後端。開始錄音後，音訊會直接從使用者的 Mac 傳送至 Groq Speech-to-Text API，以產生文字轉錄。使用者應自行閱讀並同意 Groq 的服務條款與隱私政策。

## 本機資料

- Groq API Key：以 generic password 形式儲存在 macOS Keychain，service 為 `tw.panh.FreeVoiceType.groq`。
- 快捷鍵設定：儲存在 macOS `UserDefaults`，不包含語音或 API Key。
- 暫存錄音：寫入 macOS 暫存目錄，辨識完成後刪除。
- 轉錄結果：寫入 macOS 系統剪貼簿，再視輔助使用權限貼入目前 App。
- 配對資訊：附近裝置識別儲存在本機 `UserDefaults`；六位數配對碼只在五分鐘配對期間存在記憶體中。
- 常用詞典：只保存使用者明確確認或手動加入的詞彙，以及啟用、釘選、時間、使用次數與同步版本；不保存它出現在哪個 App 或聊天室。
- 貼上後修正監看：只在 Groq 剛貼入的同一輸入元素內讀取精確貼入範圍，最長兩分鐘；安全輸入框不監看，完整原始／修改後逐字稿不落地保存。
- App 不保存轉錄歷史。

## 權限

- 麥克風：錄製使用者主動觸發的語音。
- 輔助使用：本機錄音只模擬 `Command + V`，並在貼上後限縮讀取剛貼入範圍，以偵測使用者是否修正詞彙。只有已配對 iPhone 明確送出 `貼上並送出` 動作、且 Mac 再次驗證同一輸入框時，才會額外模擬一次 Enter；此送出流程不啟動修正監看。
- 網路：用於呼叫 Groq Speech-to-Text API，以及透過加密的 Multipeer Connectivity 與附近已配對 iPhone 傳送文字、目標名稱與明確動作。遠端資料不經過開發者後端。

## 刪除

執行 `移除.command` 可刪除 App、本機啟動設定及 Keychain 中的 Groq API Key。剪貼簿內容由 macOS 管理。
