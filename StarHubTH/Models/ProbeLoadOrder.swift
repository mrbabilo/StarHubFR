import Foundation

/// Sonde en tête de l'ordre de chargement de SMAPI (`ModsToLoadEarly`, spec
/// 2026-10-01 § 4) : jamais sans consentement ; présente si et seulement si
/// l'auteur a consenti **et** la sonde est active — un identifiant listé mais
/// absent fait écrire à SMAPI un WARN à chaque lancement.
public enum ProbeLoadOrder {
    /// nil : jamais demandé, ne rien toucher.
    public static func wanted(consent: Bool?, probeActive: Bool) -> Bool? {
        guard let consent else { return nil }
        return consent && probeActive
    }

    public static func configURL(gameDir: String) -> URL {
        URL(fileURLWithPath: gameDir).appendingPathComponent("smapi-internal/config.user.json")
    }

    /// Vrai si le fichier a été écrit. Copie `config.user.json.starhubfr.bak`
    /// avant la première écriture ; un fichier illisible n'est jamais touché.
    @discardableResult
    public static func sync(gameDir: String, consent: Bool?, probeActive: Bool) -> Bool {
        guard !gameDir.isEmpty, let present = wanted(consent: consent, probeActive: probeActive) else { return false }
        let url = configURL(gameDir: gameDir)
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { return false }
        let current = try? String(contentsOf: url, encoding: .utf8)
        guard let updated = SmapiUserConfig.settingLoadEarly(current, modId: BenchmarkSides.probeId,
                                                             present: present) else { return false }
        let backup = url.appendingPathExtension("starhubfr.bak")
        if let current, !FileManager.default.fileExists(atPath: backup.path) {
            try? current.write(to: backup, atomically: true, encoding: .utf8)
        }
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
