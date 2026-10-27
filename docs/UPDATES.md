# 免費 macOS CI/CD 與使用者選擇更新

## 使用者看到的行為

安裝第一個含 Sparkle 的版本後，App 每天在背景檢查新版。選單提供「檢查更新…」與可關閉的「自動偵測新版本」。偵測新版只會通知，不自動下載、安裝或重新啟動。

有新版時，等錄音、檔案結束寫入、辨識、等待重試與其他對話框完成，再發出通知。第一次有新版才詢問 macOS 通知權限。點通知或選單中的新版項目，會開啟 Sparkle 的版本資訊與安裝／稍後提醒／略過選項。拒絕通知則使用 App 內提示；選單入口保留。macOS 專注模式可能隱藏通知，不能保證橫幅送達。

`SUAllowsAutomaticUpdates=false` 禁止背景自動安裝；`SUAutomaticallyUpdate=false` 是預設值。使用者同意更新後若又開始錄音，仍會延後重新啟動。離線及背景檢查錯誤不彈出錯誤；手動檢查由 Sparkle 顯示結果。Sparkle 保存稍後提醒及略過狀態。

## 免費方案與簽章

**不需要付費 Apple Developer、Developer ID、公證 API 或 App Store。** 發佈者沿用一份既有有效程式碼簽章憑證，以指紋固定選取，不限定為 Developer ID。現有安裝使用 Apple Development 憑證時可沿用它；沒有既有憑證的維護者需先建立一份固定本機簽章憑證，設定發佈機信任及相符的 p12／指紋。這不代表終端使用者需要 Apple 帳號。

兩種驗證各自負責不同工作：固定程式碼簽章及 designated requirement 維持 App 身分；Sparkle Ed25519 金鑰驗證版本清單與更新包的來源及完整性。兩者都要成功，不使用隨每次 build 更換的 ad-hoc 身分發佈。PR 的開發包可使用 ad-hoc，但不送進更新清單。

免費發佈不啟用 Hardened Runtime，也不送 Apple 公證；Sparkle 內嵌 framework/helpers 保留官方原始簽章。不做 Apple Library Validation 的繞過設定。首次開啟可能出現 macOS 安全確認，使用者可依系統支援的「打開／仍要打開」方式允許。不清除 quarantine、不停用 Gatekeeper、不安裝憑證到終端使用者的信任儲存區。一行指令安裝（`releases/latest/download/install.sh`）以 `curl` 下載，本來就沒有 quarantine 標記，因此首次開啟不經 Gatekeeper 確認；它只核對腳本內固定的 ZIP SHA-256，再執行同一支 `安裝.command`，不重簽、不用 sudo。

## 保存資料與權限

| 項目 | 保留方式 |
| --- | --- |
| Groq API Key | App 專用的 Keychain service 與 account `api-key` 不變；不進入 CI 或發佈包。 |
| 快捷鍵與偏好 | App Bundle ID 網域下既有的 UserDefaults keys 不變，不刪除或重建偏好。 |
| 貓咪設定／圖片 | 貓咪設定資料夾裡的 `cat.config.json` 與同資料夾 PNG 不寫入、不刪除；App 內 JSON 只是新使用者範本。 |
| App 身分 | Bundle ID、固定簽章憑證，以及只認 Bundle ID 的既有 designated requirement 保持相容。 |
| 安裝位置 | Sparkle 在原位置替換 App。首次手動安裝也會讀取既有 LaunchAgent 的 App 位置，支援舊的 Application Support 安裝。 |
| 登入啟動 | 更新保留既有 LaunchAgent，包括使用者原有的 `RunAtLoad` 設定；僅新安裝才建立登入項目。 |
| 權限 | 不呼叫 TCC reset、不清除或修改麥克風／輔助使用權限資料庫。 |

更新 ZIP 只有 `.app`，不執行移除程式、不搬動使用者資料。手動安裝先暫存並驗證新 App，確認新版本符合舊版 designated requirement 後再替換，保存舊 App 備份；替換途中失敗可回復。不要為了升級先執行移除程式。

舊版沒有更新器，仍須手動安裝一次。沿用同一憑證、身分與路徑可以維持相容性；跨舊簽章身分遷移、憑證到期／替換，或 macOS 政策改變仍可能重新要求授權。不能把簽章測試當成實機 TCC 授權保證。同機若有尚未合併的自行修改功能，先整合後再升級，避免較少功能的版本覆蓋現用 App。

## 一次性發佈設定

GitHub repository 或 `macos-release` environment 只需要：

| 名稱 | 類型 | 用途 |
| --- | --- | --- |
| `SPARKLE_PRIVATE_KEY` | Secret | 與 Info.plist `SUPublicEDKey` 配對的 Sparkle Ed25519 私鑰。 |
| `MACOS_CERTIFICATE_P12_BASE64` | Secret | 固定既有程式碼簽章憑證及其私鑰的加密 p12，以 base64 編碼；不要求 Developer ID。 |
| `MACOS_CERTIFICATE_PASSWORD` | Secret | p12 匯出密碼。 |
| `MACOS_SIGNING_SHA1` | Variable | 上述憑證的 40 字元大寫指紋。SHA-1 只用作憑證選擇識別值，更新驗證使用 Ed25519。 |

不需要 `MACOS_TEAM_ID` 或任何 `APPLE_NOTARY_*` 設定。憑證缺少、過期、私鑰無法使用、指紋不符或更新簽章不符時停止，不退回 ad-hoc 發佈。到期前需更新有效憑證並驗證舊版相容性，不能默默換身分。

只匯出所選的單一簽章身分，不要把整個 Keychain、其他開發憑證或 Groq API Key 傳給 CI。私鑰與密碼經限制權限的臨時檔或標準輸入設為 GitHub Secrets，不貼到聊天、Issue、source、命令列參數或日誌。Sparkle 原私鑰保存在本機 Keychain，備份後持續沿用，不要每次發佈重新產生。

