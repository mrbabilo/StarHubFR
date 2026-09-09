import Foundation

/// Le répertoire de données de l'application, et lui seul.
///
/// **Un seul endroit qui le construit.** Il en existait d'abord six, chacun
/// répétant `appendingPathComponent("StarHubTH")` — c'est la forme exacte que
/// ce dépôt a déjà payée : des copies qui divergent, et un renommage qui en
/// oublie une. Re-compté le 2026-09-10, ils sont quatorze (sept stores de plus
/// depuis le plan) : la tâche 4 les branche tous ici.
///
/// `Backups/` n'en fait délibérément pas partie : voir
/// `ModInstallBackupManager`.
public enum AppSupport {
    /// Le nom du dossier. `StarHubFR` et non `StarHubTH` : l'application
    /// d'origine, dont ce dépôt est un fork, écrit encore dans le second
    /// (`StarHubTH_debug.log` et `Avatars/`, vérifié sur son dépôt le
    /// 2026-08-26). Les deux installées côte à côte se marcheraient dessus.
    static let folderName = "StarHubFR"
    static let legacyFolderName = "StarHubTH"

    /// Le répertoire, créé s'il manque. `nil` quand le système ne rend aucun
    /// dossier de support — cas où l'app ne peut de toute façon rien persister.
    public static let directory: URL? = resolve()

    private static func resolve() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let target = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }
}
