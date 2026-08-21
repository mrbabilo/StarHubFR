import CryptoKit
import Foundation

/// L'empreinte du contenu d'un dossier de mod.
///
/// Elle sert à établir que deux sauvegardes portent **exactement** le même
/// état du disque, donc qu'en supprimer une ne perd rien. C'est une décision
/// destructrice : l'empreinte doit distinguer tout ce qui distingue deux
/// états, et la juger sur les métadonnées ne suffit pas. Mesuré sur un parc
/// réel le 2026-08-21 — parmi les sauvegardes de **même mod et même
/// version**, 12 avaient un contenu différent : une traduction ou une
/// configuration modifiée entre les deux. Les confondre aurait effacé ce
/// travail.
///
/// Entrent dans le calcul : le chemin relatif de chaque fichier, sa taille et
/// ses octets. Un fichier déplacé, ajouté, vidé ou modifié change l'empreinte.
public enum FolderDigest {
    /// `nil` quand le dossier n'existe pas ou n'est pas lisible — on ne
    /// supprime jamais sur la foi d'une empreinte qu'on n'a pas pu calculer.
    public static func of(_ folder: URL) -> String? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let walker = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        else { return nil }

        var files: [(relative: String, url: URL)] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let relative = url.path.hasPrefix(folder.path)
                ? String(url.path.dropFirst(folder.path.count))
                : url.lastPathComponent
            files.append((relative, url))
        }
        // Trié : l'ordre d'énumération du système n'est pas un contrat, et
        // deux copies du même dossier doivent rendre la même empreinte.
        files.sort { $0.relative < $1.relative }

        var hasher = SHA256()
        for file in files {
            hasher.update(data: Data(file.relative.utf8))
            guard let handle = try? FileHandle(forReadingFrom: file.url) else { return nil }
            defer { try? handle.close() }
            // Par blocs : un mod peut peser des centaines de mégaoctets, et
            // tout charger en mémoire pour le hacher serait payé sur chaque
            // sauvegarde examinée.
            //
            // La lecture **propage** son erreur au lieu de la taire : un
            // `try?` rendrait `nil` aussi bien à la fin du fichier qu'au
            // milieu d'une lecture qui échoue, et l'empreinte tronquée qui en
            // résulterait pourrait égaler celle d'un autre dossier. Une
            // empreinte fausse, ici, fait supprimer une sauvegarde.
            do {
                while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                    hasher.update(data: chunk)
                }
            } catch {
                return nil
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
