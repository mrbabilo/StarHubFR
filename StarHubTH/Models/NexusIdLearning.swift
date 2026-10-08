import Foundation

/// Retient les identifiants Nexus que smapi.io connaît déjà, pour les mods dont
/// le manifeste n'en déclare aucun.
///
/// Chaque vérification de mises à jour reçoit `metadata.nexusID` pour tout mod
/// que la base de compatibilité connaît. L'app ne s'en servait que sur les
/// lignes de mise à jour — pour le bouton de téléchargement — et le jetait
/// partout ailleurs. Conséquence : un mod dont l'auteur a oublié `UpdateKeys`
/// restait sans page Nexus, sans suivi de version et sans recherche de
/// traduction, alors que la réponse portait son identifiant.
///
/// Mesuré sur le parc réel le 2026-08-26 : **148 mods sans clé Nexus dans leur
/// manifeste, dont 30 identifiés par smapi.io**. Dix avaient déjà été
/// renseignés à la main, et les dix concordent exactement — la source est donc
/// fiable là où elle répond. Restent **20 identifiants gratuits perdus**.
///
/// La décision d'écriture n'est pas dupliquée : c'est celle de
/// `NexusInstallIdRecording`, la même que pour une installation venue de Nexus.
/// Le manifeste fait foi, une saisie manuelle ne se fait jamais écraser.
public enum NexusIdLearning {

    /// Un dossier de mod tel que le scan l'a vu. `folderName` est le nom
    /// **logique** (jamais préfixé par un point) : c'est la clé du registre
    /// d'identifiants, qui ne migre pas quand un mod est mis en pause.
    public struct Folder: Equatable, Sendable {
        public let folderName: String
        public let uniqueId: String
        public let updateKeys: [String]

        public init(folderName: String, uniqueId: String, updateKeys: [String]) {
            self.folderName = folderName
            self.uniqueId = uniqueId
            self.updateKeys = updateKeys
        }
    }

    /// - Parameters:
    ///   - knownIds: `UniqueID` → `metadata.nexusID`, tel que smapi.io l'a rendu.
    ///     Un mod absent de la réponse est absent d'ici : ne rien savoir n'est
    ///     pas savoir que le mod n'a pas de page.
    ///   - folders: les dossiers installés, enfants de packs compris.
    ///   - existingOverrides: `folderName` → identifiant déjà assigné.
    /// - Returns: les seules écritures à faire, `folderName` → identifiant.
    ///   Vide quand il n'y a rien de neuf : sans cette avarice, chaque
    ///   vérification réécrirait les préférences à l'identique.
    public static func plan(knownIds: [String: Int],
                            folders: [Folder],
                            existingOverrides: [String: String]) -> [String: String] {
        var plan: [String: String] = [:]
        for folder in folders where !folder.uniqueId.isEmpty {
            guard let id = knownIds[folder.uniqueId] else { continue }
            guard let learned = NexusInstallIdRecording.idToRecord(
                sourceModId: id,
                manifestUpdateKeys: folder.updateKeys,
                existingOverride: existingOverrides[folder.folderName]
            ) else { continue }
            plan[folder.folderName] = learned
        }
        return plan
    }

    /// La page d'un composant de pack à clé **cassée** (`Nexus:???`,
    /// `Nexus:-1`, `-1`), déduite de ses frères : tous les autres mods du
    /// même dossier de tête qui déclarent une page valide déclarent **la
    /// même**. Par `folderName`.
    ///
    /// Audit du 2026-10-08 : 16 composants du parc, chacun devenu vérifiable
    /// sur smapi.io avec la page déduite. Un mod sans clé n'en reçoit pas
    /// (bibliothèque embarquée possible, de version propre), ni un mod hors
    /// pack, ni un pack à plusieurs pages.
    public static func packIds(folders: [Folder]) -> [String: String] {
        func top(_ folder: Folder) -> Substring? {
            folder.folderName.firstIndex(of: "/").map { folder.folderName[..<$0] }
        }
        var pages: [Substring: Set<String>] = [:]
        for folder in folders {
            guard let top = top(folder),
                  let id = ModManifest.parseNexusId(fromUpdateKeys: folder.updateKeys)?.id else { continue }
            pages[top, default: []].insert(id)
        }
        var inferred: [String: String] = [:]
        for folder in folders where SmapiUpdateRequest.hasBrokenKey(folder.updateKeys) {
            guard let top = top(folder), let ids = pages[top], ids.count == 1, let id = ids.first else { continue }
            inferred[folder.folderName] = id
        }
        return inferred
    }
}
