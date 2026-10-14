# Windows 驗證與交接

本檔區分自動驗證與真實 Windows 桌面驗收；建置成功不代表真實麥克風或所有 App 已驗收。

## 本輪範圍

新增獨立 Windows 程式與安裝流程。以 macOS 桌面版的語言、文字、詞典、錄音生命週期與安全交付規則為參考；既有 Mac 程式、安裝、金鑰與 iPhone 協定不變。

核心狀態：Idle → Starting → Recording → Finalizing → Transcribing → Delivering → Idle。失敗可轉 RetainedAudio，兩分鐘到期清理。每次工作擷取設定快照與目標，取消使過期回覆失效。音訊／HTTP／交付介面可注入假實作測試，沒有把 Windows APIs 放進核心狀態機。

影響風險主要為 OS 麥克風、剪貼簿與 UI Automation 輸入投遞；不模擬 Enter、不提升權限，無法驗證時降級只複製。詞典只保存短詞差異，不用整份文件讀取補救範圍失敗。

## 自動驗證

待 Windows CI 實跑後補入結果。原 Mac 基線文字測試通過；本機交叉編譯 Windows App 通過。此兩項不能代替 Windows 原生執行驗證。

## 實機未驗項目

- Windows 11／Windows 10 22H2 的實體麥克風、USB／藍牙耳機與隱私權拒絕流程。
- Notepad、Chrome／Edge、Word、LINE／ChatGPT 等實際軟體的語音→貼上→修字學習。
- 中文 IME 組字、部分 App 不完整的 UI Automation provider、多螢幕 DPI 與螢幕閱讀器。
- 使用者自行建立金鑰後的真實 Groq 辨識與延遲。本輪不讀或傳送任何真實金鑰／日常錄音。
- ARM64；未簽章下載檔在不同校園裝置政策／Windows 信譽防護下的安裝體驗。

## 發布判準

Windows 建置、離線回歸、受控 UI 測試與安裝／升級／解除安裝流程皆須有直接結果，安裝檔小於 20 MB、附 SHA-256 及 payload 清單。尚未驗證的實機項目隨測試版發布，不能標示完全功能對等或正式版。
