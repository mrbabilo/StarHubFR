import Foundation
import Security

/// Un secret du trousseau, désigné par son service et son compte.
///
/// Existait en trois exemplaires dans `NexusUpdateChecker` ; une seconde copie
/// pour DeepL aurait été le motif que ce dépôt a déjà payé — des copies qui
/// divergent. Le type ne connaît ni Nexus ni DeepL : il range une chaîne.
public struct KeychainSecret: Sendable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    /// La clé d'API Nexus, aux identifiants **historiques** : les changer
    /// rendrait illisible une clé déjà enregistrée par une version antérieure.
    public static let nexusApiKey = KeychainSecret(
        service: "com.appleboiy.StarHubTH", account: "nexusApiKey")

    /// La clé d'API DeepL, sous le même service.
    public static let deepLApiKey = KeychainSecret(
        service: "com.appleboiy.StarHubTH", account: "deeplApiKey")

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Rend le statut : sans cela, l'appelant croirait la clé enregistrée
    /// alors que le trousseau a refusé (verrouillé, quota, bac à sable).
    @discardableResult
    public func write(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = baseQuery
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
