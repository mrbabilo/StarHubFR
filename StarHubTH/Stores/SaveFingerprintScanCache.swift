import Foundation

/// Le dernier scan d'empreintes d'une sauvegarde, **partagé par les sections
/// de sa fiche** (A1-T6 « mods en pause », A1-T9 « mods disparus ») : lire et
/// scanner 37 Mo de XML a été mesuré à ~10 s (Zofia, 2026-09-23) — les
/// sections d'une même fiche ne doivent pas le payer deux fois.
///
/// Une entrée suffit : une seule fiche de sauvegarde est affichée à la fois,
/// et l'ancienne entrée redeviendrait de toute façon un simple re-scan. Les
/// demandes **concurrentes** (les sections montent ensemble au premier
/// affichage) partagent le même travail en cours au lieu de lire deux fois.
actor SaveFingerprintScanCache {
    static let shared = SaveFingerprintScanCache()

    private struct Key: Hashable {
        let folderName: String
        let modified: Date
    }

    private var cache: (key: Key, scan: SaveFingerprintScan?)?
    private var enCours: [Key: Task<SaveFingerprintScan?, Never>] = [:]

    /// Le scan de la sauvegarde nommée, ou `nil` si elle est illisible —
    /// l'appelant affiche « illisible », rien n'est inventé.
    func scan(folderName: String, modified: Date, url: URL) async -> SaveFingerprintScan? {
        let key = Key(folderName: folderName, modified: modified)
        if let hit = cache, hit.key == key { return hit.scan }
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
        cache = (key, resultat)
        return resultat
    }
}
