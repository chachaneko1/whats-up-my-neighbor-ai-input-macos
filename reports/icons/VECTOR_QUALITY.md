# SVG 與放大清晰度驗證

2026-10-20。只新增可攜式 SVG 與驗證資料，不變更已核准圖形或現用 App 的 ICNS。

## 實際使用的格式

| 用途 | 格式與限制 |
| --- | --- |
| 貓臉原稿 | `Resources/DesktopPet/walk-front-face.svg`，四條原始 path，沒有內嵌點陣圖 |
| 完整白底圖示 | `Resources/AppIcon.svg`，白色圓角底板與原稿 path；可任意指定輸出尺寸。外側陰影由原生產生器另外繪製 |
| 選單列 | `NekoMenuBarIcon` 的 AppKit 原生 Bézier 曲線與透明五官，正常為 24 × 18 pt |
| App／VPS 安裝圖示 | `AppIcon.icns`，十個尺寸表示、16–1024 px，逐尺寸由 SVG 原稿繪製；它本身仍有像素上限 |

SVG 是向量原稿；安裝 App 並非直接把 SVG 當作 Dock 圖示。一般 Dock／Finder 尺寸使用多尺寸 ICNS，不能保證把已輸出的 PNG／ICNS 任意放大仍永不模糊。對外放大、印刷或製作新尺寸應使用 SVG 重新渲染。聊天預覽也可能縮圖，不能以縮圖判定原稿解析度。

## 本次檢查

- SVG 不含 `<image>`、內嵌 bitmap 或 foreignObject，四條核准路徑逐字保留。
- 直接從 SVG 輸出 4096 × 4096 PNG，另取原始像素邊緣細節檢視，沒有先放大既有 PNG。
- 1024 px SVG 與現有 App PNG 比較不透明幾何區，平均色版差異約 0.134%；獨立渲染器的邊緣反鋸齒差異在檢查容差內。
- 選單列原生曲線在 1200 × 900（50 倍座標比例）重繪並與 SVG 透明遮罩比較，平均 alpha 差異約 0.494%；外形與五官一致。
- 既有 ICNS／AppIcon-source.png 在新增 SVG 匯出後未改變；現用兩個 App 的圖示資源仍與核准 ICNS 相同。
- 五種狀態、透明五官、1x／2x、小尺寸及白底既有檢查通過。

重現：`swift scripts/generate-app-icon.swift`，再執行 `./scripts/test-menu-bar-icon.sh`。高解析圖與細節輸出於 `build/vector-proof/`，屬本機產物，不隨來源提交。SVG 本身可在瀏覽器或支援向量的設計工具中縮放檢視。

## 提交範圍

只推送兩個圖示分支；不合併、不建立 tag／Release、不改版號、更新說明或公開 appcast。`reports/icons/local-install-*` 已加入忽略規則，本機安裝收據、設定指紋及簽章身分紀錄留在本機。
