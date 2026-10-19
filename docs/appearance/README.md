# 自然毛色與身體部位

此分支以 macOS `3101f03` 為基底，提供 version 2 外觀設定與獨立預覽。沒有安裝、推送或發布；Windows version 2 尚未驗證。所有毛色處理都在本機，沒有生成服務、麥克風或網路請求。

## 開啟預覽

在本工作區執行 `Previews/CatAppearance/build-preview.sh`，然後開啟 `build/appearance/自然毛色預覽.app`。

預覽可以選擇九種外觀（八種自然毛色加原版黑貓）、切換動作、逐一調整部位底色與花紋，也可以載入 JSON。桌面預覽貓使用正式互動控制器，可點擊、抓起與放下；關閉預覽就會收回它。錄音浮窗與問候均使用正式繪製元件，但沒有錄音或辨識。

預覽中的調整只存在記憶體，不會覆寫載入的 JSON，也不讀寫正式 App 的設定。需要保存時，直接編輯下方範例；正式 App 支援這份格式後，設定仍於重新啟動時載入。

## 已填好的範例

`Examples/CatAppearance/` 每份 JSON 都明確列出全部 16 個部位：

| 檔名 | 特徵 |
| --- | --- |
| [original.json](../../Examples/CatAppearance/original.json) | 原版黑貓，沿用原圖繪製路徑 |
| [black.json](../../Examples/CatAppearance/black.json) | 自然深黑底色 |
| [white.json](../../Examples/CatAppearance/white.json) | 白色覆蓋，深色五官 |
| [blue.json](../../Examples/CatAppearance/blue.json) | 灰色底毛 |
| [orange-tabby.json](../../Examples/CatAppearance/orange-tabby.json) | 橘色底、額頭短紋、雙頰各兩道弧紋、側腹短斑與尾環；胸腹中央保留底色 |
| [tuxedo.json](../../Examples/CatAppearance/tuxedo.json) | 黑色底、白口鼻、白胸腹、四隻白襪 |
| [calico.json](../../Examples/CatAppearance/calico.json) | 白底、橘黑拼色、橘／黑雙耳、白胸腹與腳掌 |
| [tortoiseshell.json](../../Examples/CatAppearance/tortoiseshell.json) | 深色底與橘色斑塊 |
| [colorpoint.json](../../Examples/CatAppearance/colorpoint.json) | 淺色身體、深色臉罩、耳朵、腳掌與尾巴 |

部位鍵、花紋名稱與驗證規則見 [CAT-CONFIG.md](../../CAT-CONFIG.md)。完整範例適合逐一修改；日常設定也可只寫 `preset` 和想覆蓋的幾個欄位。完整範例的全部值都屬於明確覆蓋，若只改 `preset` 並希望套用新預設，需先清空 `parts`；新使用者範本中的空物件則會自動繼承。舊問候文字、字型、氣泡及自訂 PNG 欄位可與 `appearance` 並存。

## 繪製方式與邊界

共用外觀模型先展開預設，再套用部位覆蓋。頭、耳、口鼻、胸腹、軀幹、四肢、腳掌與尾巴有獨立的部位標記；固定種子決定花紋位置。錄音長臉只映射它可見的頭部特徵。

原始 PNG、SVG、動畫時序、抓取錨點與原圖輪廓均保留。抓起／放下使用 `Resources/DesktopPet/Pickup/anatomy.json` 的 36 組定位，花紋裁切在原始透明遮罩內；仍然一次顯示一張完整影格。新外觀只重新著色，不合成姿勢或改變動作。

虎斑使用按部位繪製的漸尖弧形遮罩，避免整個身體套用連續波紋形成橫帶。額頭、兩頰、側腹與尾巴各有固定位置；錄音長臉依額頭及眼睛的位置投影同一份花紋。遮罩只快取覆蓋率，實際顏色仍由各部位的 `color`、`patternColor` 決定。

`image` 明確指定自訂圖片時，錄音／問候仍優先顯示該圖片，不重新著色也不疊嘴型；找不到該圖片時維持既有回退規則。桌面貓仍使用 `appearance`。沒有 `appearance` 的舊設定維持原版黑貓，不進行設定遷移。

這是顯示資料，不是官網收藏、抽取或付費資格。沒有新增 App 內抽取入口、登入、付款或同步；也不改寫舊的毛色偏好快取。

## 驗證與人工檢視

- `scripts/test-cat-appearance.sh`：設定錯誤回退、全部部位、固定花紋、324 個毛色影格的逐像素透明度、90 個姿勢、眼睛操作、自訂圖片優先，以及實際問候繪製。
- `scripts/test-all.sh`：既有離線套件與新的外觀套件。
- `scripts/build.sh`：正式 App 的 arm64／x86_64 建置；只產生工作區內的產物，不安裝。
- `build/appearance/natural-coats.png`：所有毛色對照。
- `build/appearance/greeting-coats.png`：問候對照。
- `build/appearance/recording-coats.png`：實際錄音 HUD 元件對照。
- `build/appearance/*-pickup.png`：每種毛色全部 36 張影格。
- `build/appearance/*-poses.png`：每種毛色十個姿勢。

自動檢查不能代替主人對花紋位置、姿勢間的一致感及拖曳手感的確認。請在預覽中比較白襪與胸腹交界、三花／玳瑁斑塊、重點色尾巴、兩側行走及理毛腳掌；確認前維持獨立預覽。

[本次實作與驗證紀錄](VERIFICATION.md)。
