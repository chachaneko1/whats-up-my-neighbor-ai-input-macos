# What's up my neighbor：品牌、貼上與修字學習

日期：2026-10-15。使用者要求統一小黑貓圖示及正式名稱，修復本機游標貼上，並讓手動修字預設加入字典、顯示約兩秒「不加入」提示。

## 基線與影響

- 工作目錄：既有 `codex/neko-foundation-refactor`；保留所有先前未提交內容及 Desktop 原始工作目錄。
- 安裝版：1.1.1 (10)，執行檔 SHA-256 與此 worktree 的 build 相同。App bundle 圖示仍是橘色閃電，選單及字典混用舊名。
- 修改前 11 套離線測試全部通過；codebase-safety strict validate 通過。
- 貼上：FocusTargetService 將 AXValue 可直接設定視為 Cmd+V 的必要條件，且本機沿用遠端的視窗標題精確相等規則；可能誤擋瀏覽器／Electron 欄位或動態標題。
- 實機只讀探針：系統層 focused UI 查詢在 Codex 回傳 `cannotComplete`，對前景 App 的同一查詢可成功；新增 app-scoped fallback 並核對 PID。後續直接操控 Codex 的 UI 驗收受工具限制，未繞過限制。
- 詞典：VoiceTypeController 只把觀察到的修正存成候選，仍需人工確認；貼上被判定只複製時完全不啟動觀察。

## 實作與保護範圍

1. 重用現有小黑貓素材，更新 AppIcon、Info.plist 及可見名稱。保留 bundle ID、Keychain、執行檔與安裝路徑。
2. 對本機貼上使用獨立焦點判斷，仍核對 App／元素／視窗身分，排除安全、停用與唯讀欄位；遠端規則保持嚴格。
3. 修字穩定後顯示非啟用式兩秒提示，未按「不加入」即加入。後續編輯或焦點失效取消過期候選；只保存短詞片段。
4. 更新詞典管理說明與產品／隱私文件；保留舊候選人工處理入口。
5. 聚焦回歸、全部離線測試、正式簽章建置；備份後更新既有安裝位置，檢查名稱、圖示、簽章與啟動結果。

風險：中至高，涉及 Accessibility 的輸入目標與本機字典資料。以明確本機政策隔離遠端行為；不更動 Groq 請求／模型、不自動送出、不重設系統權限。測試詞典使用隔離 UserDefaults。

## 驗證紀錄

- 修改後 `scripts/test-all.sh`：11 套全部通過，含 33 項新增自動學習回歸、17 組 dictation 情境及本機／遠端貼上測試。
- 全來源 Swift typecheck、`git diff --check`、codebase-safety strict validate、Info.plist 與既有 LaunchAgent 檢查通過。
- 小黑貓圖示 10 個尺寸（16–1024 px）及透明度驗證通過；NSApp.applicationIconImage 明確取新圖示，避免警示框沿用快取。
- 使用原憑證 SHA-1 `FC79E8CA62EE86278CE2AE921207BD47039369B2` 建置 1.1.2 (11)。嚴格簽章驗證通過，bundle ID / designated requirement 與既有安裝相同。
- 原位置 `/Users/panh.c/Library/Application Support/AI語音輸入/AI語音輸入.app` 已更新並啟動（驗證時 PID 30639，只有一個該路徑進程）。可見名稱為 `What's up my neighbor`，目錄名稱保留以維持登入啟動與權限身分。
- 安裝執行檔與建置產物 SHA-256 一致：`c6c98b559c1e7c37e4644b2fc639410e96eda18b37d3450f217f26b5bec55379`；AppIcon.icns 亦完全一致。
- 舊版備份：`/Users/panh.c/Library/Application Support/AI語音輸入/Backups/before-neighbor-20261015-003723/AI語音輸入.app`。實際替換的舊目錄另存同目錄 `installed-original.app`。
- 更新前無待處理錄音。未讀 API 金鑰、未呼叫 Groq、未新增／重設 TCC 權限、未改 LaunchAgent。
- 實際啟動成功已由進程確認；UI 自動化讀取無視窗的新選單列程式逾時，未把它當作啟動失敗。Codex 操作工具不允許直接操控 Codex，因此真人語音→外部游標貼上→改字提示的完整實機流程仍待使用者確認。離線測試不等於所有外部 App 的 Accessibility 支援或辨識準確率驗證。

