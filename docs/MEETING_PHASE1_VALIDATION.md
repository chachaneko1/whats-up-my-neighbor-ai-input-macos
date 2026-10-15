# 多人會議第一階段驗證

狀態：第一階段實跑完成；受控測試顯示短句交替時人物合併，尚未達穩定會議轉錄門檻。

分支沿用 `codex/neko-foundation-refactor`。原工作目錄唯讀，本批新增獨立研究管線，不修改 Swift 語音輸入、詞典資料、安裝或簽章。

## 範圍與順序

1. 核對本機素材、工具與模型存取。既有 8 秒素材含三至四人，不能作為雙人穩定性證據。pyannote community-1 要求帳號接受存取條件；沒有 token，不能代替使用者接受條款。
2. 依使用者確認，採公開中文素材及無帳號門檻的 WeSpeaker 基準；保留明確指定的 pyannote adapter，不偷偷切換 backend。
3. 建立本機說話者分段、中文 ASR、時間對齊、未知／重疊標記與手動姓名編輯器，輸出 JSON／Markdown／HTML。
4. 以可追溯來源、已知參考 speaker 的測試驗證 A／B；拼接素材與自然會議分開判讀，不用模型輸出當真值。
5. 驗證時間處理、歧義拒絕、姓名只改顯示不改身分、離線編輯與輸出，再記錄真實模型結果、效能及限制。

風險：中高。新程式只讀明確提供的音檔，不錄音、不讀 Keychain、不上傳音訊。依賴／模型置於忽略的 build 目錄或模型快取，研究輸出不提交。既有 Swift 檔案於本批前後比對指紋。

## 驗收規則

- 時間戳保留來源秒數；無可用語音、沒有可靠人物對齊時不產生虛構逐字稿。
- speaker ID 與手填姓名分開；A／B 是單一錄音內首次出現順序，不能當作跨錄音人物 ID。
- 對齊證據不足或重疊時標為 UNKNOWN／需確認，不強制把文字配給某人。
- 模型成功執行不代表中文會議穩定；需獨立參考標籤、文字與真實會議樣本驗證。
- 本階段不實作公開帳號服務、不持久保存個人聲紋、不生成會議摘要、不進行人聲分離。

## 執行前固定的受控測試

來源選 AISHELL 官方 AISHELL-3 的兩位中文女性說話者 `SSB0009` 與 `SSB0011`，各六段不同錄音。只挑來源檔案清單的前六筆，不依模型結果挑選。使用兩種順序：A/B 交替及 A 全部接 B 全部，另可觀察加噪／音量變化；拼接中間加 0.5 秒靜音，沒有自然插話。

受控 smoke 門檻：兩種順序皆估出兩位說話者，且在已知來源片段內部（邊界各排除 0.25 秒）的「預測時間人物純度」達 95%。這不是 DER：來源片段含靜音，沒有人工逐幀語音活動真值；分數不能證明邊界準確、自然會議品質或廣泛穩定性。CER 另列，不把人物正確當作文字正確。

技術比較：pyannote community-1 adapter 保留，因沒有已授權模型或 token，本輪不會執行；依使用者確認改以 WeSpeaker 公開中文模型作基準。ASR 用獨立研究用的本機 faster-whisper（本輪實跑 tiny），沒有更換 App 的 Groq whisper-large-v3，也沒有上傳錄音或讀取 API Key。研究結果不能當成 Groq large-v3 的驗證結果。

補充測試（模型推論前決定）：test split 的前六段多為極短詞，總計約 22.96 秒，適合測短片段失效；另從相同兩位說話者的 train split 依檔名順序取前六個原始 WAV ≥384,000 bytes 的片段，建立較長語句交替／分組測試。選擇只依檔案長度，不依模型結果；同樣不是自然對話。

## 實際結果（2026-10-14）

| 素材／順序 | 時長 | 估計人數 | 受控人物純度 | 字形統一後 CER | UNKNOWN 片段 | 處理時間 |
|---|---:|---:|---:|---:|---:|---:|
| 較長語句／交替 | 68.20s | 2 | 100.0% | 26.7% | 12/23 | 43.84s |
| 較長語句／分組 | 68.20s | 2 | 100.0% | 18.1% | 14/26 | 18.84s |
| 短詞／交替 | 22.96s | 1 | 53.1% | 46.4% | 9/19 | 13.66s |
| 短詞／分組 | 22.96s | 2 | 100.0% | 39.3% | 8/17 | 13.32s |

判讀：

