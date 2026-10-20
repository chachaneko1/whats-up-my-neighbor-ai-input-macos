# 接手控制（VNC）驗證紀錄

日期：2026-10-20（台北）。分支 `codex/neighbor-remote-agent`。此交付是本機獨立預覽的功能，非正式 App 更新；未 push、未合併、未發布。

## 分工

| 工作 | 執行者 | 審閱與驗證 |
|---|---|---|
| PRD、交接板、核心狀態機、面板 UI | Claude | 由獨立審閱 agent 做對抗式審查；Comment Sicko 清理註解 |
| SETUP.md（T1） | Gemini（Antigravity `agy` CLI） | Claude 查證並修正事實 |
| 審閱修正（R1） | Gemini | Claude 編譯、測試，並做 mutation 測試 |
| 假 VNC 伺服器與 loopback 檢查工具（T5a、R2） | Gemini | Claude 修正腳本並實際執行 |

## 已驗證

| 項目 | 結果與實際範圍 |
|---|---|
| 離線測試 | `scripts/test-remote-desktop.sh` 32 情境通過。涵蓋：<br>• 狀態機、generation 擋舊回呼、15901 佔用、探測期限上限<br>• 啟動器參數、面板 model<br>• 7 種真實 loopback 探測與埠號檢查 |
| mutation 測試 | 拿掉埠號檢查、拿掉每次探測的期限上限、拿掉 `.waiting` 分支，三組都讓測試失敗 |
| 真實探測，無伺服器 | 對沒有伺服器的 5901，9.9 秒後顯示第二使用者的逾時文案，檢視器啟動 0 次 |
| 真實螢幕共享與 loopback | `scripts/check-screen-sharing-loopback.sh` 依序啟動本機假 RFB 伺服器、真實控制器、真實探測與 `open -b com.apple.ScreenSharing`：<br>• 控制器走完 `probing → openingViewer → viewerOpened`<br>• 螢幕共享**有連進** 127.0.0.1:5901，回覆 `RFB 003.003`<br>• 伺服器以 3.3 協定選擇安全類型 1（None）後，螢幕共享仍跳出「需要密碼來登入『127.0.0.1:5901』」 |
| 預覽圖 | 8 張，包含接手中與窄版深色失敗，皆已人工檢查 |
| 回歸 | 見文末的最終回歸結果 |

### 這次實測回答的未知數

- PRD 第 10 節擔心螢幕共享會拒絕連到同一台 Mac 的 loopback。實測顯示：對非 Apple 的 VNC 伺服器，它會連線，並一路走到登入步驟。
  - 這次只證明網路連線與 RFB 握手可以進行。真正的 Vine Server 在另一個使用者帳號裡是否可用，仍待真機驗證。
- 螢幕共享對非 Apple 伺服器使用 RFB 3.3。伺服器即使選 None，它仍會先要求密碼。

## 尚未驗證

- **登入之後的畫面傳輸。** 需要有人在密碼對話框輸入任意字元，假伺服器不會驗證：

  ```sh
  CHECK_WAIT=90 ./scripts/check-screen-sharing-loopback.sh
  ```

  依安全規則，Claude 不在系統 App 的密碼對話框代為輸入。
- **預覽 App 的 UI 點擊。** 使用者這次沒有授權操作預覽 App。按鈕背後的 model 已有測試，但按鈕本身沒有實際點擊驗證。
- **真實第二使用者與 VPS 端到端。**
  - 第二使用者：Homebrew 的 `vine-server` 自 2026-09-01 起停用（`fails_gatekeeper_check`），要用哪一個伺服器待使用者決定（PRD 第 10 節）。
  - VPS：需要連線資料。

## 證據位置

| 證據 | 位置 | 進版控 |
|---|---|---|
| 檢查工具 | `scripts/fake-rfb-server.py`、`scripts/check-screen-sharing-loopback.sh`、`Tests/RemoteDesktopLiveCheck.swift` | 是 |
| 實測 log 與預覽圖 | `build/loopback-check/`、`build/remote-agent-preview/renders-handoff/` | 否 |
| Gemini 的執行紀錄 | `build/agy-*.log` | 否 |

## 最終回歸結果

- 基準 commit：`897e1dd`。
- 測試：`./scripts/test-all.sh` 的 27 組離線測試全部通過，接手控制那組是 32 個情境。
- 建置：`./scripts/build.sh` 通過，產物同時包含 x86_64 與 arm64。
- 正式 App：`Sources/GroqVoiceInput`、`Resources`、`scripts/build.sh` 與 `3101f03` 相比沒有差異（0 行）。
- 未安裝、未替換目前使用中的 App。