## 使用方式

在要輸入的位置點一下，使用原錄音快捷鍵。貼入後在同一欄位修正一個詞，停止打字約 1.1 秒後出現兩秒提示；未按「不加入」就會加入字典。連續改字會重新等待，換 App／輸入框則取消待加入。已加入詞可在字典管理中停用或刪除；舊候選及拒絕紀錄保留。

## Build 11 後續：跨 App 貼上仍失敗

使用者確認新版所有 App 仍無法自動貼上，而且沒有錯誤提示。先前離線測試通過不足以證明實機投遞成功。追加可明確啟用、關閉即不寫入的本機診斷：僅記錄固定事件、權限與焦點判斷、按鍵發送階段，不記錄文字、剪貼簿、App/視窗名稱、PID 或金鑰。保留最近一次嘗試最多 40 筆，權限 0600。此步僅定位故障，不放寬目標核對、不更改系統權限，也不假設發送按鍵等於已貼入。


## Build 12 診斷與實機復測

- 1.1.2 (12) 使用同一原簽章憑證建置並替換既有安裝；只新增明確啟用的診斷，未更改 Build 11 的貼上傳送方式。執行檔 SHA-256：`b855ac06aba3e30fcf887cf630f01a534ccd0dd937981622ea3a96922e85084c`。
- Build 11 備份：`/Users/panh.c/Library/Application Support/AI語音輸入/Backups/before-diagnostics-20261015-010731/AI語音輸入.app`。沒有更改 LaunchAgent 或重設 TCC；診斷路徑僅透過此啟動程序的環境變數提供。
- App 自己的啟動診斷：輔助使用與按鍵發送權限均為 true，安全輸入為 false。
- 使用者於「文字編輯」空白文件實際錄音後回覆「這次有貼上」。同次診斷顯示 AXTextArea 目標、元素與視窗核對通過，剪貼簿寫入成功，鍵盤事件建立並完成發送呼叫。`post.completed` 本身不是接收確認；此次成功由使用者看到文字貼入確認。
- 重新啟動後的這次測試已恢復；原始跨 App 靜默失敗根因仍未確認，不能將診斷程式或重啟本身宣稱為確定修復。
- `scripts/test-all.sh`：全部 12 套離線測試通過，新增私密有界診斷測試；`git diff --check` 通過。


## ChatGPT 手動修字未出現提示

使用者隨後確認 ChatGPT 已可貼上，但手動改詞沒有提示。此症狀與最初的貼上失敗分開追蹤。程式碼與合成文字回歸發現：範圍驗證只有一次、中文組字中的非零選取可能直接停止觀察、替換後選取可能用舊長度核對，以及刪掉舊詞後的無候選狀態過早覆寫原始比較文字。詞彙擷取另漏掉詞內插字／刪字，單一中文字向右補字也可能形成跨詞片段。這些是可重現的缺口，尚不能指認其中哪個就是 ChatGPT 此次未提示的唯一原因。

本輪修正集中在精確範圍讀取相容性、有限重試與組字狀態、完整詞彙擷取；仍只讀本次已驗證貼入範圍及短邊界，沒有 AXValue 全文 fallback。診斷新增固定學習階段與原因，不記錄修正內容。


### Build 13 離線驗證

- `scripts/test-all.sh` 全部 14 套通過；新增 monitor 的 27 項注入測試及詞彙邊界／詞內增刪的 31 項測試，既有自動學習 33 項回歸維持通過。
- Monitor 測試包括 attributed 精確範圍備援、最多四次同目標重試、換焦點取消、組字選取等待、先刪後改保留原詞、跨界防護、審核及兩秒期限早於輪詢的競態。全部使用合成編輯器，未操作外部 App。
- 詞彙測試包括「字點→字典」「台南→台北」「ChatGPTT→ChatGPT」「語語音→語音」、詞內補字、emoji 前綴、技術名稱及長度上限；整詞刪除、獨立新增詞、標點與整句改寫排除。使用 macOS 內建離線 NaturalLanguage 斷詞。
- 全來源 typecheck、嚴格簽章建置、codebase-safety strict validate 及 `git diff --check` 通過。外部 ChatGPT 修字提示仍待新版本實測。

