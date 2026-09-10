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

    /// Le service **historique**, celui de l'application d'origine. Conservé
    /// comme secours : une clé enregistrée avant le changement d'identifiant y
    /// dort encore, et la perdre obligerait l'utilisateur à la ressaisir.
    public static let legacyService = "com.appleboiy.StarHubTH"

    /// La clé d'API Nexus, sous le service **propre au fork** depuis le
    /// changement d'identifiant de bundle. `read()` retombe sur le service
    /// historique et y **recopie** ce qu'il trouve : le détour ne se rejoue
    /// pas, et l'ancienne entrée reste en place pour l'application d'origine.
    public static let nexusApiKey = KeychainSecret(
        service: "com.mrbabilo.StarHubFR", account: "nexusApiKey")

    /// La clé d'API DeepL, sous le même service.
    public static let deepLApiKey = KeychainSecret(
        service: "com.mrbabilo.StarHubFR", account: "deeplApiKey")

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
              let data = item as? Data else {
            // **Secours sur l'ancien service, une fois.** La clé y a été écrite
            // par une version antérieure au changement d'identifiant de bundle.
            // On la recopie sous le nouveau service pour que ce détour ne se
            // rejoue pas — et on laisse l'ancienne en place : l'application
            // d'origine, si elle est installée, en a encore l'usage.
            guard service != Self.legacyService else { return nil }
            let legacy = KeychainSecret(service: Self.legacyService, account: account)
            guard let inherited = legacy.read() else { return nil }
            _ = write(inherited)
            return inherited
        }
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
