import Foundation

/// Ce que le système d'exploitation sème dans un dossier et qui n'est pas un mod.
///
/// Cette définition existait en **quatre exemplaires** au 2026-08-01, dont trois
/// identiques et un amputé : le scan des mods ne reconnaissait que `.DS_Store`,
/// `Thumbs.db`, `ehthumbs.db`, `__MACOSX` et le préfixe `._`. Il manquait
/// `Icon\r`, `.Spotlight-V100` et `.Trashes` — or le scan traite tout dossier
/// commençant par un point comme un mod en pause, si bien qu'un
/// `.Spotlight-V100` s'affichait comme un mod désactivé nommé
/// « Spotlight-V100 ». Une seule définition, et le défaut disparaît avec la
/// duplication.
enum OSJunk {
    /// Fichiers déposés par macOS ou Windows. `Icon\r` porte réellement un
    /// retour chariot dans son nom — c'est l'icône personnalisée d'un dossier.
    static let files: Set<String> = [".DS_Store", "Thumbs.db", "ehthumbs.db", "Icon\r"]

    /// Dossiers de métadonnées, à écarter en bloc.
    static let folders: Set<String> = ["__MACOSX", ".Spotlight-V100", ".Trashes"]

    /// Fichiers de fourche de ressources macOS : `._<nom>`.
    static let appleDoublePrefix = "._"

    /// Vrai quand cette entrée de dossier est un résidu du système et non un mod.
    static func isJunk(_ entry: String) -> Bool {
        files.contains(entry) || folders.contains(entry) || entry.hasPrefix(appleDoublePrefix)
    }
}