- Build 13 已在既有安裝位置啟動，簽章與安裝後檢查通過；使用者設定、Keychain、LaunchAgent 與 TCC 均未更改。
- 安裝執行檔 SHA-256：`a6c8994f3edd1d73b32f104abec590b434039a2b9f4f9c3cea17bf0dbb6c6bba`。Build 12 備份：`/Users/panh.c/Library/Application Support/AI語音輸入/Backups/before-learning-fix-20261015-011700/AI語音輸入.app`。
- 啟動回報輔助使用／按鍵發送權限均正常，安全輸入未啟用；目前僅此診斷啟動保留最多 40 筆固定狀態。


## Build 13 實機結果與提示視窗修正

- 使用者確認 ChatGPT 測試仍未看到提示，但隨後提供詞典截圖，顯示「台南 → 台北」已加入。
- 本機診斷已走過 observing → editing → review/candidateFound → toast → completed/added=true。原 `toast accepted` 事件在呼叫視窗顯示前寫入，只代表接受候選，不能證明使用者看見。先前將此事件稱為「顯示提示」的判讀已更正。
- 確定缺陷：未核對提示視窗可見性就自動加入，造成使用者沒有實際可用的「不加入」機會。查詢當時 App isHidden=false、螢幕數為 1；因此不能把隱藏 App 或錯誤螢幕當成已證實原因。
- 不事後按詞名或時間刪除已加入詞條，以免影響既有或手動建立的內容。修正放在提交之前：視窗確認可見後才開始兩秒，期間或期限失去可見性不自動加入。
- 使用者追加 UI 要求：小黑貓旁的說話泡泡，詢問是否加入常用詞典，設計動畫；修正個人字典底部按鈕與統計文字重疊。
- Build 14 設計：同一輸入目標所在螢幕頂部顯示黑貓＋對話泡泡，約0.18秒柔和進場，支援減少動態效果；兩秒倒數與「不加入」保持原需求。顯示檢查包含可見、目前Space、螢幕相交、App隱藏狀態與焦點未被搶走，診斷只記錄布林狀態。


### Build 14 畫面驗證

- 對話泡泡以實際 AppKit 元件渲染短詞與40字長詞圖片，黑貓、尾巴、問句、倒數條及「不加入」皆完整且不重疊。
- 字典 footer 改為按鈕列與統計列；獨立示範資料在820×660及580×640兩種內容尺寸渲染，確認底部不重疊且更新時間可見。測試僅使用隔離 UserDefaults 示範資料，未讀取使用者字典。
- 提示依目前安全輸入目標的視窗幾何選擇螢幕；只讀位置／大小，不讀標題或額外文字。
- 新的可見性檢查與計時邏輯使用注入時鐘驗證，與 UI 畫面渲染分開；上述驗證仍不能取代使用者在 ChatGPT 看到實際泡泡。

- Build 14 全部15套離線測試通過，嚴格簽章建置與安裝後驗證通過。
- 已在原位置啟動1.1.2 (14)；執行檔SHA-256：`46c075d66b1af6925763f3dd629653b5070750ce251096438e8b5addcfdaf991`。
- Build 13 備份：`/Users/panh.c/Library/Application Support/AI語音輸入/Backups/before-speech-bubble-20261015-012901/AI語音輸入.app`。未變更使用者字典、Keychain、LaunchAgent或TCC設定。


## Build 14 復測與 Build 15 診斷分流

- 使用者確認測試介面為 ChatGPT Mac 桌面 App，Build 14 仍未見泡泡。該次診斷有兩次 editing，隨後 contextChanged；沒有 review candidate 或 toast 事件，這次未走到提示呈現。現有證據不足以判定是焦點、長度或範圍哪個驗證失敗。
- Build 15 將既有目標與修正重驗逐項記為固定結果，沿原先短路順序，成功輪詢不產生額外事件；不增加探索讀取、不放寬判斷、不重綁輸入元素。
- 選單新增「預覽字典提示…」，共用正式泡泡、動畫、可見性與兩秒倒數；示範詞不帶任何字典建立、確認、拒絕或刪除回呼。真實待處理提示存在時，不讓預覽取消它。
- 直接操作該 ChatGPT 介面的工具解析到 com.openai.codex 並明確拒絕。未用其他 UI/AX 技術繞過；實際修字由使用者操作，診斷來自 App 正常流程已執行的判斷，不記輸入內容。

