# 中文多人會議 Phase 1

獨立、本機研究工具；不改動 Mac App，不讀 Keychain，不上傳音訊。需要 Python 3.11 與 FFmpeg。研究資料與輸出請放在已忽略的 `build/`，不要加入 Git。

## 安裝

```sh
uv venv --python 3.11 build/meeting-venv
uv pip install --python build/meeting-venv/bin/python -r experiments/meeting_phase1/requirements.txt
```

WeSpeaker 公開中文模型來源與官方載入方式見 https://github.com/wenet-e2e/wespeaker/blob/master/docs/python_package.md 。可執行 `python3 -m experiments.meeting_phase1.prepare_wespeaker --output build/meeting-models/wespeaker` 下載並記錄指紋；輸出資料夾必須不存在。或自行將 `avg_model.pt` 與 `config.yaml` 放在該目錄。本工具需要明確的模型路徑，不會自動切換雲端服務。

## 準備公開受控素材

```sh
python3 -m experiments.meeting_phase1.prepare_public_fixture --output build/meeting-fixtures
python3 -m experiments.meeting_phase1.prepare_public_fixture --output build/meeting-fixtures-long --split train --minimum-bytes 384000
```

此命令下載 AISHELL 官方 HF AISHELL-3 的兩位說話者各六段不同錄音，保存來源與 SHA-256；建立交替與分組的非重疊拼接音訊及參考標籤。它不是自然會議。上游 dataset card 的授權資訊也會一併保存，不將音檔提交到 repo。

## 執行

```sh
build/meeting-venv/bin/python -m experiments.meeting_phase1.run \
 --audio build/meeting-fixtures-long/alternating.wav \
 --reference build/meeting-fixtures-long/alternating-reference.json \
 --output build/meeting-runs/long-alternating \
 --diarizer wespeaker --diarizer-model build/meeting-models/wespeaker \
 --asr-model tiny --download-models
```

`--download-models` 只允許下載本機 ASR 權重；不傳送音訊。可改傳本機 faster-whisper 模型資料夾，省略該選項即可要求不下載。ASR 是研究用本機模型，不代表 App 的 Groq large-v3 效果。預設音訊上限兩分鐘，輸出資料夾必須不存在，避免覆蓋舊結果。暫存正規化音訊於結束／失敗時清理，輸出逐字稿由使用者自行保管或刪除。

若已有授權的 pyannote 模型，改用 `--diarizer pyannote --diarizer-model /local/model/path`；pyannote 需另一個獨立且相容的 Python 環境，不要直接覆蓋本基準固定的 Torch 版本。也可在接受模型條件後提供環境 `HF_TOKEN`，以模型 ID 載入。此 adapter 尚未完成本機模型驗證；無存取權時會失敗，不轉送到付費 API。`--speakers 2` 僅適用已知兩位說話者的 pyannote 實驗，WeSpeaker 基準自行估計數量。

## 查看與手動命名

- `review.html`：本機開啟，填 A／B 的姓名。可選擇原音檔、點時間戳播放、修改文字、修正片段說話者，下載修改後 JSON／Markdown。所有修改只在瀏覽器記憶體，離開前必須下載。
- `transcript.json`／`transcript.md`：原自動逐字稿；ID 與顯示姓名分開。
- `diarization.json`、`asr.json`：分段與 ASR 原始輸出，供檢查合併是否誤配。
- `run.json`：模型、版本、輸入指紋、處理時間與受控評分。
- `failure.json`：若失敗，保留階段與原因，不偽造成功結果。

A／B 只在該檔案內依首次出現命名。ASR token 若跨人物邊界、沒有足夠覆蓋或有競爭說話者，就標 `UNKNOWN`／需確認；畫面不顯示未校準的「人物信心百分比」。word timestamps 是模型估計，不是人工精準對齊。本版不分離重疊人聲，可能無法還原被蓋住的文字。

## 測試與判讀

```sh
./scripts/test-meeting-phase1.sh
```

測試只需 Python 標準庫，不下載模型、不連網。結果與限制見 [驗證紀錄](../../docs/MEETING_PHASE1_VALIDATION.md)。受控人物純度不是 DER，也不是自然會議通過證明。真人會議穩定性仍需更多獨立音檔與人工標記。

重跑四組已宣告的測試（模型須已下載）：

```sh
build/meeting-venv/bin/python -m experiments.meeting_phase1.benchmark \
 --short-fixtures build/meeting-fixtures --long-fixtures build/meeting-fixtures-long \
 --output build/meeting-rerun --diarizer-model build/meeting-models/wespeaker --asr-model tiny
```

如需排除繁簡字形差異，另執行 `python -m experiments.meeting_phase1.evaluate --run <run目錄> --reference <參考JSON> --output <新的評估JSON>`。此操作不重跑模型，也不覆寫原 CER；數字文字格式仍會計為字元差異。
