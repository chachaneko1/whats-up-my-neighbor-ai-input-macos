# 素材來源與補間

角色參考是負責人較喜歡的 Gemini 八格圖。第一輪離線幾何補間有尾巴／四肢殘影，已捨棄，不用於試玩包。最終素材改由同一 Gemini 對話直接補畫十六格連續姿勢，再本機去背、依眼睛與頭頂定位、打包到原生 NSView。

只在主動操作中切換影格；不需要在執行時生成圖片。原先八格及失敗方案的本機記錄保留以便查閱。

順接 R2 保留原十八張關鍵姿勢，另以 signed-distance 輪廓與個別臉部圖案插值產生六十九張本機播放影格（SmoothFrames/）。每第四格為原圖，頭眼與嘴分開對齊，避免透明度疊加產生雙眼。大幅轉側區間仍是根據二維素材估計的中間輪廓，最終以負責人試玩判斷。smooth_frames.py 只用離線 NumPy／Pillow；正式 App 無新增依賴或網路。smooth-manifest.json 記錄影格雜湊與時間權重。

高幀 R3 使用同一批十八張原始姿勢，將各間隔改為十六份，產出 273 張 DenseFrames；每十六格與原始 PNG 逐檔一致。`smooth_frames.py` 現在重建 DenseFrames 和 dense-manifest.json，舊 SmoothFrames 與 smooth-manifest.json 保留作前版紀錄。只補間已有 Gemini 素材，本輪沒有再次呼叫雲端模型。

R4 改用 Gemini 新畫 32 格。執行 `Direct32/slice_frames.py` 重建直接切分圖，來源、提示詞、逐格變換、邊界與雜湊見 Direct32/manifest.json。播放每格 50ms；不使用 SmoothFrames/DenseFrames，舊素材保留作版本紀錄。