- 這些結果未強制人數為二。較長語句的兩種順序符合受控 smoke 門檻，但短詞交替只估出一人，人物純度約 53.1%，因此不能宣稱中文 A／B 已穩定。
- 人物純度只評估「模型有預測、且在已知片段內部」的時間，短詞／靜音漏檢未被當成正確；其定義不是 DER，也沒有涵蓋所有音訊品質。較長交替約 54.30 秒、分組約 54.12 秒為實際可評分的預測時間，完整時長均為 68.20 秒。
- 原始 CER 受繁簡及中文數字／阿拉伯數字差異影響；評估另用 OpenCC t2s 統一字形，未做數字語意正規化。兩種分數都保存在各次 `evaluation.json`，不能直接當成語意錯誤率。
- 本輪明確指定本機 faster-whisper tiny，以完成資源有限下的管線驗證。原先 small 權重下載未完成，未用其推論；不存在程式自動切換 provider。本輪不代表 Groq whisper-large-v3 品質。
- UNKNOWN 來自 ASR token 時間與人物分段覆蓋不足或邊界歧義。較長交替仍有 12/23 個片段需確認，說明「人物分段可用」不等於「文字與人物已精確對齊」。
- 沒有自然雙人會議的人工逐字稿／逐幀標籤，也未測插話、台灣口音或多組不同人物；不以這組拼接音訊宣稱可商用。

## 可查看的輸出

本 worktree 下（研究輸出全在已忽略的 build 目錄）：

- `build/meeting-runs/long-alternating-v3/review.html`：真正模型結果，可手填 A／B 姓名、修改文字／片段人物、選擇原音核對、下載 JSON／Markdown。
- 同目錄的 `transcript.json`、`transcript.md`、`diarization.json`、`asr.json`、`run.json` 及 `evaluation.json` 保留不同處理層的結果。
- `build/meeting-fixtures-long/alternating.wav`：上述逐字稿對應的公開拼接原音。
- `build/meeting-runs/summary.json`：四組實跑摘要。`long-alternating` 與 `long-alternating-v2` 另保留套件相容性失敗紀錄，不把失敗算成成功模型結果。
- `build/meeting-ui-test/reviewed.json`：僅供 UI 流程驗證的人工姓名與文字修改檔，不是模型品質證據。

## 驗證與保全

- `scripts/test-all.sh` 十套離線測試通過；新增 meeting 八個測試涵蓋時間、邊界歧義、重疊、去重、未知標籤、合併、人物分數與輸出安全。
- 瀏覽器實測：填 A／B 姓名、改文字、載入本機原音（68.20 秒）、點時間戳跳到對應時間、下載 JSON 並檢查姓名與文字。重設姓名後，文字修正仍保留。另確認真實輸出頁有兩個姓名欄及 23 個片段。
- 原 Swift source 的本批前後指紋一致。原工作目錄 HEAD、分支、狀態、staged／unstaged 差異及 28 個檔案指紋皆與原始基線一致。沒有修改 main、安裝新版 App、存取真實 Keychain 或上傳錄音。
- 依賴相容性已固定在研究 requirements：Torch／torchaudio 2.5.1、SoundFile 0.13.1、sklearn 1.5.2、HDBSCAN 0.8.40。研究環境與舊研究 venv 分開；pyannote adapter 尚未實跑。

## 下一步與通過條件

先補自然中文雙人會議與人工人物／文字標籤，再以已授權 pyannote 或另一個可用管線對照。重點驗證短發言、頻繁換人、相似聲線與人物邊界，不先加入 ClearVoice 增加變因。中文文字部分再比較更大本機模型或明確授權的既有 Groq 模型，與人物分段分開評估。

目前結論為「研究管線及手動核對介面可執行，部分受控樣本可分 A／B；短詞交替失敗，穩定性與自然會議驗收未通過」。

## 來源

- [AISHELL 官方 AISHELL-3](https://huggingface.co/datasets/AISHELL/AISHELL-3)：中文音訊與文字；來源 WAV SHA-256／clip ID／URL 已保存在各素材目錄 `provenance.json`。
- [WeSpeaker 官方 Python 介面](https://github.com/wenet-e2e/wespeaker/blob/master/docs/python_package.md)：使用公開中文 ResNet34，程式固定 commit `9fecd6cb4f47475d01761d87c826298dff4ef18c`。權重 SHA-256：`e44852f375b6e22de812f64dc8dad17d2634ed44b90098b5da6c36e0a076cc30`。
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper)：本輪本機 tiny／CPU int8，套件 1.2.1。
- [pyannote community-1](https://huggingface.co/pyannote/speaker-diarization-community-1)：需要使用者接受模型存取條件，本輪未代為接受、未下載或執行。

ASR 權重快照：`Systran/faster-whisper-tiny@d90ca5fe260221311c53c58e660288d3deb8d356`，SHA-256 `dcb76c6586fc06cbdac6dd21f14cfd129cc4cdd9dce19bf4ffa62e59cbe6e6d1`。完整環境與模型指紋保存在 `build/meeting-environment.txt` 及 `build/meeting-runs/model-provenance.json`。
