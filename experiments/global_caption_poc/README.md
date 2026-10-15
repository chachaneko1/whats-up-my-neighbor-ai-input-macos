# 貓咪全域雙語字幕：本機可行性測試

測試日期：2026-10-14。狀態：**研究驗證，尚未整合進貓咪 App**。

## 目的與環境

驗證 Mac 上的系統播放聲音能否由貓咪接收，以及本機英文辨識、繁中翻譯在 8 GB 裝置上的實際速度與口音錯字。測試機為 Apple M1、8 GB、macOS 26.5.2；`whisper.cpp` CLI 1.8.4 使用 Metal。沒有將使用者的錄音送往外部 API，也沒有更改系統預設輸出。

音訊與模型放在被 Git 忽略的 `build/global-caption-poc/`，本目錄只保留重現腳本和結果說明。`sources/` 沒有變更。

## 音訊入口

| 測試 | 實際結果 | 邊界 |
|---|---|---|
| BlackHole 2ch 輸入 | 公開音訊送入 BlackHole，從其輸入錄回 6.31 秒，平均音量 −18.8 dBFS；本機模型能辨識。 | 這只驗證虛擬音效裝置，不代表系統預設輸出已切到多重輸出。 |
| 原生 Core Audio 全域 tap | 靜音對照 0 次回呼；測試程式送音到 BlackHole 時 875 次回呼、峰值 0.562。探針只計算峰值，不保存音訊。 | 驗證了此 Mac 的原生 tap 能接到一個程序的播放聲音；尚未測各種會議 App 或完成貓咪 App 的權限流程。 |

系統播放擷取實作參考：[Apple Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)。目前產品的 `Info.plist` 只有麥克風用途說明，未加入 `NSAudioCaptureUsageDescription`；正式整合時還需要處理系統音訊錄製授權。

## 印度口音英文辨識

