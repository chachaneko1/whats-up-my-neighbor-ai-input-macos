# What's up my neighbor AI Input — repository migration

2026-10-18：macOS 與 Windows 各自維護、測試及發佈。

- Mac：https://github.com/yuipan0611/whats-up-my-neighbor-ai-input-macos，由原 repo 原地改名，保留歷史、Issues、Releases 與簽章設定。
- Windows：https://github.com/yuipan0611/whats-up-my-neighbor-ai-input-windows，從原始 `main` 的 `eceb1b508af83446431244741263d79e0903f911` 抽取 Windows 相關歷史並提升至根目錄。提交對照見 Windows repo 的 `migration-commit-map.txt`。
- Mac 目前程式樹不再包含 Windows 原始碼與 CI；原 Git 歷史及既有 Windows beta 發佈仍保留。未重寫 Mac 歷史，因此舊 clone 容量不會因拆分立即縮小。
- App 名稱、bundle ID、Keychain service、快捷鍵、個人設定與黑貓素材不變；此次不提高 App 版本、不安裝更新。

## 舊版更新相容

已安裝版本仍使用 `https://github.com/yuipan0611/groq-ai-voice-input-macos/releases/latest/download/appcast.xml`。GitHub 改名轉址須保留，不可重新使用舊 repo 名稱。既有 appcast、安裝包及簽章維持原樣；未來版本使用新的 Mac repo 網址。

新建置的發佈驗證預設只接受新網址。只在核對既有不可變發佈附件時，設定 `NEIGHBOR_ALLOW_LEGACY_REPOSITORY=1` 才允許原網址；仍須通過 bundle、版本、同一 repo 的安裝檔 URL、SHA-256、程式碼簽章與 Sparkle Ed25519 簽章檢查。

Windows repo 的 beta 附件為舊版原樣搬遷，保留原始提交與 CI 證據；實機未驗收項目繼續揭露。兩平台之後可分別發版，Windows 不影響 Mac 的 latest 更新清單。
