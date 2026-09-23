import Foundation
import Observation

/// A1-T10 — le fil de conduite du nettoyage d'une sauvegarde (règle F1-T2 :
/// hors VM). Sous le verrou d'écriture des saves (celui d'`editSave`,
/// `duplicateSave`, `restoreBackup`…), et rien ne s'écrit si une étape
/// échoue : calcul du texte nouveau en mémoire (`SaveAbsentModsRemoval`) —
/// rien à retirer, rien de fait, pas même un backup —, backup **vérifié non
/// vide**, écriture atomique BOM préservé.
@MainActor
@Observable
final class SaveCleanupStore {

    enum Raison: Equatable {
        case backup, lecture, écriture, aucuneClé, occupé
    }

    enum Phase: Equatable {
        case idle
        case enCours
        case terminé(supprimées: Int, laissées: Int)
        case échec(Raison)
    }

    private(set) var phase: Phase = .idle

    func nettoyer(save: SaveGameInfo, mods: [ModItem], verrou: SavesStore) async {
        guard verrou.beginOperation() else { phase = .échec(.occupé); return }
        phase = .enCours
        phase = await Task.detached(priority: .userInitiated) {
            Self.exécuter(save: save, mods: mods)
        }.value
        verrou.endOperation()
    }

    /// Le fil entier, hors du fil principal : 37 Mo lus et réécrits.
    nonisolated private static func exécuter(save: SaveGameInfo, mods: [ModItem]) -> Phase {
        let url = save.fileURL
        let manager = SaveManager.shared

        // 1. Lecture + calcul, entièrement en mémoire.
        guard let lu = lire(url) else { return .échec(.lecture) }
        var résultat = SaveAbsentModsRemoval.removing(from: lu.contenu, mods: mods)
        guard !résultat.removedKeys.isEmpty else { return .échec(.aucuneClé) }

        // 2. Backup — le dossier de save copié à côté, puis vérifié.
        guard let backup = manager.backupSaveURL(info: save),
              taille(of: backup.appendingPathComponent(url.lastPathComponent)) > 0
        else { return .échec(.backup) }

        // Le jeu a pu écrire entre la lecture et le backup : on écrit à
        // partir de ce que le backup protège, jamais d'un état antérieur.
        guard let relu = lire(url) else { return .échec(.lecture) }
        if relu.data != lu.data {
            résultat = SaveAbsentModsRemoval.removing(from: relu.contenu, mods: mods)
            guard !résultat.removedKeys.isEmpty else { return .échec(.aucuneClé) }
        }

        // 3. Écriture atomique.
        let hadBOM = relu.hadBOM
        manager.invalidateParseCache()
        do {
            try SaveManager.bytes(Data(résultat.content.utf8), preservingBOM: hadBOM)
                .write(to: url, options: .atomic)
        } catch {
            return .échec(.écriture)
        }
        return .terminé(supprimées: résultat.removedKeys.count,
                        laissées: résultat.untouchedKeys.count)
    }

    /// Les octets, la marque relevée, et le texte sans elle : elle est rendue
    /// à l'écriture.
    nonisolated private static func lire(_ url: URL) -> (data: Data, hadBOM: Bool, contenu: String)? {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { return nil }
        let hadBOM = data.starts(with: [0xEF, 0xBB, 0xBF])
        guard let contenu = String(data: hadBOM ? data.dropFirst(3) : data, encoding: .utf8)
        else { return nil }
        return (data, hadBOM, contenu)
    }

    nonisolated private static func taille(of url: URL) -> Int {
        do {
            let attributs = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributs[.size] as? NSNumber)?.intValue ?? 0
        } catch {
            return 0
        }
    }
}
