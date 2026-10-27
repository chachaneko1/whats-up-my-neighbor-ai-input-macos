# 賓士貓口鼻白斑修正預覽

使用者參考真實賓士貓照片，要求 macOS／Windows 同步調整。現況的窄三角口鼻遮罩穿過 omega 嘴線，造成同一筆畫中途翻轉明暗；頭部與白胸也不連續。

計畫：僅在 `tuxedo` 的純色頭／口鼻與胸部樣式使用曲線白斑，鼻樑由窄漸寬至圓潤口鼻／下巴，接到白胸；以窄幅反鋸齒覆蓋取代硬切。沿用實際部位顏色；自訂花紋保留原邏輯。其他八色、眼睛／嘴型原畫、透明輪廓、影格、設定格式與抓放時序不改。

影響路徑：`CatAppearanceArtwork.rgb` → macOS 桌面、抓放、錄音與問候；同一原生 renderer → Windows 預覽／內建 PNG，另匯出共用覆蓋遮罩給 Windows 自訂部位 renderer。先提供 Mac 原生與 Windows 共用素材的可操作預覽，不替換現用 App 或發布。

風險中等：共用著色器廣泛使用，必須測試其他八色位元一致、原 PNG alpha 不變、自訂部位與配置相容，以及不同姿勢下白斑連續。驗證採外觀離線測試、代表性嘴線地標、全九色／抓放匯出與 Windows 核心／build。

## 已完成與驗證

- `CatAppearanceArtwork.swift` 新增賓士專用的曲線口鼻／上胸覆蓋，約兩像素反鋸齒過渡；使用實際 head／muzzle／body／chest 配色，自訂花紋保留原路徑。沒有變更 preset、schema 或使用者設定。
- `Tests/CatAppearanceTests.swift` 新增 18 項地標與自訂色檢查，完整外觀測試 **1,074 checks 通過**，含九色、36 張來源、各姿勢與錄音／問候。
- Mac 獨立 App：`build/tuxedo-preview/賓士貓口鼻修正預覽.app`，不同 bundle ID；建置、ad-hoc 簽章驗證、實際啟動及桌面／錄音視覺檢查通過。不替換現用 App。
- `./scripts/build.sh` 成功產生完整 App；既存 `AppUpdateController.swift` weak capture 與系統 SDK 的 x86_64 compatibility archive 警告未改。完整 App 產物只建置、未安裝或執行。
- Windows 工作在 `../windows-cat-animation-preview`：同一 renderer patch 匯出內建賓士 PNG、397 張動作影格與純色自訂部位遮罩，Windows 從遮罩取樣，沒有重抄一套幾何。
- Windows 核心 **280 checks**、動畫 C# **4,346 checks**、JS **773 checks**、素材／來源／publish **7,252 checks** 通過，WPF App build 及獨立預覽 publish 通過。Windows 真實桌面執行仍未驗證。
- 其他八色全部動作 PNG SHA-256 不變；賓士 397 張影格 alpha 不變。原始 SVG／PNG、表情、時序及 JSON 範例皆不改。

[前後對照](http://127.0.0.1:8776/web/tuxedo-review.html)／[修正後動作](http://127.0.0.1:8776/web/?coat=tuxedo)。使用者已於 2026-10-27 確認此版，授權整合到 macOS／Windows Lite。程式整合與 CI 驗證進行於獨立分支；正式安裝與發版另行處理。
