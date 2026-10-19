# 遠端分身獨立預覽

本機示範原型，非正式 App 更新。三家 AI 均待遠端驗證。

從此分支根目錄執行：

```sh
./Previews/RemoteAgent/build-preview.sh
open "$PWD/build/remote-agent-preview/遠端分身預覽.app"
```

1. 點「填入範例」或自行輸入文字。
2. 選擇 AI 標籤；三種選項都使用相同固定示範，不會呼叫模型。
3. 點「執行示範」或按 ⌘ Return，約五秒後顯示結果。
4. 執行中可按「取消示範」或 Esc。取消不會產生完成結果。

示範不連網、不開瀏覽器、不控制桌面、不建立備忘錄、不錄音。任務與結果只存在記憶體；結束預覽即清除。只保存選擇的 AI 名稱於：

`~/Library/Application Support/tw.panh.NeighborRemoteAgentPreview/preferences.json`

預覽不註冊全域快捷鍵、不建立登入啟動項目、不讀取正式 App 的 Keychain／設定。使用現有核准 App 圖示，沒有改動圖片。

## 驗證

```sh
./scripts/test-agent-core.sh
./scripts/test-agent-preview.sh
```

重現六種原生畫面（只繪製本 App，不擷取桌面）：

```sh
"build/remote-agent-preview/遠端分身預覽.app/Contents/MacOS/NeighborRemoteAgentPreview" \
  --render-previews "$PWD/build/remote-agent-preview/renders"
```

SSH 通道層的程式與測試會在第三階段加入；面板沒有真實連線入口。整體驗收及後續事項見 `docs/REMOTE_AGENT_PREVIEW.md`。
