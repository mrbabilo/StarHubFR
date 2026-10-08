import Foundation
import Observation

/// R5 — l'historique des états d'activation, persisté dans
/// `activation_history.json`.
///
/// Dossier injecté, sans valeur par défaut (patron `BisectionSnapshotStore`) :
/// aucun test ne peut écrire dans le vrai Application Support. Un fichier
/// illisible est **mis de côté**, jamais écrasé : il porte peut-être des
/// instantanés épinglés.
@MainActor
@Observable
final class ActivationHistoryStore {
    static let fileName = "activation_history.json"

    private(set) var history: ActivationHistory
    var snapshots: [ActivationSnapshot] { history.snapshots }
    /// La dernière écriture ou lecture ratée, montrée par la section : un
    /// historique qui ne se sauve plus ne doit pas se taire.
    private(set) var failure: String?

    private let directory: URL?

    init(directory: URL?) {
        self.directory = directory
        (history, failure) = Self.load(from: directory)
    }

    func record(_ gesture: ActivationSnapshot.Gesture, detail: String?, mods: [ModItem],
                activeProfileId: UUID?, now: Date = Date()) {
        history.record(.capture(gesture: gesture, detail: detail, mods: mods,
                                activeProfileId: activeProfileId, now: now), now: now)
        save()
    }

    func setPinned(_ id: UUID, _ pinned: Bool) {
        history.setPinned(id, pinned)
        save()
    }

    private func save() {
        guard let directory else { return }
        let url = directory.appendingPathComponent(Self.fileName)
        do {
            try JSONEncoder().encode(history).write(to: url, options: .atomic)
            failure = nil
        } catch {
            failure = "\(url.path): \(error.localizedDescription)"
        }
    }

    private static func load(from directory: URL?) -> (ActivationHistory, String?) {
        guard let directory else { return (ActivationHistory(), nil) }
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return (ActivationHistory(), nil) }
        do {
            return (try JSONDecoder().decode(ActivationHistory.self, from: Data(contentsOf: url)), nil)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = directory.appendingPathComponent("activation_history.unreadable-\(stamp).json")
            do {
                try FileManager.default.moveItem(at: url, to: aside)
                return (ActivationHistory(), nil)
            } catch {
                return (ActivationHistory(), "\(url.path): \(error.localizedDescription)")
            }
        }
    }
}
