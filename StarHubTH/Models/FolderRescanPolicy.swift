import Foundation

/// Les dates de modification des deux dossiers que l'Accueil surveille, prises
/// au dernier scan du parc.
///
/// La date d'un dossier change quand une entrée y est ajoutée, retirée ou
/// renommée : mod installé, supprimé ou mis en pause (préfixe point) dans le
/// Finder, partie copiée ou supprimée. Elle ne change **pas** quand un fichier
/// change à l'intérieur d'un mod : ce cas passe par « Actualiser la liste des
/// mods » (⇧⌘R).
public struct FolderStamps: Equatable, Sendable {
    public let mods: Date?
    public let saves: Date?

    public init(mods: Date?, saves: Date?) {
        self.mods = mods
        self.saves = saves
    }

    /// Le dossier des parties du jeu sur macOS — partagé avec `SaveManager`.
    public static let savesDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/StardewValley/Saves")

    /// Les deux dossiers d'un dossier de jeu.
    public static func read(gameDir: String) -> FolderStamps {
        read(mods: URL(fileURLWithPath: gameDir).appendingPathComponent("Mods"), saves: savesDirectory)
    }

    /// Deux lectures d'attributs, sans parcourir les dossiers. `nil` pour un
    /// dossier illisible ou absent (disque externe du parc démonté).
    public static func read(mods: URL, saves: URL) -> FolderStamps {
        func date(_ url: URL) -> Date? {
            do {
                return try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            } catch {
                return nil  // absent ou illisible : une valeur comparable, pas une panne
            }
        }
        return FolderStamps(mods: date(mods), saves: date(saves))
    }
}

/// N-04, préalable : faut-il rescanner le parc en arrivant sur l'Accueil ?
///
/// Mesuré le 2026-10-18 sur le parc réel (966 mods), app au repos : chaque
/// arrivée sur l'Accueil coûtait 13,3 s de CPU et ~28 s d'activité, contre
/// 1,8 s pour une autre page. Le lancement scanne déjà (`performInitialLoad`),
/// et les gestes de l'app (bascule, installation) rescannent eux-mêmes ; ne
/// reste à rattraper que ce qui change hors de l'app.
public enum FolderRescanPolicy {
    /// `last` vaut `nil` tant qu'aucun scan n'est daté (lancement en cours,
    /// dossier de jeu pas choisi) : le chargement s'en charge, pas l'Accueil.
    public static func needsRescan(last: FolderStamps?, now: FolderStamps) -> Bool {
        guard let last else { return false }
        return last != now
    }
}
