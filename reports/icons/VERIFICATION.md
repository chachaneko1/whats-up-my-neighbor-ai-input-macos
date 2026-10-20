# 核准圖示套用驗證

日期：2026-10-20（台北）。

## 已通過

| 檢查 | 結果 |
| --- | --- |
| 正式 App 原生建置 | arm64＋x86_64，`scripts/build.sh` 成功；嚴格簽章完整性驗證成功，屬本機開發簽章 |
| 正式 App 離線回歸 | `scripts/test-all.sh`：全部 25 組套件通過，含更新機制 13 項測試 |
| 圖示渲染 | 與原稿 SVG 幾何比對、白底、五種狀態不同、透明五官、1x／2x 原生輸出均通過 |
| App ICNS | 十個表示尺寸，涵蓋 16–1024 px；底板內部像素為純白 |
| 核准素材一致性 | `AppIcon-source.png` 與 `AppIcon.icns` 和既有核准白底版本逐位元相同 |
| VPS 預覽 App | `Previews/RemoteAgent/build-preview.sh` 成功；預覽 bundle 內 ICNS 與核准版本一致；嚴格簽章完整性驗證成功 |
| VPS 預覽模型 | `scripts/test-agent-preview.sh`：輸入、生命週期、供應商選擇、隔離儲存檢查通過 |
| VPS 分支圖示檢查 | `scripts/test-menu-bar-icon.sh` 通過；與主線圖示實作、白底素材一致 |
| 保護項目 | 版本／build、錄音長臉素材、原稿 SVG、cat.config.json 指紋均與本次基線相同 |
| 已安裝 App | Info.plist、執行檔、ICNS、簽章資源指紋與本次開始前相同；沒有替換、重新啟動 |
| 原工作區保留 | 最新 main 及原遠端分身工作區沒有被此次圖示改動；另開隔離 worktree 保留原未提交工作 |
| 範圍檢查 | 兩個隔離工作區的 `git diff --check`、建置腳本語法與 safety config 嚴格驗證通過 |

完整本機測試／建置輸出留在各工作區 `build/icon-tests.log`、`build/icon-build.log` 或 `build/icon-preview-build.log`、`build/icon-agent-preview-tests.log`；原生圖示輸出在 `build/icon-render/`。正式 App 完整測試是在主線基準分支執行；未對遠端分支重跑所有 28 組套件，該分支執行的是相關圖示／預覽模型檢查及預覽 App 建置。

## 尚未執行，不宣稱已通過

- 沒有安裝或開啟這次產物；實際 Dock／選單列、圖示快取、深色背景可讀性尚未實機驗收。預覽圖由實際 NekoMenuBarIcon 程式繪製，並非系統截圖。
- 沒有驗證真實 VPS、供應商登入、VNC 或遠端桌面整體流程。
- 沒有替這次修改跑 GitHub CI，因為尚未推送。
- 沒有提高版本，仍為主線 1.4.5／1012；VPS 預覽保留獨立識別 tw.panh.NeighborRemoteAgentPreview 與 0.1.0／1。
- 沒有使用正式發布憑證簽署、匯出金鑰、公證、建立 tag／Release、上傳更新包或變動 appcast。

發布前事項見 [RELEASE_READINESS.md](RELEASE_READINESS.md)。
