# NekoNode / NekoChat Windows Lite MVP

Windows 10/11 x64、C#/.NET 10 WPF。與現有 macOS Swift App 並存；這是同一儲存庫內的新 Lite 用戶端，與 README 原有的另一個 Windows 語音專案分開。功能限於桌面貓咪、文字聊天、語音輸入；不含 AI Agent、遠端執行或遠端控制。

## 安裝／執行

1. 在本 PR 的 **NekoChat Windows Lite** Actions 工作流程取得 `nekochat-windows-lite-trial` artifact，解開 artifact 後再完整解開內層 `NekoChat-Windows-Lite-win-x64.zip`。
2. 直接執行 `NekoChat.Windows.exe`。這是自帶 .NET 的未簽署試用版本；不需要管理員權限。學校若封鎖未簽署 App，請由教室管理者審核，不要停用安全設定。
3. 可選擇在解壓縮資料夾執行 `powershell -File .\Install.ps1`，安裝至目前使用者的 `%LOCALAPPDATA%\Programs\NekoChat.WindowsLite` 並建立開始功能表捷徑；不加入自動啟動。不需要改系統執行原則。
4. 更新前先從貓咪右鍵選單離開，再執行新版本安裝腳本。個人設定與憑證另存，不會因更新被覆寫。

從原始碼執行（需 .NET 10 SDK，Windows x64）：

```powershell
dotnet run --project windows-lite/NekoChat.Windows
```

建置、測試與自帶 runtime 的 ZIP 內容：

```powershell
dotnet run --project windows-lite/NekoChat.Tests -c Release
dotnet build windows-lite/NekoChat.Windows -c Release -p:RestoreLockedMode=true
dotnet publish windows-lite/NekoChat.Windows -c Release -r win-x64 --self-contained true -o build/windows-lite-package
```

## 連線與聊天

- 貓咪透明、置頂、可拖曳；右鍵開啟選單、切換九種花色或離開。點貓咪開聊天視窗。
- 「連線與語音」選 LAN 或 VPS，填 Relay 位址、自己的 ID 與管理者提供的個人 Relay 憑證，按「儲存並連線」。兩種模式分別記住位址；不會在斷線後自動降級為 LAN。
- LAN：例如 `ws://192.168.1.20:8765/nekochat/v1/ws`。明文 WS 僅允許明確選 LAN 且使用私有 IPv4／loopback 位址。VPS：`wss://<管理者設定的主機>/nekochat/v1/ws`，憑證必須有效，不提供略過 TLS 驗證功能。
- 好友 ID 填對方 ID。雙方都必須在 Relay 設定互相授權；使用者不能自行取得他人授權。沒有離線留言或訊息持久儲存。
- 對方收到訊息時，文字氣泡出現在頭頂，不搶焦點；點擊氣泡會開啟以該好友為收件人的回覆窗。完整文字可在本次聊天紀錄查看。
- 「已送達」只表示 Relay 已寫入對方連線，並非已讀。草稿收到送達回條後才清除；離線／錯誤會保留。斷線造成送達不明時先向朋友確認，避免重送；不自動重試。
- 斷線後按「儲存並連線」明確重連。一個帳號同時只允許一個連線。

## 語音與隱私

1. 使用自己的 Groq Key，僅貼到 App 的密碼輸入欄並按儲存。不要放進聊天、程式碼、環境範例或 repo。Groq 與 Relay 憑證均使用目前 Windows 使用者的 **Windows 認證管理員**；不寫進 settings.json。
2. 到 Windows「隱私權與安全性 → 麥克風」允許桌面 App 使用麥克風；使用系統預設輸入裝置。
3. **全系統輸入**：游標放在文字欄位，按 `Ctrl + Alt + Space` 錄音，再按一次停止；不會主動切換／恢復到別的視窗。App 確認原視窗、程序與可編輯控制項仍有焦點，且沒有按著修飾鍵後才送入 Unicode 文字事件。不會按 Enter。焦點改變、密碼欄位、UI Automation 不支援、換行、權限／輸入限制時會改用剪貼簿。送出輸入事件不保證目標 App 已接受，請確認欄位。
4. **聊天語音**：按「語音草稿」開始、再按停止。辨識文字先加入草稿，確認好友與內容再按「傳送」。全系統輸入與聊天錄音互斥。
5. `Esc`／「取消錄音」／貓咪右鍵取消均可取消；60 秒自動停止。若 Esc 被其他軟體攔截，使用按鈕。全域快捷鍵衝突會提示，需關閉衝突程式後重開。
6. 錄音僅存記憶體，送至固定 Groq HTTPS transcription 端點；不寫暫存錄音、不傳給 Relay。`ITranscriptionProvider` 可替換，MVP 使用 `whisper-large-v3`，語言自動偵測。測試使用模擬 Provider，CI 不使用個人 Key、不呼叫付費轉錄。
7. 最近轉錄和有限聊天紀錄只留在記憶體，離開即清除；可按「複製最近轉錄」。剪貼簿可能被 Windows 剪貼簿歷程或其他 App 讀取，請自行管理。Relay 能讀取即時訊息；WSS 為傳輸加密，並非端到端加密。

## JSON／外觀相容

直接複用 `Examples/CatAppearance/*.json` 的九種版本 2 外觀與原版 SVG；PNG 由既有 Swift 繪製器匯出。右鍵可匯入 `cat.config.json`（版本 1/2）：支援 `appearance.preset`、`seed`、16 個部位的 `color`／`pattern`／`patternColor`，以及設定資料夾內的相對 PNG `image`。PNG 上限 5 MB、2048×2048；JSON 64 KiB。不下載 URL，不讀設定資料夾以外的圖片。

預設九種花色使用原生匯出的圖片；自訂部位使用相同解剖座標與原生虎斑遮罩繪製，邊緣與抗鋸齒可能有細微差異。WPF 只顯示靜態坐姿；macOS 的走路／拎起動畫、招呼 triggers、字型、氣泡配置與冷卻秒數不在此 MVP 範圍。匯入外觀此次啟動有效，內建花色選擇會記住。

macOS 開發者修改原生素材後可重生：`./windows-lite/tools/export-cat-assets.sh`；不更動原始 Swift 或 SVG。Windows 建置直接使用已提交素材，不需要 Swift。

## 驗證與已知限制

CI 包含 Linux Relay／C# 真實 WebSocket 整合、Windows WPF build、九種花色與自訂繪製比對、氣泡／視窗建立，以及 Windows 認證管理員寫入／讀取／刪除；另輸出畫面供檢視。CI 不代表麥克風或任意前景 App 的實機驗收。

手動驗收：見儲存庫 `nekochat/docs/LAN-TEST.md`。本機與 CI 的實際結果記錄於 `nekochat/docs/VALIDATION.md`；未經互動式 Windows 使用者驗證前，請視為試用 MVP。macOS App 尚未接上 NekoChat；現有 Office／VPS remote 協議不相容，不能拿 Office URL 當聊天 Relay。

移除：先離開 App，在設定按刪除 Groq Key／Relay 憑證，刪除安裝資料夾、開始功能表捷徑及 `%LOCALAPPDATA%\NekoChat.WindowsLite`。也可在 Windows 認證管理員刪除 `NekoChat.WindowsLite/` 開頭的 Generic Credentials。解除安裝不撤銷 Relay 憑證；請管理者刪除帳號或輪替 token 後重啟 Relay。
