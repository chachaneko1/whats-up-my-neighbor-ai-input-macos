# macOS CI/CD 與使用者選擇更新

## 使用者看到的行為

安裝第一個含 Sparkle 的版本後，App 每天在背景檢查正式版。選單提供「檢查更新…」與可關閉的「自動偵測新版本」。偵測新版只會通知，不會自動下載、安裝或重新啟動。

有新版時，等錄音、檔案結束寫入、辨識、等待重試與其他對話框完成，再發出通知。第一次發出更新通知前才詢問 macOS 通知權限。點選通知或選單中的新版項目，會開啟 Sparkle 的版本資訊與安裝／稍後提醒／略過選項。若拒絕通知，使用 App 內更新視窗提示；選單入口始終存在。勿把通知送達視為保證：macOS 專注模式可能隱藏橫幅。

每次都需使用者同意安裝。`SUAllowsAutomaticUpdates=false` 禁止改成背景自動安裝；`SUAutomaticallyUpdate=false` 是預設值。即使使用者同意更新後又開始錄音，也會延後重新啟動。沒有新版本、離線、更新服務故障時，背景檢查不彈出錯誤；手動檢查會由 Sparkle 說明結果。Sparkle 管理稍後提醒及略過版本狀態。

## 保存資料與權限

更新封裝只有 `AI語音輸入.app`，替換現有 App 本體，不執行移除程式。保留以下位置／識別值：

| 項目 | 保留方式 |
| --- | --- |
| Groq API Key | Keychain service `tw.panh.FreeVoiceType.groq`、account `api-key` 不變；不進入發佈流程。 |
| 快捷鍵與偏好 | `tw.panh.FreeVoiceType` 的既有 UserDefaults keys 不變，更新器不清除偏好。 |
| 貓咪設定／圖片 | `~/Library/Application Support/tw.panh.FreeVoiceType/cat.config.json` 與同資料夾 PNG 不寫入、不刪除；App 中的 JSON 只是新使用者範本。 |
| macOS 身分 | Bundle ID `tw.panh.FreeVoiceType` 不變；Sparkle 在原安裝位置更新，固定沿用同一 Developer ID。 |
| 麥克風／輔助使用權限 | 不呼叫 TCC reset、不刪除權限資料庫，也不重新要求重設權限。 |

**首次遷移限制：** 舊版沒有更新器，仍須手動安裝一次。既有本機版使用 Apple Development 或 ad-hoc 簽章；改為 Developer ID 是簽章身分遷移，macOS 可能重新要求麥克風／輔助使用或 Keychain 授權。資料仍保留，但不能承諾 macOS 權限跨憑證自動沿用。之後每次使用相同 Developer ID、Bundle ID 與安裝位置。不要用新憑證偷偷覆蓋既有本機簽章，也不要透過清除 TCC 處理問題。

同機若有尚未合併的自行修改版本，正式升級前應先整合其功能；不能只依版本號就覆蓋成較少功能的版本。

## CI

`.github/workflows/build.yml` 在 push／PR 編譯 Universal 2（arm64 + x86_64）App、檢查簽章，執行七組離線測試，並產出保留七天的開發安裝包與貓咪 AppKit 圖像。開發包沒有 Developer ID 公證，不會進入自動更新清單。PR 工作只有讀取權限、沒有發佈憑證。

Sparkle 2.10.0 來自官方 release；`scripts/fetch-sparkle.sh` 固定版本與 SHA-256，每次從驗證過的壓縮檔重新解開，不信任殘留的 framework。程式使用 macOS 13 deployment target。`./scripts/build.sh`、`./scripts/test-all.sh` 可重現 CI。

## 一次性發佈設定

在 GitHub repository 或 `macos-release` environment 設定：