### Build 15 建置與安裝

- 全部15套離線測試通過；monitor的109項注入檢查涵蓋每個目標、review及commit驗證失敗，泡泡測試涵蓋預覽不寫入及真實提示保護。
- 嚴格簽章建置、codebase-safety strict validate與git diff --check通過，使用原憑證與既有指定需求。
- 已於原位置啟動1.1.2 (15)，單一進程，啟動回報輔助使用與按鍵發送權限正常。執行檔SHA-256：`ac113052e9d16e9ed51cdd6a55e7338722494f4beada908be432a245f7cc894f`。
- Build 14備份：`/Users/panh.c/Library/Application Support/AI語音輸入/Backups/before-popup-diagnostics-20261015-013852/AI語音輸入.app`。原診斷存為paste-diagnostics-build14-final.json。
- 等待使用者從小黑貓選單執行「預覽字典提示…」確認實際可見性，再定位ChatGPT的實際修正流程；此時仍未宣稱端到端修復。

### Build 15 預覽復測

- 使用者回覆選單預覽也沒有出現；正式App診斷仍僅startup與idle，沒有任何learning.toast。故不能將其解釋為可見性檢查失敗；入口是否到達仍未明。
- 隔離AppKit harness實跑正式VocabularyLearningToastController，依序產生presenting、toast、completed事件；250ms及1s時panel visible/onActiveSpace/occlusion/alpha均正常，2.7s關閉，獨立詞典entries/candidates一直為0。證據：build/toast-probe/diagnostics.json。
- 實際StatusMenuController的隔離NSApp.sendAction測試確認預覽項目已啟用、target/action正確，可呼叫private @objc無參數selector；ObjC runtime確認VoiceTypeController也暴露同selector，沒有建立真正controller或讀使用者設定。證據：build/status-menu-dispatch-review/。
- 上述檢查尚未重現正式App的入口問題，保持未完成狀態，未盲目放寬安全條件。

### Build 16 入口診斷

- 使用者確認選單第一行為What's up my neighbor。Build 15自身進程的一秒sample顯示主執行緒正常等待AppKit事件，沒有卡在提示初始化；樣本只針對本App，不含外部編輯器的讀取或控制。
- Build 16只補預覽selector第一步的固定事件，記idle gate及真實待加入提示阻擋，沒有放寬任何判斷。
- 全部15套測試與簽章建置通過，原位置更新並啟動。執行檔SHA-256：`873f7aacc4392c220e162ce8ad800f48b25a678e5bc42afebd422afc4ece7c0d`。Build 15備份：`/Users/panh.c/Library/Application Support/AI語音輸入/Backups/before-preview-entry-20261015-014420/AI語音輸入.app`。等待一次實際選單點選結果。

- Delegate lifetime隔離測試複製production main.swift的top-level持有方式，-O建置後AppKit runloop延遲回呼仍保有delegate與menu target，selector成功派送；沒有發現生命週期缺陷，也未做猜測性的retain修改。證據：build/delegate-lifetime-review/。

## Build 17 首次使用引導收斂

- 使用者補充：「開始錄音」按鈕及圖示引導只應提供初次使用者，平常不要反覆提示。
- 已確認原因：啟動的showIntroductionIfNeeded有持久化一次限制，但一般showPreview仍無條件showStartButton；重新開啟App及普通介面預覽因此再顯示引導按鈕。
- 改為共用configurePreview，只有showIntroduction=true顯示開始錄音按鈕及眼睛操作引導；一般預覽純貓，不以另一行文字取代。首次使用和使用者明確選「重新查看操作引導」保留完整引導。
- 原hasSeenIntroduction設定不重設，更新不觸發新一輪引導；錄音/辨識必要狀態與眼睛按鈕功能不變。
- HUD回歸覆蓋一般預覽、明確引導、返回一般預覽及錄音切換，檢查文字/按鈕可見性與尺寸復原。字典泡泡實機入口問題仍待使用者正常點選診斷，未宣稱修復。

### Build 17 驗收

