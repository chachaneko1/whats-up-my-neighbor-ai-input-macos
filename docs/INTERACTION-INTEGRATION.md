# 桌面貓抓取與互動整合

## 範圍與執行計畫

使用者於 2026-10-19 授權將獨立預覽的點擊、抓起與放下整合進正式 App，更新本機並保留原設定。基底為正式 main `f45b6c1`（1.4.4／1011），在隔離分支實作。

1. 接入已存在的預覽手勢與離散 Gemini PNG 播放；保留正式舔掌、行走與資料夾停靠。
2. 控制器沿用錄音、剪貼簿選取、全螢幕、鎖定、睡眠與收回 gate；只讓貓咪不透明輪廓接收滑鼠，不取得鍵盤焦點。
3. 驗證快速放下／重新抓取、遺失 mouse-up、透明區域、取消、減少動態效果、多螢幕 fixture、既有功能回歸與通用架構建置。
4. 用原簽章與原路徑更新本機，保留可回復的舊 App；逐項比對偏好、Keychain metadata、外部貓咪設定與登入啟動檔指紋。

影響：`DesktopPetModel`（狀態與座標）、`DesktopPetView`（繪圖與原生滑鼠事件）、`DesktopPetController`（排程與暫停）、`Resources/DesktopPet/Pickup`（本機 PNG）及其測試／版本說明。消費者為 `VoiceTypeController` 與桌面貓選單。

風險中：滑鼠接收與正式狀態機會影響桌面操作；非啟動面板、透明處穿透、原 busy gate 與取消回歸必須通過。保護 `tw.panh.FreeVoiceType`、既有安裝路徑與簽章、Keychain service/account、所有既有偏好鍵、錄音／貼上服務與長臉錄音 HUD。基線：7529 項桌面貓檢查通過，安全設定驗證通過。

本機更新不等同 GitHub 公開發布；本次以本機正式 App 的互動與設定保留為完成條件。

## 完成與證據

- 版本：1.4.5／1012；arm64 與 x86_64 通用 App 已建置，既有憑證指紋、bundle ID、指定簽章要求與 strict 驗簽通過。
- 正式閒置／繪圖回歸：7533 項通過。互動測試：4082 項通過，包括真實 `NSWindow.sendEvent` → view → controller → model 的按下、拖曳與放開路徑、screen 座標偏移、漏接放開、快速重新抓取、暫停、焦點、多螢幕 fixture 與實際 display callback。
- 完整 23 組離線測試通過；新增原生事件案例後，另重跑互動測試通過。沒有使用真實語音或呼叫 Groq。
- 36 張 PNG 的 SHA-256 與 R6 原素材一致。更新時一併核對原長臉錄音 HUD、App 身分與使用者決定安裝的既有更新策略。
- 14 個受保護偏好逐項指紋相同、Keychain metadata 相同、外部貓咪設定與登入啟動檔狀態／指紋相同。未匯出個人值或 API Key。
- 系統 TCC 資料庫不可讀，未將「不可讀」當成權限已實測。既有安裝路徑、憑證與 designated requirement 維持相同，未重設或改寫權限。麥克風／轉錄未在本輪重新實測。
- 已在原路徑替換並啟動正式 App；原生 UI 顯示「小黑貓桌面夥伴」按鈕與抓取說明，點擊實際顯示「呼嚕～」。獨立預覽已結束。UI 自動化對非啟動浮動視窗的實體 drag 回傳 AXError.notImplemented；拖曳事件路徑由上述原生 fixture 驗證，主觀拖曳手感與實體多螢幕仍由使用者操作確認。
- 更新前 App 保留為原安裝資料夾中的隱藏備份，收據與雜湊證據位於工作區 `reports/neko-interaction-integration/`。
