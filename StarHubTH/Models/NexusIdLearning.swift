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
}
