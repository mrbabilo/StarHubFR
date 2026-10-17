import Foundation

/// Le dernier scan d'empreintes d'une sauvegarde, **partagé par les sections
/// de sa fiche** (A1-T6 « mods en pause », A1-T9 « mods disparus ») : lire et
/// scanner 37 Mo de XML a été mesuré à ~10 s (Zofia, 2026-09-23) — les
/// sections d'une même fiche ne doivent pas le payer deux fois.
///
/// Une entrée **par sauvegarde** (2026-10-17) : la vérification avant mise
/// en pause (`SaveFingerprintPauseStore`) relit toutes les parties à chaque
/// geste, et une seule entrée lui faisait repayer ~10 s par partie, sans
/// rien à l'écran. Une entrée vaut tant que la save n'est pas réécrite (date
/// de modification). Les demandes **concurrentes** (les sections montent
/// ensemble au premier affichage) partagent le même travail en cours au lieu
/// de lire deux fois.
actor SaveFingerprintScanCache {
    static let shared = SaveFingerprintScanCache()

    private struct Key: Hashable {
        let folderName: String
        let modified: Date
    }

    private var cache: [String: (key: Key, scan: SaveFingerprintScan?)] = [:]
    private var enCours: [Key: Task<SaveFingerprintScan?, Never>] = [:]

    /// Le point d'entrée des appelants : le cache partagé, sans qu'ils
    /// aient à nommer l'instance.
    static func scan(folderName: String, modified: Date, url: URL) async -> SaveFingerprintScan? {
        await shared.scan(folderName: folderName, modified: modified, url: url)
    }

    /// Le scan de la sauvegarde nommée, ou `nil` si elle est illisible —
    /// l'appelant affiche « illisible », rien n'est inventé.
    func scan(folderName: String, modified: Date, url: URL) async -> SaveFingerprintScan? {
        let key = Key(folderName: folderName, modified: modified)
        if let hit = cache[folderName], hit.key == key { return hit.scan }
        if let tache = enCours[key] { return await tache.value }
        let tache = Task.detached(priority: .userInitiated) { () -> SaveFingerprintScan? in
            // Illisible → nil : l'appelant affiche « illisible », rien n'est
            // inventé. Le do/catch (et non `try?`) garde la cause dans le
            // journal de débogage (§7.1).
            do {
                return SaveFingerprintScanner.scan(try Data(contentsOf: url))
            } catch {
                return nil
            }
        }
        enCours[key] = tache
        let resultat = await tache.value
        enCours[key] = nil
        cache[folderName] = (key, resultat)
        return resultat
    }
}
