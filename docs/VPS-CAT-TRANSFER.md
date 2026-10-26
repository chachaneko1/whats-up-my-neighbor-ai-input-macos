# 原 App 貓咪進出 VPS：修正檢查點

更新：2026-10-27。

## 使用者要的互動

使用現有 Mac App 的同一隻桌面貓，以及選單中的現有「VPS 遠端桌面」視窗。從本機拖進已連線的 VPS 畫面後，原桌面貓暫時隱藏並在視窗裡顯示；從視窗拖到外面則回到本機。「叫牠回家」直接返回原本位置，沿用既有拎起與 400ms 放下影格。鑽貓門的軟 Q 過場仍在 Roadmap，這次不做。

## 修正範圍

- `DesktopPetController` 保持唯一一個貓咪模型與桌面面板，記住出發位置並負責進出狀態。
- `VPSDesktopWindowController` 接上既有桌面貓；不建立第二個 VNC 視窗。
- `VPSCatHostView` 是放在原 VPS 視窗裡的繪圖與點擊層，沿用同一個模型及素材；VNC 其他區域仍可操作。
- 未連線、收合或隱藏的 VPS 視窗不能接受拖入。
- 先前 `native-vps-cat-journey` 是獨立預覽，因為多開了 VNC 與貓咪，已停用並僅供追溯。

## 驗證狀態

- 修正分支：`codex/vps-existing-cat-transfer`，從 `9d07b55` 建立。
- 2026-10-27 查到現用 App 在 `/Users/panh.c/Library/Application Support/AI語音輸入/AI語音輸入.app`，內含開發來源 `0827a84` 與原本的 VPS 選單；現用程序仍在執行，額外 `NekoDesktopPreview` 程序已關閉。
- 桌面貓互動：4,737 項檢查通過；10 種原生姿勢渲染通過。
- VPS 落點測試、可用性測試、VNC 登入與斷線 5 項測試通過。
- 最後修正後的 arm64／x86_64 雙架構建置通過，產物的 designated requirement 與深層簽章驗證通過。這是工作區內的 QA 產物，未安裝。
- 尚未替換使用者目前安裝的 QA App；尚未在真實 VNC 畫面驗收跨視窗拖放。

## 下一步

最後建置與測試通過後，依工作區 `AGENTS.md` 另取得 Mac 安裝授權，再備份現用 App 與設定指紋，替換 QA App。使用者在既有 VPS 視窗自行登入；實測拖入、拖出、回家及取消，確認後才考慮提交其他分支或發布。
