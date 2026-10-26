# 原生 Preview 核驗 — 2026-10-26

## 已確認
- swiftc 原生 Apple Silicon 建置通過，codesign --verify --strict 通過。
- CUA 開啟獨立 App，兩個 NSWindow；聊天 / VPS 名稱與原生控制項可讀取。
- 聊天與 VPS 各自收合為 340 × 48 標題列，展開可恢復；VPS 收合後再展開保留原登入頁。
- App menu 的顯示兩個面板動作可恢復面板。狀態列圖示與左鍵 / 右鍵動作已實作；實體點擊仍待驗收。
- 三花貓上緣裁切已修正；修正後 `evidence/chat-native.png` 無耳朵裁切。
- `evidence/chat-collapsed.png` 為原生聊天收合畫面。
- `neighbor-vps` BatchMode + StrictHostKeyChecking 連線成功；遠端 Xtigervnc 與 xfce4-session 執行中，5901 只聽 IPv4/IPv6 loopback。
- 初版曾完成 RFB greeting 與 credentialsrequired；新版移除探測握手，僅檢查本機 SSH 監聽，使用者送出密碼前不開啟 VNC socket。
- 不含隨機路徑的 HTTP 請求回 404；錯誤 Host 回 403；外來 WebSocket Origin 被拒絕。
- 結束 Preview 後 15927 不再監聽；重新開啟重新建立通道。只結束本 App 擁有的子程序。
- 原櫻花 v4 Git 工作區保持乾淨。

## 尚待完成
- 實際桌面輸入、收合後畫面連續性、狀態列貓咪的實體點擊與視窗拖曳驗收。

## 範圍
聊天 AI 仍未接線。未替換正式 App，未公開部署，未改 VPS、VNC 密碼或存取權限。

## 登入防誤觸修正（同日）
- 等待密碼時不建立 VNC 連線，避免未完成登入逾時、測試探測造成未驗證失敗累積。遠端曾明確回覆 Too many security failures；未改遠端限流或重啟服務。
- 空白不能送出、阻擋重複提交、未登入隱藏中斷；登入後中斷採原生確認對話框。失敗可重新登入，暫時限制登入與錯誤密碼文案分開。
- 五項離線行為測試全部通過（零密碼零連線、單次提交、斷線不自動重試、服務限制識別、僅 connect 事件表示成功）。新版原生建置與簽章檢查通過。
- 使用者在新版原生視窗自行完成登入；CUA 看到「已連線 · 即時桌面」，實際 XFCE 與 Chromium example.com 畫面。未讀取、儲存或代填密碼。
- 使用者正在操作原生 App，CUA 確認對話框測試被使用者操作打斷；不再搶操作。新版確認對話框與收合後連線連續性尚未完成實機複驗。

## 使用者驗收
- 2026-10-26 使用者回覆「ok checked」，授權 commit 與 push。本次保存原生 Preview 與登入防誤觸修正；未授權合併、替換正式 App 或發布。
