---
title: 接手控制（VNC）多 agent 交接板
date: 2026-10-20
owner: Claude（協調）
branch: codex/neighbor-remote-agent
status: 進行中，只在本機分支；不 push、不 merge、不發布
---

# 接手控制：Agent 交接板

## 一句話

在遠端分身預覽加一顆「接手控制」按鈕，用 macOS 螢幕共享開啟 Linux VPS 或本機第二使用者的桌面。需求與規格以 [PRD.md](PRD.md) 為準，這份文件只管分工與進度。

## 接手前必讀（依序）

1. 工作區 `README.md` 與 `AGENTS.md`：工作區規則，例如不 push、不碰 `history/`。
2. [PRD.md](PRD.md)：需求、不做的範圍、介面契約、驗收標準。
3. 本文件的「分工」與「規則」兩節；派給你的任務說明放在 `tasks/`。
4. 既有脈絡：[../REMOTE_AGENT_PREVIEW.md](../REMOTE_AGENT_PREVIEW.md)、`Sources/NeighborAgentCore/SSHTunnel.swift`。

## 分工與檔案所有權

一個檔案只能有一個負責的 agent。要改不屬於自己的檔案，先在下方「進度紀錄」留言，由協調者分配。

| ID | 任務 | 負責 | 擁有的檔案 | 依賴 | 狀態 |
|---|---|---|---|---|---|
| T0 | PRD 與交接板 | Claude | `docs/remote-desktop/PRD.md`、`HANDOFF.md` | — | 完成 |
| T1 | 遠端設定文件，以官方來源查證；任務說明見 [tasks/T1-setup-doc.md](tasks/T1-setup-doc.md) | **Antigravity**（Gemini，`agy` CLI） | `docs/remote-desktop/SETUP.md`（只新增這一個） | T0 | 完成，Claude 審閱並修正 |
| T2 | 核心狀態機、探測、啟動器與離線測試 | Claude | `Sources/NeighborAgentCore/RemoteDesktopHandoff.swift`、`Tests/RemoteDesktopHandoffTests.swift`、`scripts/test-remote-desktop.sh` | T0 | 完成 |
| T3 | 面板 UI 與預覽圖 | Claude | `Previews/RemoteAgent/RemoteDesktopHandoffModel.swift`、`RemoteAgentView.swift`、`PreviewMain.swift`、`PreviewRenderer.swift`、`build-preview.sh` | T2 | 完成 |
| T4 | 審閱 T1、同步既有文件、完整回歸、commit | Claude | `docs/REMOTE_AGENT_PREVIEW.md`、`Previews/RemoteAgent/README.md`、工作區 `README.md` 該列 | T1、T2、T3 | 完成 |
| R1 | 依獨立審閱修正：15901 佔用檢查、探測期限上限、開啟中停用結束、測試缺口；任務說明見 [tasks/R1-review-fixes.md](tasks/R1-review-fixes.md) | **Antigravity**（Gemini，`agy` CLI） | 核心、面板 model／View／Renderer、測試檔 | T2、T3 | 完成，Claude 審閱並通過 mutation 測試 |
| T5a | 本機假 VNC 伺服器與螢幕共享 loopback 檢查工具；任務說明見 [tasks/T5a-loopback-check.md](tasks/T5a-loopback-check.md) | **Antigravity**（Gemini，`agy` CLI） | `scripts/fake-rfb-server.py`、`Tests/RemoteDesktopLiveCheck.swift`、`scripts/check-screen-sharing-loopback.sh` | R1 | 完成；R2 補 RFB 3.3 握手，Claude 修腳本並實測 |
| T5 | 真機驗證（第二使用者先，VPS 等資料） | 使用者＋Claude | 驗證紀錄 `reports/REMOTE_DESKTOP_HANDOFF_<日期>.md` | T4、遠端設定完成 | 部分完成：loopback 實測完成；登入後畫面、真實 Vine Server／VPS 待使用者 |

## 規則（所有 agent）

- 只改自己擁有的檔案。**只有協調者（Claude）可以 commit**；其他 agent 不 commit、不切分支、不 stash、不 reset。
- 不 push、不 merge、不發布，也不安裝或替換正式 App。
- 不在任何機器上安裝或啟動 VNC 伺服器、不建立 macOS 使用者、不連任何 VPS。這些由使用者照 SETUP.md 自己做。
- 不碰正式 App 的 `Sources/GroqVoiceInput/`、`Resources/`、`scripts/build.sh`，也不改 `SSHTunnel.swift`。
- 不讀取、不輸入、不保存任何密碼、API Key 或 VNC 密碼。
- 查不到官方或上游依據的內容，標註「未確認」，不要寫成已驗證。
- PRD 和這份交接板若有衝突，以 PRD 為準；要改 PRD，先跟協調者確認。

## 回報格式

完成或卡住時，在「進度紀錄」加一行：

```text
- YYYY-MM-DD HH:MM｜<agent>｜<任務 ID>｜<完成／卡住／需決定>｜<改了哪些檔案>｜<驗證做了什麼、結果>｜<還沒做或不確定的事>
```