- 全部15套離線測試、簽章建置與差異檢查通過，已安裝1.1.2 (17)。執行檔SHA-256：`ccf08671b49b0ac297d5321d23985dbd3adaed18d9c372f1697305a01e19623d`，原版備份：`/Users/panh.c/Library/Application Support/AI語音輸入/Backups/before-onboarding-cleanup-20261015-014920/AI語音輸入.app`。
- 用Computer Use只開啟本App的普通預覽。實機AX樹只有「關閉預覽」「完成預覽」兩個眼睛按鈕；實際截圖確認純小黑貓，沒有「開始錄音」按鈕或引導文字。驗證後已關閉預覽。
- 未操作ChatGPT/Codex編輯器、未啟用錄音、未修改使用者字典或首次引導記錄。字典泡泡的正式選單點選診斷仍待實際事件，保留尚未完成狀態。

## Build 17 預覽顯示確認

- 使用者回覆「有出現泡泡」，正式App的預覽可見性已有真人確認。此結果不等於手動修字會觸發提示。
- 當下最新有界診斷已被後續錄音取代：貼上驗證及observing成功，多次編輯後review回報noCandidate，最終同process但focused element不同而停止。未記錄文字，因此不能判定這些是否為單詞修正，也不能把最後的focus變化認定為App重建輸入框。
- 已保存這次診斷，請使用者在空白ChatGPT輸入框測試單詞替換，停留原輸入框且不送出；再驗證自動提示與加入流程。

## Build 17 自動修字提示確認與閱讀時間調整

- 使用者在控制測試後回覆「有，自動出現泡泡」，已確認ChatGPT實際改字可觸發提示。之後又開始另一段錄音，因此有界診斷被新的capture取代，不能捏造先前的完整trace。
- 隨後使用者回饋UI太淡、停留太短、不易察覺，要求重做視覺。此新需求取代原本約兩秒的倒數要求。
- Build 18範圍限於提示：沿用既有黑貓、墨色/米白/薄荷綠palette，改成深色高對比說話泡泡與清楚的拒絕按鈕。六秒有效閱讀時間；滑鼠移上提示暫停倒數，不搶鍵盤焦點。
- 顯示時鐘與自動加入時鐘統一；暫停期間仍檢查視窗可見性、輸入焦點與既有觀察期限。繼續編輯、隱藏或換目標仍取消過期修正。

- 控制測試的持久化結果以唯讀方式核對：只輸出「測試詞存在／啟用／對應修正紀錄為已加入」三個布林，皆為true；未輸出其他字典內容、未修改任何詞條。


### Build 18 驗收與安裝

- 實際 AppKit 元件已批次渲染短詞、40字長詞及暫停狀態；文字與按鈕沒有溢出。泡泡改為600×216點，正文17點、操作按鈕126×44點。文字對比最低10.60:1，正文16.01:1。
- 顯示及加入共用presentation的單一單調時鐘，進場動畫完成後起算六秒；滑鼠移上整個提示（含貓咪）時暫停，移開後保留餘時，少於一秒時補足一秒反應時間。
- 初始滑鼠位置、進度回呼及最終範圍驗證後都重新確認自身視窗中的滑鼠位置；不新增高頻AX範圍讀取。測試覆蓋到期同時hover、cancel/replacement重入、預覽不寫字典及隱藏/焦點失效。
- 全部15套離線測試通過，簽章建置、嚴格設定驗證及git diff --check通過。另完成唯讀時鐘/hover/preview整合審查，未發現阻擋問題。
- 確認沒有進行中的錄音後，原位置更新為1.1.2 (18)，安裝後簽章、單一進程及來源/安裝執行檔雜湊一致。SHA-256：`d0b10688f125bd8af45fcf7260c162d76095c403d7a69ce04ca666cea776f82b`。
- Build 17備份：`/Users/panh.c/Library/Application Support/AI語音輸入/Backups/before-readable-bubble-20261015-021251/AI語音輸入.app`。保留原bundle identity、指定簽章需求與安裝路徑。
- 這次正常啟動未帶診斷環境變數；先前固定事件診斷已存檔，重新啟動後內容與mtime未再變動。沒有要求重複操作已經由使用者確認成功的ChatGPT修字流程。新版視覺體感尚待使用者後續回饋，沒有宣稱真人驗收新版配色及時間。


## Build 19 貓咪與說話泡泡的整體配色及留白

