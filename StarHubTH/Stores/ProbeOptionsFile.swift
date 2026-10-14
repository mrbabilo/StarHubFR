import Foundation

/// Le `config.json` de la sonde, lu et réécrit par la fiche sonde
/// (`ProbeOptionsSection`) et l'onglet Performances (mini-stats) : un seul
/// chemin, une seule écriture propre (`ProbeOptions.rewritten`).
enum ProbeOptionsFile {
    enum Loaded: Equatable {
        case options(ProbeOptions)
        /// Présent mais illisible : « réparer » réécrit depuis les valeurs affichées.
        case corrupted
        /// Pas de dossier du jeu, pas de sonde, ou pas encore de `config.json`
        /// (créé au premier lancement de la sonde).
        case unavailable
    }

    static func url(gameDir: String, presence: ModPresence) -> URL? {
        guard !gameDir.isEmpty else { return nil }
        let modsRoot = URL(fileURLWithPath: gameDir, isDirectory: true).appendingPathComponent("Mods", isDirectory: true)
        return ProbeBundle.target(modsRoot: modsRoot, presence: presence)?.appendingPathComponent("config.json")
    }

    static func load(_ url: URL?) -> Loaded {
        guard let url, let data = FileManager.default.contents(atPath: url.path) else { return .unavailable }
        switch ProbeOptions.read(data) {
        case .success(let options): return .options(options)
        case .failure: return .corrupted
        }
    }

    /// Ouvre les droits (le parc pose parfois ses dossiers en 0555), puis
    /// réécrit canoniquement ; `repair` repart des valeurs passées seules.
    static func write(_ options: ProbeOptions, to url: URL, repair: Bool = false) throws {
        ModZipInstaller.grantOwnerWriteAccess(in: url.deletingLastPathComponent())
        let data = try ProbeOptions.rewritten(
            original: repair ? nil : FileManager.default.contents(atPath: url.path), options: options)
        try data.write(to: url, options: .atomic)
    }
}
