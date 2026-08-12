import Foundation

/// Quand l'app a-t-elle le droit d'affirmer une version installée ?
///
/// Chaque règle rend une ancre **ou `nil`** — et `nil` veut dire « ne rien
/// écrire », jamais « effacer ». L'appelant qui reçoit `nil` laisse l'ancre
/// existante en place.
public enum ModVersionAnchorRules {

    /// Après une installation menée par l'app.
    ///
    /// `isReferenceFile` distingue le fichier principal d'un optionnel. Poser
    /// un optionnel d'un pack ne dit rien de la version de son cœur : on
    /// enregistre les faits Nexus, on ne touche pas à la version affirmée.
    /// Sans cette réserve, installer une traduction de Swim Mod éteindrait la
    /// mise à jour du mod principal.
    ///
    /// `facts` est **optionnel** : le lot A ne va pas chercher `files.json` et
    /// ignore donc le vrai `file_id` et sa date de mise en ligne. Inventer des
    /// valeurs ferait déclencher à tort la règle de re-publication sur toute
    /// page mise à jour après l'installation. `nil` dit « je ne sais pas », et
    /// ce qu'on ne sait pas ne s'écrit pas.
    public static func afterInstall(existing: ModVersionAnchor?,
                                    uniqueId: String,
                                    installedVersion: String,
                                    facts: NexusInstallFacts?,
                                    isReferenceFile: Bool,
                                    now: Date) -> ModVersionAnchor? {
        if isReferenceFile {
            return ModVersionAnchor(uniqueId: uniqueId,
                                    anchoredVersion: installedVersion,
                                    origin: .install,
                                    anchoredAt: now,
                                    // Des faits absents n'effacent pas ceux
                                    // qu'une installation antérieure a connus.
                                    nexusFacts: facts ?? existing?.nexusFacts)
        }
        // Fichier secondaire : sans version antérieure à conserver, il n'y a
        // rien à affirmer.
        guard let existing else { return nil }
        return ModVersionAnchor(uniqueId: uniqueId,
                                anchoredVersion: existing.anchoredVersion,
                                origin: existing.origin,
                                anchoredAt: now,
                                nexusFacts: facts ?? existing.nexusFacts)
    }

    /// Après un clic sur « je l'ai déjà ».
    public static func afterUserAffirmation(uniqueId: String,
                                            version: String,
                                            now: Date) -> ModVersionAnchor {
        ModVersionAnchor(uniqueId: uniqueId,
                         anchoredVersion: version,
                         origin: .userAffirmed,
                         anchoredAt: now,
                         nexusFacts: nil)
    }

    /// Après un scan qui a vu la version du manifest **changer**.
    ///
    /// L'événement, pas l'état : « le manifest a rejoint la version cible » est
    /// vrai en permanence pour les ~800 mods à jour. Formulée ainsi, la règle
    /// se déclencherait à chaque rescan et éteindrait des lignes sans
    /// installation — le défaut d'origine par la route disque.
    public static func afterDiskChange(existing: ModVersionAnchor?,
                                       uniqueId: String,
                                       previousManifestVersion: String,
                                       currentManifestVersion: String,
                                       suggestedVersion: String,
                                       now: Date) -> ModVersionAnchor? {
        guard previousManifestVersion != currentManifestVersion else { return nil }
        // Rejoindre ou dépasser : une version qui change sans atteindre la
        // cible est une installation partielle, la mise à jour reste due.
        guard !NexusUpdateChecker.isNewer(suggestedVersion, installed: currentManifestVersion) else {
            return nil
        }
        // Une ancre d'installation ne se dégrade pas : la remplacer jetterait
        // `nexusFacts`, et avec eux la date du fichier réellement posé.
        if let existing, existing.origin == .install,
           !NexusUpdateChecker.isNewer(currentManifestVersion, installed: existing.anchoredVersion) {
            return nil
        }
        return ModVersionAnchor(uniqueId: uniqueId,
                                anchoredVersion: currentManifestVersion,
                                origin: .diskObserved,
                                anchoredAt: now,
                                nexusFacts: existing?.nexusFacts)
    }
}
