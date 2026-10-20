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
3. 本文件的「分工」與「規則」兩節。
4. 既有脈絡：[../REMOTE_AGENT_PREVIEW.md](../REMOTE_AGENT_PREVIEW.md)、`Sources/NeighborAgentCore/SSHTunnel.swift`。

## 分工與檔案所有權

一個檔案只能有一個負責的 agent。要改不屬於自己的檔案，先在下方「進度紀錄」留言，由協調者分配。

| ID | 任務 | 負責 | 擁有的檔案 | 依賴 | 狀態 |
|---|---|---|---|---|---|
| T0 | PRD 與交接板 | Claude | `docs/remote-desktop/PRD.md`、`HANDOFF.md` | — | 完成 |
| T1 | 遠端設定文件，以官方來源查證 | **Antigravity** | `docs/remote-desktop/SETUP.md`（只新增這一個） | T0 | 已派工 |
| T2 | 核心狀態機、探測、啟動器與離線測試 | Claude | `Sources/NeighborAgentCore/RemoteDesktopHandoff.swift`、`Tests/RemoteDesktopHandoffTests.swift`、`scripts/test-remote-desktop.sh` | T0 | 未開始 |
| T3 | 面板 UI 與預覽圖 | Claude | `Previews/RemoteAgent/RemoteDesktopHandoffModel.swift`、`RemoteAgentView.swift`、`PreviewMain.swift`、`PreviewRenderer.swift`、`build-preview.sh` | T2 | 未開始 |
| T4 | 審閱 T1、同步既有文件、完整回歸、commit | Claude | `docs/REMOTE_AGENT_PREVIEW.md`、`Previews/RemoteAgent/README.md`、工作區 `README.md` 該列 | T1、T2、T3 | 未開始 |
| T5 | 真機驗證（第二使用者先，VPS 等資料） | 使用者＋Claude | 驗證紀錄 `reports/REMOTE_DESKTOP_HANDOFF_<日期>.md` | T4、遠端設定完成 | 未開始 |

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
