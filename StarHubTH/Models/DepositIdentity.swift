import Foundation

/// De quelle page Nexus vient ce qu'on dépose dans un mod — et ce que ce dépôt
/// remplace.
///
/// Extrait de `depositIntoMod` (ViewModel), où quatre `??` chaînés portaient
/// toute la règle au milieu de cent lignes d'I/O. Ce qu'elle décide n'est pas
/// cosmétique : sans identifiant, la fiche du mod affiche « aucune
/// vérification de mise à jour » et attend un rattachement à la main.
public enum DepositIdentity {

    /// Ce qu'on a pu établir de la provenance d'un dépôt.
    public struct Resolved: Equatable, Sendable {
        /// `0` quand rien ne l'identifie.
        public let modId: Int
        /// `""` quand rien ne la porte.
        public let version: String
        /// **La date du dépôt, jamais celle que porte le nom du fichier** :
        /// on sait quand l'utilisateur l'a posée, et tout ce que Nexus a
        /// publié depuis est plus récent. `nil` pour un dépôt non identifié —
        /// sans quoi `isNewer` conclurait « à jour » sur une ligne dont on
        /// ignore la provenance.
        public let updatedAt: Date?

        /// La ligne de registre correspondante.
        ///
        /// Passer par cette fabrique **plutôt que de reconstruire l'identité**
        /// est ce qui garantit que la sonde de doublon et la ligne finalement
        /// gardée parlent de la même chose : deux lectures du même nom qui
        /// divergeraient donneraient une identité au comparateur et une autre
        /// à ce qui est conservé.
        public func entry(hostFolderName: String, sourceName: String,
                          installedAt: Date, files: [String],
                          replacedFiles: [String: String]) -> InstalledTranslation {
            InstalledTranslation(hostFolderName: hostFolderName,
                                 nexusModId: modId,
                                 nexusName: sourceName,
                                 version: version,
                                 updatedAt: updatedAt,
                                 installedAt: installedAt,
                                 files: files,
                                 replacedFiles: replacedFiles)
        }
    }

    /// - Parameters:
    ///   - nexus: la fiche, quand le dépôt vient du navigateur intégré — il
    ///     sait de quelle page l'archive vient, et garde donc la main entière.
    ///   - sourceName: le nom du fichier déposé. Sur un compte gratuit tout
    ///     s'installe à la main, et ce nom porte l'identifiant Nexus six fois
    ///     sur dix sur le parc réel.
    ///   - downloadedModId: l'identifiant que le téléchargement connaissait,
    ///     quand le nom, lui, ne dit rien.
    ///   - now: l'instant du dépôt.
    public static func resolve(nexus: NexusModSearch.Hit?,
                               sourceName: String,
                               downloadedModId: Int?,
                               at now: Date) -> Resolved {
        // **Une seule porte pour la priorité** : l'ordre de ces `??`. Le nom
        // était auparavant lu sous condition (`nexus == nil ? … : nil`), ce
        // qui doublait la règle — et rendait l'ordre insabotable, donc
        // invérifiable : aucun test ne pouvait distinguer les deux gardes.
        // Le nom est désormais toujours lu, et c'est la fiche qui prime parce
        // qu'elle vient de Nexus, pas d'une déduction.
        let learned = NexusArchiveName.parse(sourceName)
        let modId = nexus?.modId ?? learned?.modId ?? downloadedModId ?? 0
        let version = nexus?.version ?? learned?.version ?? ""
        // Un identifiant venu du téléchargement compte autant qu'un
        // identifiant lu dans le nom : dans les deux cas on sait de quelle
        // page l'archive vient, donc la ligne mérite une date.
        let updatedAt = nexus?.updatedAt ?? (modId == 0 ? nil : now)
        return Resolved(modId: modId, version: version, updatedAt: updatedAt)
    }

    /// Ce que ce dépôt remplace, s'il remplace quelque chose.
    ///
    /// Une **traduction** remplace la traduction du mod, quelle qu'elle soit :
    /// il n'y en a qu'une par mod. Une **greffe** ne remplace que la greffe de
    /// même identité — elle n'écarte pas la traduction du même mod, elles ne
    /// déposent pas les mêmes fichiers — sans quoi redéposer un lot laisserait
    /// derrière lui les fichiers de l'ancienne version.
    public static func incumbent(in registry: InstalledTranslationRegistry,
                                 kind: ManifestlessArchive.Kind,
                                 host: String,
                                 probe: InstalledTranslation) -> InstalledTranslation? {
        switch kind {
        case .translation:
            return registry.translation(forHost: host)
        case .addon:
            return registry.addons(forHost: host)
                .first { InstalledTranslationRegistry.sameAddon($0, probe) }
        }
    }
}