- 使用者要求一起考慮貓咪、泡泡的色系，以及文字落在留白區是否清楚。檢查Build 18實際渲染後，文字對比充足，但固定三行字高造成短詞問句與倒數之間過多空白，圓形貓底座也與對話框顯得分離。
- 本輪計畫限於泡泡view、controller內容尺寸及build號：保留墨黑／暖白／薄荷綠，暖白底座改為貼近貓寬高的圓角造型，尾巴指向嘴；問句按一至三行自動決定初始高度，所有文字保持在不透明墨色底上。倒數期間不變更尺寸。
- 直接消費者為VocabularyLearningToastController；setTerm後同步panel內容尺寸，再走原有螢幕位置與動畫。六秒、hover暫停、拒絕動作、焦點檢查及字典持久化不變。風險低，主要檢查長詞溢出、視窗尺寸及hover命中範圍。
- 基線：前一輪Build 18的全部15套測試、簽章建置及安裝驗證通過。預計用同一批實際AppKit渲染比較淺／深背景、短詞、長詞及暫停狀態，再完成必要測試與原簽章安裝。


### Build 19 本機驗證

- 已批次檢視明／暗底上的短詞、40字長詞與暫停狀態。文字在實底內清楚可讀；短詞168點高、兩行192、三行216，字級維持17點。輸入同詞的倒數過程不變更高度。
- 全部15套離線測試、實際AppKit渲染／hover fixture與簽章建置通過。原位置已安裝1.1.2 (19)，確認單一進程及安裝雜湊一致。SHA-256：`d71517d566c487e6bf34a2d2bcde762a24b9e2da78ca6de83c0171a89d317e64`。
- Build 18備份：`/Users/panh.c/Library/Application Support/AI語音輸入/Backups/before-bubble-harmony-20261015-021838/AI語音輸入.app`。
- 完成安裝後，使用者另對先前Build 18圖提出更明確視覺方向：不想要墨綠色對話框，框體與字型比例不對，希望更活潑。此新回饋取代本輪深色泡泡方向，下一輪保留黑貓與六秒hover功能，改做更輕巧的淺暖色漫畫式泡泡。


## Build 20 奶油黃貓咪漫畫泡泡

- 使用者明確選擇「奶油黃泡泡、黑色輪廓，像貓咪漫畫」，此選擇取代先前墨色／薄荷綠泡泡。保留原黑貓資產、官方名稱與既有錄音介面。
- Scope為單一字典提示view及build號：以不透明奶油黃承托深色字，黑色輪廓界定淺／深背景中的形狀；縮小整體寬度、依實際文字換行定高度，把倒數與拒絕操作集中。詞彙標記使用暖黃，泡泡不再使用綠色。
- 仍保留六秒有效閱讀時間、指標停留暫停、最少一秒離開寬限、拒絕／可見性／焦點檢查。動態尺寸只在新詞setTerm時決定。原0.18秒進場及減少動態效果支援保留，不新增聲音或循環裝飾。
- 基線為Build 19全15套測試、簽章與安裝通過。用實際AppKit元件一次批次檢查淺／深背景、短／長詞及暫停，確認所有文本對比、換行和44點按鈕，再建置及更新本機。


### Build 20 驗收與安裝

- 實際AppKit一次批次渲染已檢視：淺／深背景、短詞、40字長詞及暫停；無文字溢出或重疊，短詞480×136、兩行480×160、三行480×184點。主文字17點不縮小；90×44點拒絕按鈕。正文對奶油黃15.04:1，對暖黃標記12.16:1。
- 全15套離線測試通過；實際量字、長轉短復原、倒數尺寸穩定、hover fixture與嚴格設定／差異檢查通過。已用原簽章完成建置。
- 確認沒有錄音檔後在原位置更新1.1.2 (20)，正常啟動不帶暫時診斷；確認單一進程、bundle identity、指定簽章需求、來源與安裝雜湊。SHA-256：`4ef52ed607963481e11f32ae343765de437d20f63dd6e85bcab5798ea80b827b`。
- Build 19備份：`/Users/panh.c/Library/Application Support/AI語音輸入/Backups/before-comic-bubble-20261015-022455/AI語音輸入.app`。
- 使用者已選定奶油黃漫畫方向；新畫面已在對話中提供，但尚未宣稱使用者對新版最終外觀完成實機驗收。設計決策整理於docs/design/living-signal/VOCABULARY_BUBBLE.md。