## 進度紀錄

- 2026-10-20｜Claude｜T0｜完成｜新增 PRD.md、HANDOFF.md｜—｜T1 派給 Antigravity，提示詞存於工作區 `reports/ANTIGRAVITY_TASK_2026-10-20_vnc-docs.md`
- 2026-10-20｜Claude｜T2｜完成｜新增 RemoteDesktopHandoff.swift、RemoteDesktopHandoffTests.swift、test-remote-desktop.sh；PRD 第 5、6 節補 `openingViewer` 狀態與 SSH 兩種失敗文案｜`test-remote-desktop.sh` 18 情境通過（含真實 loopback 探測 4 種）；`test-agent-ssh.sh` 不變、通過｜UI 尚未接上（T3）
- 2026-10-20｜Claude｜T3｜完成｜新增 RemoteDesktopHandoffModel.swift；修改 RemoteAgentView（側欄接手控制區、側欄可捲動、獨立預覽說明改寫）、PreviewMain、PreviewRenderer（8 張）、build-preview.sh；核心逾時文案依目標區分（第二使用者不再提 SSH）｜`test-remote-desktop.sh` 22 情境（含面板 4 種）、`test-agent-preview.sh`、`test-agent-core.sh` 通過；8 張預覽圖人工檢查｜窄版錯誤狀態底部說明需捲動才看得到（預期）；T1 SETUP.md 尚未收到
- 2026-10-20｜Claude｜T4｜部分完成｜同步 REMOTE_AGENT_PREVIEW.md、Previews README、工作區 README；新增 tasks/T1-setup-doc.md（派工說明移入 worktree，不再依賴剪貼簿）｜`test-all.sh` 27 組全過；`build.sh` 通過（x86_64＋arm64，codesign 驗證）；正式 App 原始碼對 3101f03 差異 0 行；真實探測對無伺服器的 5901 實測 9.9 秒失敗、檢視器 0 次｜等 Antigravity 交 SETUP.md 後審閱並 commit；預覽 App UI 點擊未獲授權，未做
- 2026-10-20 15:38｜Antigravity｜T1｜完成｜新增 docs/remote-desktop/SETUP.md｜以 Debian/TigerVNC 官方 manpage、Eggplant 論壇與 Homebrew formulae 查證參數與套件名稱；內容涵蓋目標說明、VPS 與 Mac 第二使用者設定、排錯對照與官方連結｜macOS 螢幕共享連本機 loopback 是否被擋、RFB 探測中斷是否計為失敗連線（依 PRD 第 10 節標註為未確認，待 T5 真機驗證）
- 2026-10-20｜Claude｜T1 審閱｜完成｜修正 SETUP.md｜用 Homebrew API 查證：`vine-server` 自 2026-09-01 停用（fails_gatekeeper_check），原文的 `brew install` 會失敗，改寫為待決定選項；`tigervnc-viewer` 已查無，改為 `tigervnc`；依 Debian tigervncserver(1)，加上 `-localhost` 時預設已是 VncAuth，所以刪掉「不指定就一定失敗」的說法；Vine Server 改引上游 OSXvnc.html，GUI 勾選名稱標為未確認；排錯表加入 15901 被佔用一列｜第二使用者要用哪一個 VNC 伺服器，記入 PRD 第 10 節，待使用者決定
- 2026-10-20｜Claude｜R1 審閱｜完成｜Gemini 修改 5 個檔案；Claude 補回 Comment Sicko 保留的 `.waiting` 註解，PRD 第 5～7、9 節同步｜`test-remote-desktop.sh` 32 情境通過；mutation 測試三組（拿掉埠號檢查、拿掉期限上限、拿掉 `.waiting`）都被抓到；8 張預覽圖重新產生｜—
- 2026-10-20｜Gemini｜T5a｜完成｜新增 fake-rfb-server.py、RemoteDesktopLiveCheck.swift、check-screen-sharing-loopback.sh｜由 Claude 執行｜Gemini 指出：探測連線本身會讓「第一個連線後退出」的規格失效，所以把沒送客戶端版本的連線當成探測
- 2026-10-20｜Gemini｜R2｜完成｜fake-rfb-server.py 支援 RFB 3.3 與 3.7 握手｜實測：螢幕共享回覆 RFB 003.003，3.3 協商成功｜—
- 2026-10-20｜Claude｜T5（部分）｜完成｜刪掉檢查腳本與 Python 中逐步敘述的註解；修正畫面張數的計算、3.3 摘要；加入 CHECK_WAIT 與停在登入步驟的提示；新增 reports/REMOTE_DESKTOP_HANDOFF_2026-10-20.md｜真實螢幕共享會連進 127.0.0.1:5901，走到密碼對話框，所以 loopback 沒有被擋；Claude 依安全規則不在系統密碼框輸入，按取消後清理｜待使用者：用 CHECK_WAIT=90 重跑並輸入任意字元，以驗證畫面；決定第二使用者的 VNC 伺服器；提供 VPS 資料；預覽 App 的 UI 點擊
