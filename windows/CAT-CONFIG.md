# 自訂你的貓咪 / Customize your cat

Windows 版支援固定的 `cat.config.json` 設定檔，不需要改程式碼。

## 開始使用

1. 在 What's Up My Neighbor 的系統匣選單點選「開啟貓咪設定資料夾（修改後重啟）」，然後結束 App。
2. 也可以按 `Win + R`，輸入 `%LOCALAPPDATA%\WhatsUpMyNeighbor` 並開啟資料夾。若資料夾尚不存在，先執行一次 App，或自行建立。
3. 正式套件首次啟動時，會把隨附的 `cat.config.json` 範本複製到此資料夾；既有檔案不會被覆蓋。如果沒有範本，請自行從套件複製，檔名保持不變。套件也附有這份 `CAT-CONFIG.md`。
4. 用文字編輯器修改並儲存為 **UTF-8 JSON**，再重新啟動 App。設定在啟動時讀取，不會即時更新。

這是每位 Windows 使用者自己的設定。分享範本和圖片即可讓別人設定自己的貓咪；不需要分享 API key、`settings.json` 或其他個人資料。

## 完整預設範本

```json
{
  "version": 1,
  "image": null,
  "triggers": ["what's up", "whats up", "what is up"],
  "reply": "what's up!",
  "fontFamily": "Comic Sans MS",
  "fontSize": 18,
  "bold": true,
  "bubblePosition": "upperRight",
  "tiltDegrees": -10,
  "cooldownSeconds": 5,
  "displaySeconds": 3
}
```

| 欄位 | 說明 |
| --- | --- |
| `version` | 設定格式版本，目前只支援數字 `1`。 |
| `image` | `null` 使用內建貓咪。自訂圖片請填同資料夾內的 PNG 檔名，例如 `"my-cat.png"`。 |
| `triggers` | 1–32 個完整觸發句，每句 1–80 個 Unicode 字元。設定後會取代整組預設觸發句。 |
| `reply` | 氣泡回覆，1–80 個 Unicode 字元，不可換行。建議 24 字以內；較長的文字會換行、縮小或在空間不足時省略。 |
| `fontFamily` | 電腦上已安裝的字型名稱，1–80 個字元，例如 `"Comic Sans MS"`、`"Segoe UI"`、`"Microsoft JhengHei UI"`。找不到時使用系統後備字型。 |
| `fontSize` | 100% 縮放下的像素大小，12–28，可用小數。實際字型會配合螢幕縮放和文字長度調整。 |
| `bold` | `true` 粗體、`false` 一般字重。 |
| `bubblePosition` | `"upperRight"` 在貓咪右上方、`"upperLeft"` 在左上方。 |
| `tiltDegrees` | -15 至 15 度，可用小數。負數逆時針、正數順時針。 |
| `cooldownSeconds` | 兩次彩蛋間的冷卻時間，1–60 秒，可用小數。冷卻期間的完整觸發句仍不會輸入到其他 App。 |
| `displaySeconds` | 氣泡顯示時間，1–10 秒，可用小數。開始新錄音會立即收起氣泡。 |

省略的欄位會採用上表預設值；欄位名稱區分大小寫。請勿新增未列出的欄位。數字及布林值不要加引號。

### 觸發句比對規則

- 只有**整句**符合才會觸發。例如 `what's up` 會觸發，`translate what's up` 和 `what's up my neighbor` 都仍是一般聽寫。
- 忽略英文字母大小寫、句首句尾的標點、前後空白，並合併連續空白。
- 英文撇號 `'`、`’`、`‘`、`ʼ`、`＇` 視為相同。
- 不會刪除詞語內部的標點：`what-s up` 不等於 `what's up`。`whats up` 是另一個明確列出的預設句。
- 不能包含換行、控制字元、空白句、純標點句，或正規化後重複的觸發句。
- 這些設定只決定貓咪彩蛋，不會改變辨識服務、語言設定、詞彙或其他聽寫處理。

### 換成自己的貓咪

把 `my-cat.png` 放在 `%LOCALAPPDATA%\WhatsUpMyNeighbor`，並改成 `"image": "my-cat.png"`。

- 只接受本機同資料夾的 **PNG**，最大 **4 MiB**，寬高各最多 **2048 像素**。建議使用透明背景。
- 不接受 JPG、GIF、SVG、網路網址、絕對路徑、子資料夾、`..` 路徑或捷徑／連結檔；設定不會下載圖片或執行指令。
- 圖片會縮放至原有貓咪的範圍，建議保持約 **2:1** 的寬高比。
- 左眼的取消按鈕與右眼的開始／完成按鈕位置固定。自訂圖片請保留原貓咪眼睛的位置；本格式不支援自訂點擊區域。
- 圖片不存在、過大或無法解碼時，App 使用內建貓咪。

## 格式有誤時

設定檔最多 **16 KiB**，只接受有效 UTF-8。JSON 語法、欄位型別、版本、範圍或圖片路徑無效時，**整份設定回到預設值**；App 保留原檔，不會覆蓋你的內容。圖片檔案本身載入失敗則只使用內建圖片。沒有設定檔時，App 直接採用預設設定。

修正檔案並重新啟動即可；也可以移走 `cat.config.json` 恢復預設。

## English quick start

Open the cat configuration folder from the tray menu, then exit the app. The packaged app automatically copies the template to your configuration folder at startup if no config exists and never overwrites an existing file. The release package includes this guide. If necessary, manually copy the supplied `cat.config.json` into `%LOCALAPPDATA%\WhatsUpMyNeighbor`, edit it as UTF-8 JSON, then restart. Omitted fields use the defaults above. Unknown fields, invalid types, unsupported versions and out-of-range values invalidate the whole configuration without overwriting the file. Use a same-folder PNG filename for `image`, or `null` for the built-in cat. PNGs are limited to 4 MiB and 2048 × 2048 pixels; keep the original cat's eye positions because its click targets remain fixed. Triggers match whole utterances only. The file contains no credentials, remote URLs or executable actions.
