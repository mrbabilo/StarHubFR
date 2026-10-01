import Foundation

/// Sonde en tête de l'ordre de chargement de SMAPI (`ModsToLoadEarly`, spec
/// 2026-10-01 § 4) : jamais sans consentement ; présente si et seulement si
/// l'auteur a consenti **et** la sonde est active — un identifiant listé mais
/// absent fait écrire à SMAPI un WARN à chaque lancement.
public enum ProbeLoadOrder {
    /// Ce que `sync` a fait. `failed` : la sonde voulue n'a pas pu être
    /// (dé)placée — SMAPI absent, fichier illisible, liste exotique, écriture
    /// refusée. Distinct de `unchanged`, sinon l'échec reste muet.
    public enum SyncOutcome: Equatable, Sendable { case unchanged, written, failed }

    /// L'état montré à l'auteur, déduit du **fichier** et du dernier lancement
    /// mesuré — pas de la dernière action de l'app : un lancement par Steam ne
    /// passe jamais par `launchGame`.
    public enum Status: Equatable, Sendable {
        /// Jamais demandé (`consent == nil`).
        case notAsked
        /// Refusé : jamais redemandé.
        case declined
        /// Listée, et le dernier lancement l'a vue en tête.
        case active
        /// Listée, pas encore vue en tête par un lancement.
        case pending
        /// Voulue mais absente du fichier : l'écriture a échoué.
        case notApplied
        /// Consentie, sonde en pause : retirée, elle reviendra à sa réactivation.
        case probePaused
        /// Pas de dossier `smapi-internal` : rien à dire sur le fichier.
        case smapiMissing
    }

    /// nil : jamais demandé, ne rien toucher.
    public static func wanted(consent: Bool?, probeActive: Bool) -> Bool? {
        guard let consent else { return nil }
        return consent && probeActive
    }

    /// La sonde est-elle installée et active ? Seule définition : `launchGame`,
    /// la carte et son état passent tous par ici.
    public static func isProbeActive(in mods: [ModItem]) -> Bool {
        mods.contains { $0.isEnabled && $0.components.contains {
            $0.uniqueId.caseInsensitiveCompare(BenchmarkSides.probeId) == .orderedSame } }
    }

    public static func configURL(gameDir: String) -> URL {
        URL(fileURLWithPath: gameDir).appendingPathComponent("smapi-internal/config.user.json")
    }

    /// nil : pas de `smapi-internal` (ou `gameDir` vide) ; sinon, la sonde
    /// est-elle listée dans `ModsToLoadEarly` ?
    public static func listed(gameDir: String) -> Bool? {
        guard !gameDir.isEmpty else { return nil }
        let url = configURL(gameDir: gameDir)
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { return nil }
        return SmapiUserConfig.listsLoadEarly(try? String(contentsOf: url, encoding: .utf8), modId: BenchmarkSides.probeId)
    }

    public static func status(consent: Bool?, probeActive: Bool, listed: Bool?, lastLaunchFirst: Bool?) -> Status {
        guard let consent else { return .notAsked }
        guard consent else { return .declined }
        guard let listed else { return .smapiMissing }
        guard probeActive else { return .probePaused }
        guard listed else { return .notApplied }
        return lastLaunchFirst == true ? .active : .pending
    }

    /// Copie `config.user.json.starhubfr.bak` avant la première écriture ;
    /// un fichier présent mais illisible n'est jamais touché — le lire comme
    /// vide l'écraserait sans copie.
    @discardableResult
    public static func sync(gameDir: String, consent: Bool?, probeActive: Bool) -> SyncOutcome {
        guard !gameDir.isEmpty, let present = wanted(consent: consent, probeActive: probeActive) else { return .unchanged }
        let url = configURL(gameDir: gameDir)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.deletingLastPathComponent().path) else { return present ? .failed : .unchanged }
        let current: String?
        if fm.fileExists(atPath: url.path) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .failed }
            current = text
        } else {
            current = nil
        }
        guard let updated = SmapiUserConfig.settingLoadEarly(current, modId: BenchmarkSides.probeId,
                                                             present: present) else {
            // nil : rien à changer, ou texte que l'on refuse de réécrire.
            return SmapiUserConfig.listsLoadEarly(current, modId: BenchmarkSides.probeId) == present ? .unchanged : .failed
        }
        let backup = url.appendingPathExtension("starhubfr.bak")
        do {
            if let current, !fm.fileExists(atPath: backup.path) {
                try current.write(to: backup, atomically: true, encoding: .utf8)   // sans copie, pas d'écriture
            }
            try updated.write(to: url, atomically: true, encoding: .utf8)
            return .written
        } catch {
            return .failed
        }
    }
}
