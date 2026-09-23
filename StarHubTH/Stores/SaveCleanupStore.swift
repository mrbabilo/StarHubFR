import Foundation
import Observation

/// A1-T10 — le fil de conduite du nettoyage d'une sauvegarde (règle F1-T2 :
/// hors VM). Dans l'ordre, et rien ne s'écrit si une étape échoue :
/// backup **vérifié non vide**, calcul du texte nouveau en mémoire
/// (`SaveAbsentModsRemoval`), écriture atomique BOM préservé. La section de
/// la fiche se rafraîchit seule : l'écriture change la date du fichier, le
/// cache de scan périme par elle.
@MainActor
@Observable
final class SaveCleanupStore {

    enum Raison: Equatable {
        case backup, lecture, écriture, aucuneClé
    }

    enum Phase: Equatable {
        case idle
        case enCours
        case terminé(supprimées: Int, laissées: Int)
        case échec(Raison)
    }

    private(set) var phase: Phase = .idle

    func nettoyer(save: SaveGameInfo, mods: [ModItem]) async {
        phase = .enCours
        phase = await Task.detached(priority: .userInitiated) {
            Self.exécuter(save: save, mods: mods)
        }.value
    }

    func réinitialiser() { phase = .idle }

    /// Le fil entier, hors du fil principal : 37 Mo lus et réécrits.
    nonisolated private static func exécuter(save: SaveGameInfo, mods: [ModItem]) -> Phase {
        let url = save.fileURL
        let manager = SaveManager.shared

        // 1. Backup — le dossier de save copié à côté, puis vérifié.
        guard let backup = manager.backupSaveURL(info: save),
              taille(of: backup.appendingPathComponent(url.lastPathComponent)) > 0
        else { return .échec(.backup) }

        // 2. Lecture + calcul, entièrement en mémoire. La marque est relevée
        // avant et retirée du texte : elle est rendue à l'écriture.
        let hadBOM = SaveManager.fileStartsWithBOM(at: url)
        let data: Data
        do { data = try Data(contentsOf: url) } catch { return .échec(.lecture) }
        guard let contenu = String(data: hadBOM ? data.dropFirst(3) : data, encoding: .utf8)
        else { return .échec(.lecture) }
        let résultat = SaveAbsentModsRemoval.removing(from: contenu, mods: mods)
        guard !résultat.removedKeys.isEmpty else { return .échec(.aucuneClé) }

        // 3. Écriture atomique.
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

    nonisolated private static func taille(of url: URL) -> Int {
        do {
            let attributs = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributs[.size] as? NSNumber)?.intValue ?? 0
        } catch {
            return 0
        }
    }
}
