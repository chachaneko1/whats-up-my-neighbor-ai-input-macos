# 部位毛色實作與驗證紀錄

日期：2026-10-19（台北）

## 交接狀態

- 工作區：桌面協作入口下的 `worktrees/neko-appearance-v2`。
- 分支：`codex/cat-appearance-v2`；基底與 HEAD 為 `3101f03`，功能變更尚未提交。
- Mac 主線仍為 `3101f03`，沒有工作目錄變更。沒有安裝、推送、合併或發布，也沒有改寫正式 App 的設定。
- 獨立預覽：`build/appearance/自然毛色預覽.app`，使用獨立的識別碼，與正式 App 分開。
- 完整資料範例：`Examples/CatAppearance/`，九份 JSON（八種自然毛色加原版黑貓），每份明列 16 個部位。

## 完成的行為

`CatConfiguration` 讀取 version 1 或 2；version 2 使用 `appearance.preset`、`seed` 與 `parts`，先展開毛色再逐欄覆蓋。新使用者範本的空部位物件保留繼承，所以只切換預設就能換整套外觀；完整範例則可以直接修改各部位的值。錯誤設定依原規則整份回退並保留原檔，不自動遷移。

`CatAppearance`、`CatAnatomy`、`CatAppearanceArtwork` 共用於桌面、錄音與問候。SVG 使用原始 path 的前後層次辨識部位；36 張互動 PNG 有逐張定位。原圖檔、透明輪廓、時序、滑鼠操作與抓取錨點保留。原版黑貓略過重新著色路徑；自訂 PNG 仍優先且不加嘴型。

網站登入、抽取、收藏、權益與同步仍在後續範圍。此設定僅描述本機顯示，不作為官網擁有權證明。

## 驗證結果

| 項目 | 結果與證據 |
| --- | --- |
| 前一輪完整離線基線 | `scripts/test-all.sh`：24 組通過，紀錄 `build/offline-tests.log` |
| 最終外觀與範本檢查 | `scripts/test-cat-appearance.sh`：934 項通過，紀錄 `build/tabby-appearance-tests.log` |
| 設定與問候回歸 | 虎斑調整後重跑 `scripts/test-cat.sh`：317 項設定、59 項 AppKit 檢查通過，紀錄 `build/tabby-cat-tests.log` |
| 桌面互動 | 4,082 項互動檢查通過，包含於完整套件 |
| 原版黑貓回歸 | 與同基底主線產物的 516 張姿勢 PNG 逐檔 SHA-256 一致 |
| 影格與部位 | 九種外觀各 36 張影格，逐像素 alpha 一致；全部 16 個部位均映射到可見原圖像素 |
| 姿勢 | 九種外觀各十種姿勢渲染；既有左右行走、抓取及透明穿透回歸通過 |
| 錄音與問候 | 實際元件繪製、取消／完成操作、嘴型、自訂圖片優先與非啟用視窗檢查通過 |
| 自訂 PNG | 有效自訂圖在 version 1 與帶毛色的 version 2 產生相同畫面；缺圖維持原規則 |
| Mac 建置 | `scripts/build.sh` 成功；`lipo -archs` 確認 `x86_64 arm64`，嚴格本機簽章檢查通過 |
| 最後範本打包 | 已同步最終 JSON 至建置產物並重新本機簽章；打包範本與來源逐位元一致 |
| 獨立預覽 | 編譯、本機簽章與啟動通過；已實際切換三花、將尾巴單獨改灰、載入重點色 JSON |
| 前一輪繪製成本 | 臉頰修正前本機未快取影格著色中位數 2.7 ms、p95 3.3 ms；沿用 16 張／12 MiB 的快取上限 |
| 原始資源 | 原 SVG、PNG、互動時序及 Info.plist 與基底無差異 |
| 檔案檢查 | `git diff --check` 與工作區安全設定 strict validation 通過 |

首次在新工作區執行完整套件時，更新測試需要的 Sparkle 工具尚未解壓。之後使用工作區既有、校驗過的 Sparkle 壓縮檔完成建置，再跑完整套件通過；沒有藉此修改測試預期。

## 可檢視的結果