發佈腳本只匯入臨時 keychain，以 `codesign --keychain` 選擇固定憑證。因 codesign 仍需從使用者搜尋清單查找私鑰，打包期間暫時加入該 keychain；先保存原始清單，退出時完整恢復，再刪除臨時 keychain、p12 及私鑰檔案。不改全域信任設定。對自簽憑證的發佈環境信任設定應由維護者明確預先配置；此腳本不修改任何全域信任。

## CI 與發佈

`.github/workflows/build.yml` 的一般 push／PR 工作不讀發佈 Secrets：編譯 Universal 2（arm64 + x86_64）、驗證簽章、執行 25 組離線測試，產出保留七天的開發安裝包與原生貓咪圖像。另有 `free-release-check`，只允許此 repository 的 main 或指定實作分支可信 push，實際匯入固定憑證、產生免費簽章安裝包及真實簽署 appcast，完全不提供付費 Apple／公證資料。該工作沒有發佈權限，不建立 tag、Release 或更新公開清單；PR／fork 不取得發佈憑證。

正式發佈：

1. 同時提高 `Resources/Info.plist` 的版本與 build，維護 `RELEASE_NOTES.md` 及 `CHANGELOG.md`，再合併通過 CI 的 PR。
2. main 收到版本檔、更新說明或發佈流程變更後，自動執行 Release macOS；使用來源檔的版本與 build，不需另建 tag。既有版本只重新驗證公開資產，不重發或覆寫；新版本的 build 必須高於已公開 appcast。仍支援可信 main 歷史中的版本 tag 或手動指定 tag。
3. 再次執行測試，以固定憑證及既有 requirement 簽署；驗證真實憑證指紋、Bundle ID、requirement 與 strict code signature。無公證步驟或付費憑證分類要求。
4. 產生 app-only 更新 ZIP、首次安裝 ZIP、SHA-256 清單、固定該版首次安裝 ZIP 雜湊的 `install.sh`，以及包含更新說明的簽署 appcast；以 App 內嵌公鑰驗證 ZIP 與 appcast 的 Ed25519 簽章。
5. 測試及簽章驗證通過後才為這個不可變 commit 建立版本 tag，建立 draft Release、上傳全部資產後才標記正式 latest。上傳失敗維持 draft，原版本清單不變。既有公開版本不覆蓋；有問題時發更高版本修正。
6. 下載已發佈的完整安裝包、更新 ZIP 及 appcast，再驗證 SHA-256、固定程式碼簽章、來源版本及 Ed25519 簽章；下載連線失敗會重試。若 GitHub 已接受正式發布但回覆逾時，先核對伺服器上的正式版與 latest 狀態；重新執行時直接驗證既有資產，不重建版本。Actions 摘要記錄版本、build、commit 及下載位置。使用者的 App 透過既有定期檢查讀取更新清單，先通知，再由使用者選擇是否安裝。

固定使用官方 Sparkle 2.10.0，版本及下載 SHA-256 固定，每次從驗證過的 archive 解開。`Resources/Info.plist` 是版本與 build 的唯一來源，選單、一般建置與正式更新包保持一致。已停止以 workflow 執行次數產生 build；正式版必須同時提高版本及 build，9999 前需明確遷移。黑貓選單顯示「版本 x.y.z（build）」；歷史紀錄見 `CHANGELOG.md`。

清單網址為 `https://github.com/yuipan0611/whats-up-my-neighbor-ai-input-macos/releases/latest/download/appcast.xml`。公開 repository 的使用者不需 GitHub token。每個標記 latest 的正式 Release 都必須含 macOS appcast；Windows 或其他產品不可搶佔 latest。PR／CI 通過並不等於公開清單已上線，首次發佈前該網址可能 404。

## 驗證範圍

離線測試涵蓋提醒延後、通知拒絕、去除重複提醒、手動檢查、結束清理；真實 Sparkle 簽章及篡改拒絕；版本倒退／輸入與憑證缺少；固定 Keychain／快捷鍵識別值。安裝測試在可拋棄資料夾驗證舊位置、備份、損壞包拒絕及設定／圖片／登入資訊位元保存。測試中的 Keychain／TCC 檔是合成標記，不能稱為實機授權驗證。

原有貓咪 317 項設定與 59 項原生 AppKit 檢查保留。免費發佈 CI 另外驗證現有憑證的真實簽署與更新清單產製。實際系統通知、使用者允許／略過更新、錄音時延後，以及實機 Keychain／麥克風／輔助使用權限，仍須在含更新器的版本正式採用時驗證。不會為了測試去重設現用 App 權限或替換含未合併功能的 App。

參考：[Sparkle](https://sparkle-project.org/documentation/)、[更新提醒](https://sparkle-project.org/documentation/gentle-reminders/)、[更新設定](https://sparkle-project.org/documentation/customization/)。

## 現用功能整合

發佈包含現用 build 24 的剪貼簿快捷視窗、十筆文字歷史、固定黑貓圖示與錄音 HUD、詞庫及修正學習、輸入目標驗證、快捷鍵設定與遠端模式。既有生產模組保留，控制器只新增更新器及貓咪指令接線；未納入本機會議研究、個人資料或未驗證模型。

可透過 `NEIGHBOR_UPDATE_DIAGNOSTICS_PATH` 明確啟用最多 128 筆本機更新驗證事件，檔案權限 0600；只記錄版本、通知狀態及功能可用布林值，不接受 API Key、轉錄或剪貼簿內容，預設不建立檔案。實機驗證期間使用此紀錄與原生 UI，完成後以一般啟動方式停用。
