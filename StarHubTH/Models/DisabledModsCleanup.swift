import Foundation

/// Ce que « Vider les mods désactivés » supprime, et ce qu'on en dit.
///
/// ⚠️ **Suppression définitive, pas la corbeille.** L'enjeu n'est pas
/// théorique : sur le parc de référence, **721 dossiers** sont en pause
/// (mesuré le 2026-09-11) et partiraient tous d'un seul geste. Un résidu
/// système pris pour un mod — ou l'inverse — se paie ici sans retour possible,
/// d'où l'extraction de ce tri hors du ViewModel.
enum DisabledModsCleanup {

    /// Les entrées d'un dossier `Mods/` à supprimer.
    ///
    /// Le scan traite **tout** dossier commençant par un point comme un mod en
    /// pause : sans la garde `OSJunk`, `.Spotlight-V100` et `.Trashes` — des
    /// dossiers du système — seraient emportés par un bouton qui promet de ne
    /// toucher qu'à des mods. C'est le défaut qu'`OSJunk` a déjà corrigé une
    /// fois côté scan, avec quatre copies dont une amputée.
    static func targets(in entries: [String]) -> [String] {
        entries.filter { $0.hasPrefix(".") && !OSJunk.isJunk($0) }
    }

    /// Ce que la passe a fait — et donc ce qu'il faut dire.
    enum Outcome: Equatable, Sendable {
        /// Aucun mod en pause : « supprimés avec succès » ferait croire que le
        /// ménage a eu lieu.
        case nothingFound
        case removed(Int)
        /// Au moins un dossier est resté. Le compte des réussites ne doit pas
        /// masquer l'échec : l'utilisateur croirait son `Mods/` propre.
        case partial(removed: Int, failed: Int)

        /// Rescaner un parc inchangé coûte plusieurs secondes sur ~900 mods —
        /// mais un échec partiel a pu déplacer des dossiers, et l'écran doit
        /// alors refléter le disque, quel qu'il soit.
        var needsRescan: Bool {
            if case .nothingFound = self { return false }
            return true
        }
    }

    static func outcome(removed: Int, failed: Int) -> Outcome {
        if failed > 0 { return .partial(removed: removed, failed: failed) }
        return removed == 0 ? .nothingFound : .removed(removed)
    }
}
