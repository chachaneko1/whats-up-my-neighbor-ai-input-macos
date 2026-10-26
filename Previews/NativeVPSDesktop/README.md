# Neko 原生桌面 Preview

2026-10-26。本機獨立 App：聊天面板與右上角 VPS 桌面是兩個真正的 macOS 視窗，不在瀏覽器白色畫布裡。

## 開啟

首次建置：

```sh
cd Previews/NativeVPSDesktop
(cd Viewer && npm ci --ignore-scripts)
./build.sh
```

需要本機 Node.js 24（目前程式使用 Apple Silicon Homebrew 路徑），以及已設定並驗證主機金鑰的 `neighbor-vps` SSH alias；遠端 VNC 需監聽 `127.0.0.1:5901`。SSH 設定與密碼不包含在 repo。

完成後雙擊 `build/Neko Desktop Preview.app`。本預覽沒有取代現用正式 App，也未設定登入時啟動。

- 狀態列的貓咪 logo：左鍵展開聊天與 VPS 面板；右鍵可隱藏兩個面板、重設位置或結束 Preview。
- 每個視窗右上角的箭頭：收合為 340 × 48 的標題列；再按一次展開。
- 視窗可拖曳、調整大小。關閉視窗不會結束狀態列程式。
- 遠端視窗是真正的 VPS VNC 桌面；啟動時經既有 `neighbor-vps` SSH alias 連線。
- 安全通道就緒後先停在登入表單；輸入密碼並按「登入桌面」才建立 VNC 連線，等待輸入不佔用未驗證的 VNC 連線。
- 請在遠端視窗直接輸入 VNC 密碼；不要傳到聊天中。密碼只存在本次 viewer 的記憶體，不寫入設定或日誌。
- 空白密碼不能送出；送出後立即鎖定按鈕，避免重複登入。未登入時不顯示中斷按鈕；登入後中斷須再確認。斷線後提供「重新連線並登入」，不自動重試。
- 完成登入後預設「只看」；按「接手操作」才啟用遠端滑鼠與鍵盤。
- 收合與隱藏保留 WKWebView 和連線；中斷按鈕或結束 App 會關閉本 App 自己的 SSH 與橋接程序。
- 聊天仍是 UI 預覽，尚未接到 VPS 上的 AI 任務服務。聊天內容不會被當作遠端指令執行。

## 視覺來源

櫻花直接移植 桌面工作區 `design/multi-chat-2026-10-26/` 的已核准 v4 幾何與參數：奶粉色 #FCF4F5 / #F8E7EB / #F0D9DF、28 片、大小 0.88、速度 0.65、風力 0.4，保留 V 形缺口。SwiftUI Canvas 繪製，支援開關、減少動態；泡泡不透明，花瓣不攔截點擊。原櫻花專案未修改。

三花貓取自 `nekonode-site/public/media/companion/calico/poster.png`。狀態列圖示沿用 `worktrees/neighbor-remote-approved-cat-icons/Sources/GroqVoiceInput/NekoMenuBarIcon.swift` 的核准圓臉版本。

## 連線與依賴

- SwiftUI / AppKit 殼；WKWebView 內嵌 noVNC 1.7.0 實際遠端 framebuffer viewer，無模擬桌面。
- Node.js：本機既有 `/opt/homebrew/opt/node@24/bin/node`。noVNC 與 ws 使用 npm ci 安裝在本資料夾 Viewer/node_modules 並複製進 App，版本鎖定於 package-lock.json。
- 僅 Mac loopback 15927 → SSH → VPS loopback 5901；HTTP / WebSocket 橋接使用隨機 loopback 埠和每次執行隨機路徑。
- StrictHostKeyChecking、BatchMode、無遠端 shell command、無 SSH agent/X11 forwarding；不更改 VPS 設定。
- HTTP Host、WebSocket Origin 與隨機路徑檢查。Viewer 使用 non-persistent WKWebView，無剪貼簿同步。
- 重建：`./build.sh`。macOS 13+、Apple Silicon；本機 ad-hoc 簽章，非公證／正式發布。

目前核驗結果見 `VERIFICATION.md`。使用者已完成密碼登入，已確認真實 VPS 桌面顯示；實際遠端輸入另行驗收。

## 版本與驗收

2026-10-26 使用者確認此原生 Preview 已檢查並授權 commit / push。原始開發位置為桌面工作區 `design/remote-desktop-native-preview/`，此處保存其已驗收原始碼與證據；不含建置產物、密碼或個人 SSH 設定。

離線登入流程測試：`node --test tests/login-flow.test.mjs`。
