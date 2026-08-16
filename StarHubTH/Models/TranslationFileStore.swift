import Foundation

/// Poser un fichier de traduction sur le disque.
///
/// Ce fichier est le travail du traducteur : une écriture interrompue à
/// mi-chemin, ou un écrasement sans filet, lui coûte des heures. D'où le `.tmp`
/// puis le remplacement, et le `.bak` de l'état précédent — le même motif que
/// `ModConfigBackupManager`, pour les mêmes raisons.
public enum TranslationFileStore {

    public enum StoreError: Error, Equatable {
        case writeFailed(String)
    }

    /// Le fichier de secours, à côté du fichier lui-même : `fr.json.bak`.
    ///
    /// Voisin plutôt que dans un dossier à part, pour qu'un traducteur qui
    /// fouille son mod le trouve sans nous.
    public static func backupURL(for url: URL) -> URL {
        url.appendingPathExtension("bak")
    }

    public static func write(_ text: String, to url: URL) throws {
        let fm = FileManager.default

        // Garder l'état précédent avant toute chose. S'il n'y en a pas, il n'y
        // a rien à sauver — et surtout pas de `.bak` vide à créer, qui ferait
        // croire à une version antérieure inexistante et inviterait à
        // « restaurer » vers rien.
        if fm.fileExists(atPath: url.path) {
            let backup = backupURL(for: url)
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        }

        let tmp = url.appendingPathExtension("tmp")
        // Un seul nettoyage pour les deux sorties. Après un déplacement réussi
        // le `.tmp` n'existe plus et le retrait échoue sans conséquence : c'est
        // précisément ce qu'un `try?` doit couvrir.
        defer { try? fm.removeItem(at: tmp) }

        do {
            try Data(text.utf8).write(to: tmp, options: .atomic)
            // `replaceItemAt` demande une destination existante ; le premier
            // enregistrement d'un fichier neuf passe donc par un déplacement.
            if fm.fileExists(atPath: url.path) {
                guard (try fm.replaceItemAt(url, withItemAt: tmp)) != nil else {
                    throw StoreError.writeFailed("replaceItemAt")
                }
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }
}