| 名稱 | 類型 | 用途 |
| --- | --- | --- |
| `SPARKLE_PRIVATE_KEY` | Secret | Sparkle Ed25519 私鑰，與 Info.plist 的 `SUPublicEDKey` 配對。 |
| `MACOS_CERTIFICATE_P12_BASE64` | Secret | **Developer ID Application** 憑證與私鑰的 p12，以 base64 編碼。Apple Development 不適用。 |
| `MACOS_CERTIFICATE_PASSWORD` | Secret | p12 匯出密碼。 |
| `MACOS_TEAM_ID` | Variable | 與 Developer ID 憑證相符的 10 字元 Team ID。 |
| `APPLE_NOTARY_KEY_P8_BASE64` | Secret | App Store Connect team API key 的 p8，以 base64 編碼。 |
| `APPLE_NOTARY_KEY_ID` | Secret | 公證 API key ID。 |
| `APPLE_NOTARY_ISSUER_ID` | Secret | 公證 API key issuer UUID。 |

私鑰不要貼入聊天、Issue、source、命令列參數或日誌。Sparkle 私鑰可由 `generate_keys --account tw.panh.FreeVoiceType` 保存在本機 Keychain，再經臨時限制權限檔案傳入 GitHub Secret；傳完刪除臨時檔。保留離線備份，不要每次 release 重新產生金鑰。

建議 repository ruleset 要求 PR 與 Build 檢查通過再合併；`macos-release` environment 可限制 main／版本 tags。憑證與公證資料缺少時，release 腳本在匯入任何 keychain 前停止，不發佈空包或無簽章更新。

## 發佈版本

1. 合併通過 CI 的 PR，更新 `RELEASE_NOTES.md`。
2. 在 main 上建立尚未使用過、且高於既有正式版的版本 tag，例如 `v1.3.0`，推送該 tag。也可在 Actions 的 Release macOS 手動指定已存在且位於 main 歷史中的 tag。
3. 流程再次測試，匯入臨時 keychain，以 Developer ID 逐層簽署 helpers/framework/App、啟用 hardened runtime 與 audio-input entitlement，送 Apple 公證並 staple。驗證 `codesign`、`stapler`、`spctl`。
4. 產生 app-only 更新 ZIP、首次安裝 ZIP、SHA-256 清單與含更新說明的簽署 appcast。以嵌入 App 的公鑰驗證 ZIP 與 appcast 的真實 Ed25519 簽章。
5. 先建立 draft Release，全部資產上傳成功後才轉為正式 latest。上傳失敗保留 draft，既有版本清單不變。已存在版本不覆蓋，修復後清理未發佈的 draft 再重跑，或發新版本。

版本號由合法 `v主版.次版.修訂` tag 寫入**輸出** Info.plist。build 使用此 workflow 的 run number + 1000，重跑同一 run 不增加，9999 前要求明確遷移。憑證臨時檔與 keychain 由退出處理移除；不改發佈機以外的 keychain。

清單固定網址為 `https://github.com/yuipan0611/groq-ai-voice-input-macos/releases/latest/download/appcast.xml`。repository 目前公開，使用者不需要 GitHub token。**每個標記 latest 的正式 Release 都必須包含這份 macOS appcast**；Windows 或其他獨立產品 release 不可搶佔 latest。首次正式 release 成功前，該網址可能 404，不能當作已上線的更新服務。

## 驗證範圍

離線測試涵蓋忙碌延後、拒絕通知的替代提示、不重複通知、手動檢查、略過後清理；也使用暫存測試金鑰產生真實 Sparkle appcast／ZIP，確認正確簽章通過、篡改 ZIP 或清單失敗，檢查原有 Keychain／快捷鍵識別值。原有貓咪設定的 317 項政策檢查與 59 項原生 AppKit 檢查仍執行。

編譯、離線測試及 ad-hoc 開發包不等於正式更新已交付。首次正式發佈還需 Developer ID／公證設定，並用兩份可犧牲的正式簽章 App 做實際舊版→新版測試：同意更新、稍後／略過、通知拒絕、錄音中延後、更新後設定與實機權限。對失敗版本的復原應保留已發佈安裝檔；自動修復可發更高 build 的修正版，不能只把舊二進位標記 latest。

參考：[Sparkle 設定](https://sparkle-project.org/documentation/customization/)、[背景 App 更新提醒](https://sparkle-project.org/documentation/gentle-reminders/)、[Apple 公證](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
