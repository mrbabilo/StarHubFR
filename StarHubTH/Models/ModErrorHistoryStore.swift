import Foundation

/// File-backed persistence for `ModErrorHistory`.
///
/// Lives in Application Support, not Caches: this is accumulated observation
/// the user may consult weeks later, and it can't be rebuilt once the SMAPI log
/// has been overwritten by the next launch. It is kept out of the install
/// registry (UserDefaults) so growing diagnostic data can never endanger the
/// install/profile data the app depends on.
enum ModErrorHistoryStore {
    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("StarHubTH", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mod_error_history.json")
    }

    /// Timestamp of the last SMAPI log folded in, so reloading the same log
    /// (tab switch, refresh button) can't double-count it.
    private struct Payload: Codable {
        var history: ModErrorHistory
        var lastLogDate: Date?
    }

    /// - Parameter url: surcharge du fichier réel. `nil` (par défaut) lit
    ///   `fileURL` ; les tests passent un dossier temporaire pour ne jamais
    ///   toucher à l'historique de l'utilisateur.
    static func load(from url: URL? = nil) -> (history: ModErrorHistory, lastLogDate: Date?) {
        guard let target = url ?? fileURL,
              let data = try? Data(contentsOf: target),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return (ModErrorHistory(), nil) }
        return (payload.history, payload.lastLogDate)
    }

    /// Écrit l'historique. **Rend `false` en cas d'échec**, et l'appelant doit
    /// le dire : cette donnée est accumulée et ne se rebâtit pas (le journal
    /// SMAPI suivant écrase le précédent). Une écriture perdue en silence ne se
    /// verrait qu'au lancement suivant. Même convention que
    /// `ModCompatibilityStore` et `InstalledTranslationStore`.
    ///
    /// - Parameter url: surcharge du fichier réel, même rôle que dans `load`.
    @discardableResult
    static func save(_ history: ModErrorHistory, lastLogDate: Date?, to url: URL? = nil) -> Bool {
        guard let target = url ?? fileURL else { return false }
        let payload = Payload(history: history, lastLogDate: lastLogDate)
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
