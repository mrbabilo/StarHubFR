import Foundation
import Observation

/// Le domaine Sauvegardes (cadrage §4, domaine 1) : la liste des parties, les
/// trois préférences d'affichage de l'onglet, et le verrou qui empêche deux
/// écritures concurrentes.
///
/// « Ce qui n'est pas à moi arrive en paramètre » : l'étiquette d'une
/// sauvegarde vit dans `SaveNotesStore` (préférences), et le store la reçoit
/// en **closure** — il ne connaît ni le magasin, ni L10n, ni AppKit. La
/// lecture se fait à l'appel : le suivi d'observation traverse donc jusqu'au
/// magasin de notes quand un rendu lit `hierarchy`.
///
/// L'orchestration d'I/O (lecture du disque, écriture d'une sauvegarde, les
/// backups) reste au ViewModel pour l'instant et mute ce store par
/// `replace(saves:)` / `beginOperation()` / `endOperation()`.
@Observable
final class SavesStore {

    /// Les parties trouvées sur le disque, telles que `SaveManager.fetchSaves`
    /// les rend. Remplacée en bloc — jamais mutée élément par élément.
    private(set) var saves: [SaveGameInfo] = []

    /// Liste ou grille.
    var viewMode: SaveViewMode = .list
    /// Le tri des racines **et** des enfants (`SaveTree.build`).
    var sortOption: SaveSortOption = .lastPlayed
    /// L'étiquette filtrée, `""` = aucune.
    var filterTag: String = ""

    /// Vrai pendant qu'une écriture de sauvegarde (suppression, duplication,
    /// backup, restauration) tourne en tâche de fond.
    ///
    /// Ces opérations bloquaient le fil principal, ce qui empêchait par
    /// accident un second clic. Une fois asynchrones, le bouton reste vivant :
    /// sans ce drapeau, deux clics sur « Dupliquer » lanceraient deux copies
    /// concurrentes du même dossier.
    private(set) var isOperationRunning = false

    @ObservationIgnored private let tagForSave: (String) -> String

    init(tagForSave: @escaping (String) -> String) {
        self.tagForSave = tagForSave
    }

    func replace(saves: [SaveGameInfo]) {
        self.saves = saves
    }

    // MARK: - Le verrou d'écriture

    /// Prend le verrou, ou rend `false` s'il est déjà tenu. Test-et-pose en
    /// **une** opération : les huit appelants l'écrivaient en deux temps.
    func beginOperation() -> Bool {
        if isOperationRunning { return false }
        isOperationRunning = true
        return true
    }

    /// Relâche le verrou. Idempotent — un `endOperation()` de trop ne fait rien
    /// de mal, mais un manquant fige l'onglet : chaque `beginOperation()` qui a
    /// rendu `true` doit avoir le sien sur **tous** ses chemins de sortie.
    func endOperation() {
        isOperationRunning = false
    }

    // MARK: - Ce que l'onglet affiche

    /// L'arbre des sauvegardes tel qu'il s'affiche.
    ///
    /// La filiation et le tri vivent dans `SaveTree` ; ne reste ici que le
    /// filtre par étiquette, qui s'applique **aux racines seulement** —
    /// comportement historique, conservé à l'extraction.
    var hierarchy: [SaveNode] {
        var roots = SaveTree.build(from: saves, sortedBy: sortOption)
        if !filterTag.isEmpty {
            roots = roots.filter { tagForSave($0.info.folderName) == filterTag }
        }
        return roots
    }

    /// Les étiquettes proposables, dédoublonnées et triées. Parcourt `saves`
    /// et non l'arbre : une étiquette posée sur un enfant reste proposable.
    var availableFilterTags: [String] {
        let allTags = saves.map { tagForSave($0.folderName) }.filter { !$0.isEmpty }
        return Array(Set(allTags)).sorted()
    }
}