主要音源來自 [George Mason University Speech Accent Archive](https://accent.gmu.edu/) 的五位出生於印度的講者，母語分別為 Hindi、Marathi、Tamil、Telugu、Bengali。每位朗讀同一段 69 詞的英文；原站內容採 [CC BY-NC-SA 4.0](https://accent.gmu.edu/download/)。這是有參考文字的**朗讀語音**，不是自然多人會議；個別講者也可能沒有逐字照稿念。評分忽略大小寫和標點，另將 zero–nine 的英文數字與 0–9 視為相同。

| 講者 | `base.en-q5_1` 數字正規化錯字率 | `large-v3-turbo-q5_0` 數字正規化錯字率 | 單段冷啟動耗時：base／turbo |
|---|---:|---:|---:|
| Hindi | 0 / 69（0%） | 0 / 69（0%） | 1.00／3.60 秒 |
| Marathi | 4 / 69（5.8%） | 1 / 69（1.4%） | 0.98／3.68 秒 |
| Tamil | 2 / 69（2.9%） | 1 / 69（1.4%） | 0.87／3.60 秒 |
| Telugu | 1 / 69（1.4%） | 1 / 69（1.4%） | 0.95／3.68 秒 |
| Bengali | 0 / 69（0%） | 0 / 69（0%） | 1.00／3.76 秒 |

兩個模型都在這台 8 GB M1 上完成測試，沒有記憶體不足錯誤。模型檔約 57 MiB 與 547 MiB；本次所見 CLI 最高常駐記憶體約 0.75 GB，但此數值**不含全部 GPU／系統模型記憶體**，不能據此保證與 Teams 同時開啟時無換頁。兩分鐘合併音訊的冷啟動處理時間為 base 4.75 秒、turbo 17.24 秒；這是離線處理速度，不能直接當作字幕延遲。

額外把五位講者朗讀的**同一段文字**串成 121 秒：turbo 預設跨片段文字記憶時漏字、重複，原始錯字率 38 / 345（11.0%）；以 `-mc 0` 關閉跨片段文字記憶後是 1 / 345（0.3%）。這是刻意重複的測試素材，顯示解碼設定會影響長音訊，不能外推為真實會議準確率。

模型來源：[whisper.cpp 官方模型列表](https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md)。本次 turbo 模型 SHA-1 為 `e050f7970618a659205450ad97eb95a18d69c9ee`，與官方列表相符。

## 即時字幕與繁中翻譯

把一段約 6 秒的公開印度英語送到 BlackHole，再由 `whisper-stream` 連續收音：小模型第一行暫時英文約在開始播放後 2.12 秒出現，之後多次改寫；大模型採 1 秒步進／4 秒窗口時，第一行約 5.04 秒才出現，而且猜成「Thank you」，播放結束後仍沒有產出完整、穩定的一句。改為 2 秒步進／8 秒窗口，約 6.20 秒才出現部分句子。這測的是專案附的簡易串流範例及這組設定，**不能證明優化後的大模型一定無法即時運作**；目前它不能直接當產品字幕引擎。

同一段 BlackHole 錄回的音訊，turbo 以離線短段模式在 2.84 秒完成，18 詞全對；小模型把 `masons` 辨成 `basins`，turbo 則正確辨識。將 turbo 的完整英文句送進 macOS `TranslationSession`，約 3.13 秒得到繁中「木匠和石匠」。另一段 69 詞參考稿分成四句翻譯，每句約 1.03～2.16 秒；整段一次翻譯約 6.81 秒。翻譯前需要合併語音模型切出的半句，且英文錯字會傳遞到中文。Apple 說明此 API [在裝置上翻譯](https://developer.apple.com/documentation/translation/translationsession)。

## 判斷

1. **音訊入口可行：**Core Audio tap 適合正式全域收音；已安裝的 BlackHole 2ch 可作測試或備援。產品仍需權限流程、來源選擇和裝置變更處理。
2. **本機辨識跑得動：**turbo 在這批印度口音朗讀樣本上較準，小模型較快。現成 1 秒步進的 turbo 串流表現不合格；下一步須驗證語音活動切段、暫時字幕與定稿替換的實作，而非直接嵌入 `whisper-stream` 範例。
3. **雙語可行但有延遲：**英文先出、完整句子再翻繁中。實際字幕延遲要用自然會議音訊測；目前沒有 Teams／Zoom／瀏覽器實況、多人重疊或同時跑會議軟體的證據，也沒有與 Groq 同音比較。

## 重現入口

- `prepare_gmu.py`：下載五個授權公開樣本與參考文字到指定的忽略目錄。
- `benchmark.py`：合併 WAV、執行本機 `whisper-cli`、記錄冷啟動時間、常駐記憶體與兩種錯字率；`--max-context 0` 可驗證重複內容的失敗情境。
- `stream_probe.py`：將指定公開 WAV 播到確認過的 BlackHole 裝置，記錄 `whisper-stream` 的文字更新時間；不切換系統輸出。
- `core_audio_tap_probe.swift`：只量測原生全域 tap 的回呼和峰值，不保存音訊。
- `translation_probe.swift`：將 stdin 的英文按句送入本機 `TranslationSession`，記錄每句耗時。

這些腳本是獨立實驗，不會修改現有 Groq 語音輸入流程或偷偷啟用模型切換。

在產品 worktree 根目錄重跑辨識時，先從上述官方模型列表下載模型，然後執行：

```sh
python3 experiments/global_caption_poc/prepare_gmu.py --output build/global-caption-poc/gmu
python3 experiments/global_caption_poc/benchmark.py \
  --manifest build/global-caption-poc/gmu/manifest.json \
  --model build/global-caption-poc/models/ggml-large-v3-turbo-q5_0.bin \
  --max-context 0 --output build/global-caption-poc/gmu-turbo-all-nocontext
```

輸出會寫在忽略的 `build/`，其中 `results.json` 保存參考文字、模型辨識文字、錯字率與耗時；原始音訊不會加入 Git。
