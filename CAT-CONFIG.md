# 自訂你的貓咪 / Customize your cat

macOS 與 Windows 版使用相同的 **version 1** `cat.config.json` 格式，可以分享範本和 PNG，不需要分享 API key 或其他個人設定。

## macOS 開始使用

1. 在選單列點選 App，選擇「開啟貓咪設定資料夾…」。這會建立設定資料夾，並在尚無設定檔時複製隨附範本；不會覆蓋既有檔案。
2. 結束 App，編輯 `cat.config.json`，儲存為 **UTF-8 JSON**。
3. 重新啟動 App。設定只在啟動時讀取，不會即時更新。

也可以在 Finder 的「前往資料夾」輸入：

```
~/Library/Application Support/tw.panh.FreeVoiceType
```

若沒有設定檔，直接使用以下預設值。Windows 使用 `%LOCALAPPDATA%\WhatsUpMyNeighbor`；兩個平台的設定資料夾各自獨立，不會自動同步。

桌面模式的「放出／收回小黑貓」獨立儲存在本機偏好設定，使用隨 App 打包的黑貓動作圖，不會改寫這份設定或自訂 PNG。自訂圖片與嘴型設定仍用於原有錄音／問候視窗。

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
  "displaySeconds": 3,
  "animateMouth": true
}
```

| 欄位 | 說明 |
| --- | --- |
| `version` | 格式版本，目前只支援整數 `1`。 |
| `image` | `null` 使用內建貓咪；自訂圖片填同資料夾內 PNG 檔名，例如 `"my-cat.png"`。 |
| `triggers` | 1–32 個完整觸發句，每句 1–80 個 Unicode 字元。設定後取代整組預設觸發句。 |
| `reply` | 氣泡回覆，1–80 個 Unicode 字元，不可換行。建議 24 字內；較長文字可能換行、縮小或省略。 |
| `fontFamily` | 已安裝字型名稱，1–80 個 Unicode 字元。未安裝時使用系統後備字型；分享設定不會安裝字型。 |
| `fontSize` | 12–28，可用小數。macOS 使用螢幕點數，配合 Retina 縮放；實際大小也會配合文字長度調整。 |
| `bold` | `true` 粗體、`false` 一般字重。 |
| `bubblePosition` | `"upperRight"` 貓咪右上方、`"upperLeft"` 左上方。 |
| `tiltDegrees` | -15 至 15 度，可用小數。負數逆時針、正數順時針。 |
| `cooldownSeconds` | 兩次問候間隔，1–60 秒，可用小數。冷卻期間完整觸發句仍不輸入其他 App，也不會延長冷卻。 |
| `displaySeconds` | 氣泡顯示時間，1–10 秒，可用小數。開始新錄音會立即收起氣泡。 |
| `animateMouth` | 預設 `true`，內建貓咪只在氣泡顯示時有無聲小嘴動畫；`false` 保留靜止嘴型。 |

省略的欄位採用預設值。欄位名稱區分大小寫；不接受未列出的欄位。數字及布林值不要加引號。文字長度以 Unicode scalar 計算，例如 `🐱` 為一個字元，組合附加符號各自計算。

## 觸發句比對

- 只比對完整句子；`what's up` 會觸發，`translate what's up` 和 `what's up my neighbor` 仍為一般聽寫。
- 忽略大小寫、前後空白與句首句尾標點，合併連續空白。
- `'`、`’`、`‘`、`ʼ`、`＇` 視為相同的英文撇號。
- 不刪除詞語內部標點：`what-s up` 不等於 `what's up`。
- 設定的觸發句不能包含換行、控制字元、純空白、純標點，或正規化後重複的句子。
- 問候在語言處理與文字輸出前比對；命中的完整觸發句不會輸入或傳送到其他 App。

## 圖片與嘴型動畫

將 `my-cat.png` 放入同一設定資料夾，改為 `"image": "my-cat.png"`：

- 僅接受本機同資料夾的 PNG，最大 **4 MiB**，寬高各最多 **2048 像素**。建議透明背景、約 **2:1** 寬高比。
- 不接受網址、絕對路徑、子資料夾、`..`、符號連結、非 PNG 或 Windows 保留檔名。設定不下載圖片，也不執行指令。
- 圖片在啟動時讀成有上限的快照，檢查格式、尺寸並解碼。變更圖片後也需要重啟。
- 貓咪的左眼取消與右眼完成按鈕位置固定。自訂圖請保留原有眼睛位置；本格式不支援改動點擊區域。
- 嘴型只在內建貓咪問候期間播放，沒有聲音。`"animateMouth": false` 可關閉；舊設定省略此欄位仍預設開啟。
- 只要指定自訂 `image` 就不加上嘴型；即使圖片無法載入而退回內建貓咪，也保持關閉。這可避免將預設嘴巴疊在別人的圖上。

## 格式錯誤時

設定檔最多 **16 KiB**，只接受有效 UTF-8（可含 UTF-8 BOM）。JSON 語法、欄位型別、版本、數值範圍或圖片路徑無效，會讓**整份設定回到預設值**；原檔會保留，不會覆寫。設定檔本身必須是一般檔案，不能使用符號連結或命名管道。

圖片不存在、過大、尺寸不符或無法解碼時，只改用內建圖片；其他有效設定仍保留。修正檔案並重啟即可，也可移走 `cat.config.json` 恢復預設。

## English quick start

Choose “開啟貓咪設定資料夾…” from the app's menu-bar menu. This creates `~/Library/Application Support/tw.panh.FreeVoiceType` and copies the bundled template only if no configuration exists. Quit the app, edit `cat.config.json` as UTF-8 JSON, then restart. Settings and images are loaded only at startup.

The version-one schema and defaults match Windows. Omitted fields use defaults; unknown fields, invalid types, unsupported versions, unsafe image paths and out-of-range values invalidate the whole configuration without overwriting it. The config limit is 16 KiB. Triggers match whole utterances only, and a match is consumed even during cooldown.

Use a same-folder PNG filename for `image`, or `null` for the built-in cat. PNGs are limited to 4 MiB and 2048 × 2048 pixels. Keep the original cat's eye positions because click targets are fixed. Missing or undecodable artwork falls back to the built-in image while retaining other valid settings. Any explicit custom image disables mouth overlays, even when the image cannot load. Set `animateMouth` to `false` to disable the silent mouth animation while retaining greetings. Fonts are resolved locally, with a system fallback when absent.
