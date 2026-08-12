import Foundation

/// Décide si l'identifiant Nexus d'une installation doit être retenu pour le
/// dossier installé.
///
/// Quand un mod arrive par Nexus — lien `nxm://` ou téléchargement intégré —
/// l'app connaît son identifiant. Elle s'en servait pour réconcilier la version
/// puis pour retirer la ligne de mise à jour, et le jetait. Un mod dont l'auteur
/// a oublié `UpdateKeys` dans son `manifest.json` devenait donc invisible aux
/// vérifications suivantes, définitivement et sans le moindre signal.
///
/// La règle est volontairement avare : le manifeste fait foi (c'est ce que SMAPI
/// lit pour ses propres mises à jour) et une saisie manuelle ne se fait pas
/// écraser par une installation.
public enum NexusInstallIdRecording {

    /// - Parameters:
    ///   - downloadedModId: L'identifiant de la page Nexus d'où vient l'archive.
    ///   - manifestUpdateKeys: Le champ `UpdateKeys` du manifeste installé.
    ///   - existingOverride: L'identifiant déjà assigné à la main à ce dossier.
    /// - Returns: L'identifiant à retenir, ou `nil` s'il ne faut rien écrire.
    public static func idToRecord(downloadedModId: Int,
                                  manifestUpdateKeys: [String]?,
                                  existingOverride: String?) -> String? {
        // Un `nxm://` malformé ou un champ non renseigné : écrire ferait
        // interroger une page qui n'existe pas à chaque vérification.
        guard downloadedModId > 0 else { return nil }

        // Le manifeste fait foi. `parseNexusId` porte déjà les cas tordus —
        // suffixe `@variant`, espaces, id non numérique — et ne rend un
        // identifiant que s'il est réellement exploitable.
        if ModManifest.parseNexusId(fromUpdateKeys: manifestUpdateKeys) != nil { return nil }

        // Une saisie manuelle est un choix de l'utilisateur ; une installation
        // ne l'écrase pas. Un champ vidé n'en est pas une.
        if let existing = existingOverride,
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }

        return String(downloadedModId)
    }
}