- `build/appearance/natural-coats.png`
- `build/appearance/recording-coats.png`
- `build/appearance/greeting-coats.png`
- `build/appearance/*-pickup.png`：逐毛色 36 張影格
- `build/appearance/*-poses.png`：逐毛色十種姿勢
- `build/appearance/自然毛色預覽.app`：選毛色、部位、花紋，載入 JSON，以及點擊／拖曳互動

## 仍需主人確認

毛色位置與拖曳手感仍保留人工驗收。已檢視渲染與操作預覽，但不將此視為主人核准；正式 App 安裝、公開發布，以及 Windows 支援均未執行。


## 臉頰漏色修正（2026-10-19）

使用者指出三花貓的臉頰未填完整。放大實際影格後，可見兩側臉頰外緣在橘、黑色橢圓花塊之間有白色三角細縫。

修正僅延伸三花頭部外側花塊：兩塊未重疊的側邊區域使用較近的橘／黑花塊接到原輪廓，中央白斑與獨立口鼻仍保留。原始素材、alpha、表情、動作時序、其他毛色與自訂圖片規則不變。

- 新增 18 項臉頰與中央白斑回歸檢查；外觀套件總計 876 項通過，並重新產出九種外觀、324 張來源影格及 90 個姿勢。
- 設定與問候回歸重跑：317 項設定、59 項 AppKit 檢查通過，記錄為 `build/cheek-cat-tests.log`。
- 原始 PNG、SVG、互動時序及 Info.plist 與基底仍無差異；`git diff --check` 通過。
- Mac arm64／x86_64 與獨立預覽重新建置通過，本機嚴格簽章檢查通過；紀錄 `build/cheek-build.log`、`build/cheek-preview-build.log`。
- 獨立預覽已重建並重新選擇三花貓；已檢視實際視窗中的桌面貓與錄音長臉。
- 完整 24 組為修正前的基線；本次針對共用外觀及問候消費端重跑以上檢查。
- 前後放大對照：`build/appearance/cheek-comparison.png`；單張修正後：`build/appearance/cheek-after.png`。

這次仍只更新工作區產物與獨立預覽，沒有安裝、公開發布或改寫正式使用者設定。

## 虎斑花紋修整（2026-10-19）

使用者指出橘虎斑的畫法不理想。原實作使用整片正弦條紋，造成橫跨胸腹的斜帶、密集臉頰線與生硬的額頭折線。

改成沿部位繪製、末端漸尖的弧形遮罩：額頭三道短紋，兩頰各兩道短紋，身體只保留兩側斑紋與尾環；胸腹中央保留底色。遮罩快取覆蓋率，顏色仍由每個部位的設定決定。固定種子維持花紋定位，原圖透明邊緣與表情不改動。錄音長臉使用自身額頭、眼睛的位置投影同一套頭紋。

- 新增 58 項回歸檢查，涵蓋眼睛區域、胸腹中央、額頭方向、側斑／尾環、錄音額頭定位，以及自訂花紋色和移除尾環；外觀套件共 934 項通過。
- 重新產出九種外觀、各 36 張互動影格與十種姿勢；逐像素 alpha 與固定繪製檢查通過。已批次檢視橘虎斑十種姿勢、全部 36 張互動影格，以及實際錄音元件。
- 設定與問候回歸：317 項設定及 59 項 AppKit 檢查通過；紀錄 `build/tabby-cat-tests.log`。
- 獨立預覽重新編譯、本機簽章與啟動通過；已選擇橘虎斑，檢視同一視窗中的桌面貓與錄音長臉。紀錄 `build/tabby-preview-build.log`。
- Mac App 重新建置通過，包含 arm64／x86_64，並通過本機嚴格簽章檢查；紀錄 `build/tabby-build.log`。產物僅保留在工作區，沒有安裝。
- 原始 SVG、PNG、互動時序與 Info.plist 仍與基底一致；主線工作目錄乾淨。`git diff --check` 與工作區安全設定 strict validation 通過。
- 對照圖：`build/appearance/tabby-comparison.png`；姿勢與影格：`orange-tabby-poses.png`、`orange-tabby-pickup.png`。對照使用相同應用程式姿勢，沒有重畫對照用的貓形。

本次維持獨立本機預覽，花紋美感仍待主人檢視；不代表正式安裝、發布或 Windows 驗證。
