import Foundation

/// Où atterrit l'image qu'un joueur choisit comme portrait d'une sauvegarde.
///
/// Le ViewModel copiait l'image dans `Avatars/` en composant le nom en ligne,
/// au milieu de l'ouverture du panneau système : la règle n'était donc pas
/// vérifiable, et elle porte pourtant deux décisions qui comptent.
///
/// **Le nom de fichier est porteur.** `SaveHeroPortrait.resolvedImagePath`
/// retrouve une image dont le chemin absolu a été périmé par un déplacement du
/// dossier de données (F5 a déplacé `Avatars/` de `StarHubTH/` vers
/// `StarHubFR/`) **en cherchant le fichier de même nom** dans le dossier
/// courant. Changer la forme du nom ici casserait cette récupération ailleurs —
/// d'où un test qui l'épingle.
///
/// **Le préfixe dit à qui l'image appartient.** `folderName` est l'identité
/// d'une sauvegarde (`SaveInfo.id` le rend tel quel), donc unique : deux
/// sauvegardes ne peuvent pas se disputer un nom de destination.
public enum CustomAvatarStaging {

    /// Ce qu'il faut faire pour poser l'image choisie.
    public struct Plan: Equatable {
        /// Le fichier à écrire dans le dossier des avatars.
        public let destination: URL
        /// `true` quand un fichier occupe déjà cette place et doit être retiré
        /// avant la copie. Voir `plan(forSave:source:in:fileExists:)`.
        public let replacesExisting: Bool

        public init(destination: URL, replacesExisting: Bool) {
            self.destination = destination
            self.replacesExisting = replacesExisting
        }
    }

    /// Décide du fichier à écrire pour l'image `source`.
    ///
    /// - Parameters:
    ///   - folderName: le dossier de la sauvegarde, qui est son identité.
    ///   - source: l'image choisie par le joueur. Seul son **dernier
    ///     composant** est repris : le chemin d'origine peut pointer n'importe
    ///     où (bureau, volume externe, photothèque) et ne doit rien laisser
    ///     paraître dans le dossier de données.
    ///   - avatarsDirectory: le dossier des avatars. **Arrive en paramètre, et
    ///     ce n'est pas un détail** : `AppSupport.directory` est un
    ///     `static let` à effet de bord dont la simple lecture déclenche la
    ///     reprise des préférences et le déplacement du dossier de données —
    ///     un type de Core qui irait le chercher lui-même ferait migrer
    ///     1,2 Go de sauvegardes réelles à chaque exécution de la suite de
    ///     tests, ce qui est arrivé le 2026-09-10.
    ///   - fileExists: la lecture du disque, injectée pour la même raison.
    public static func plan(forSave folderName: String,
                            source: URL,
                            in avatarsDirectory: URL,
                            fileExists: (URL) -> Bool) -> Plan {
        let destination = avatarsDirectory
            .appendingPathComponent("\(folderName)_\(source.lastPathComponent)")
        return Plan(destination: destination, replacesExisting: fileExists(destination))
    }
}
