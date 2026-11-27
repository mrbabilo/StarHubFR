import Foundation
import Observation

/// L'édition d'une partie ouverte (A0) : le formulaire, le sac, l'étiquette et
/// la note, et **la** lecture dont ils partent. Gardée par `NavigationStore`,
/// pas par la vue : changer de segment ne perd rien, ouvrir une autre partie
/// repart d'une session neuve.
///
/// La copie de référence du sac est la lecture elle-même (`loaded`) : les
/// `InventoryItem` portent un `UUID`, une seconde lecture compterait toutes
/// les cases comme modifiées. Revers accepté : une case vidée compte 1, même
/// une case déjà vide.
@MainActor @Observable
final class SaveEditSession {
    let save: SaveGameInfo
    var draft: SaveFarmerDraft
    var noteTag: String
    var noteText: String
    /// Le sac édité ; vide jusqu'à l'arrivée de la lecture.
    var inventory: [InventoryItem] = []
    /// Les coffres lus avec le sac (A1), édités par l'écran des coffres (A4) ; même référence que le sac.
    var chests: [SaveChest] = []
    /// La lecture d'origine ; `nil` tant qu'elle n'est pas arrivée, ou si elle a échoué.
    private(set) var loaded: SaveContents?
    /// Lue à chaque décompte, pas figée : le choix d'un avatar enregistre la
    /// note en cours, qui cesse alors de compter.
    private let notes: SaveNotesStore

    init(save: SaveGameInfo, notes: SaveNotesStore = .shared) {
        self.save = save
        self.notes = notes
        draft = SaveFarmerDraft(save)
        let note = notes.note(for: save.folderName)
        noteTag = note.tag
        noteText = note.note
    }

    /// Pose la lecture : la référence et le sac édité en partent ensemble.
    func load(_ contents: SaveContents) {
        loaded = contents
        inventory = contents.inventory
        chests = contents.chests
    }

    /// L'empreinte que l'écriture doit retrouver : celle de la lecture, dès que le
    /// sac ou un coffre est modifié, sauf écrasement confirmé.
    func expectedStamp(overwriteNewer: Bool) -> SaveDocument.Stamp? {
        overwriteNewer || changedSlots + changedChestSlots == 0 ? nil : loaded?.stamp
    }

    /// Modifications non enregistrées : champs de la fiche, cases du sac et des coffres, étiquette et note.
    var changeCount: Int {
        let note = notes.note(for: save.folderName)
        return draft.changedFields(from: SaveFarmerDraft(save)) + changedSlots + changedChestSlots
            + (noteTag == note.tag ? 0 : 1) + (noteText == note.note ? 0 : 1)
    }

    /// Ce que l'écriture doit porter (`nil` = non modifié) ; la note de l'app s'enregistre à part.
    /// `chests` : les seuls coffres modifiés, par `id`.
    func pendingEdits() -> (sheet: SaveFarmerSheet?, items: [InventoryItem]?, chests: [String: [InventoryItem]]?) {
        let sheet = draft.changedFields(from: SaveFarmerDraft(save)) > 0 ? draft.sheet(for: save) : nil
        let changed = chestChanges.filter { $0.count > 0 }
        let chests = changed.isEmpty ? nil : Dictionary(changed.map { ($0.chest.id, $0.chest.items) }, uniquingKeysWith: { a, _ in a })
        return (sheet, changedSlots > 0 ? inventory : nil, chests)
    }

    private var changedSlots: Int {
        loaded.map { InventoryItem.changedSlots(inventory, from: $0.inventory) } ?? 0
    }

    private var changedChestSlots: Int { chestChanges.reduce(0) { $0 + $1.count } }

    /// Chaque coffre édité et ses cases modifiées, rapproché de sa lecture par `id`, jamais par position.
    private var chestChanges: [(chest: SaveChest, count: Int)] {
        guard let loaded else { return [] }
        let read = Dictionary(loaded.chests.map { ($0.id, $0.items) }, uniquingKeysWith: { a, _ in a })
        return chests.compactMap { chest in
            read[chest.id].map { (chest, InventoryItem.changedSlots(chest.items, from: $0)) }
        }
    }
}
