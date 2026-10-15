import Foundation
import Security

/// Credentials retain their existing Keychain identity; only successful reads are cached.
final class KeychainStore {
    private let keychainService = "tw.panh.FreeVoiceType.groq"
    private let keychainAccount = "api-key"
    private var cachedAPIKey: String?

    /// 讀取金鑰，成功後在本次執行期間快取。
    ///
    /// 這個 App 使用 ad-hoc 簽章，每次重新建置的程式碼身分（CDHash）都不同，
    /// 鑰匙圈會把它當成另一個程式而要求使用者授權。原本每段錄音會讀兩次
    /// （開始錄音檢查一次、上傳前再讀一次），授權提示因此出現得很頻繁。
    /// 快取後每次啟動最多只會問一次。
    ///
    /// 只快取成功的結果：讀取失敗或使用者取消授權時不寫入快取，下次會重新嘗試。
    /// 快取僅存在記憶體，不寫入任何檔案；金鑰更新時由 `saveAPIKey` 覆蓋。
    func readAPIKey() -> String? {
        if let cachedAPIKey { return cachedAPIKey }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        cachedAPIKey = key
        return key
    }

    func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let updateStatus = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                cachedAPIKey = nil
                throw VoiceTypeError.message("Keychain 錯誤 \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            cachedAPIKey = nil
            throw VoiceTypeError.message("Keychain 錯誤 \(updateStatus)")
        }
        // 使用者更換金鑰後，快取必須立刻跟上，否則會繼續用舊金鑰直到重啟。
        cachedAPIKey = key
    }

}
