import Foundation

/// Ce qu'on sait d'un mod installé : la version vue sur disque et la date à
/// laquelle on l'a constatée.
///
/// `nexusVersion` a été retiré le 2026-08-12. Il portait « la dernière version
/// publiée sur Nexus » sous le nom d'une version installée, sans qu'aucune
/// installation ne l'atteste : le vérificateur comparait ensuite cette version
/// à elle-même et concluait « à jour ». Ce que l'app affirme avoir installé
/// vit désormais dans `ModVersionAnchor`, et ne s'écrit que sur un constat.
struct InstalledModRecord: Codable, Equatable {
    let version: String
    let installedAt: Date

    init(version: String, installedAt: Date) {
        self.version = version
        self.installedAt = installedAt
    }
}

/// Met à jour le registre des mods installés à partir de ce qu'un scan a vu.
///
/// Extrait du ViewModel, où rien ne le testait — alors que ses décisions
/// commandent la détection des mises à jour : une date d'installation erronée
/// signale une mise à jour qui n'existe pas.
///
/// Pur : l'appelant fournit le registre courant, ce que le scan a vu, et
/// **l'instant présent**. Cette dernière injection est ce qui rend la logique
/// vérifiable, les trois quarts des règles portant sur l'horodatage.
enum InstalledModRegistry {
    /// Un mod tel que le scan l'a vu.
    struct Seen {
        let folder: String
        let version: String

        init(folder: String, version: String) {
            self.folder = folder
            self.version = version
        }
    }

    /// `now` vaut pour **tout le lot**, là où le code d'origine évaluait `Date()`
    /// à chaque enregistrement : les mods d'un même scan portaient des instants
    /// distants de quelques microsecondes. Sans portée — cette date se compare à
    /// une date de mise en ligne Nexus, dont la granularité est l'heure — mais la
    /// différence est réelle, et un lot cohérent vaut mieux qu'un lot dispersé.
    ///
    /// - Returns: le registre mis à jour, et `didChange` — faux quand rien n'a
    ///   bougé. Un rafraîchissement sans installation ni suppression est le cas
    ///   courant : ne rien réécrire épargne un encodage JSON à chaque scan.
    static func sync(registry current: [String: InstalledModRecord],
                     seen: [Seen],
                     now: Date) -> (registry: [String: InstalledModRecord], didChange: Bool) {
        var registry = current
        var didChange = false
        var seenFolders = Set<String>()

        for mod in seen {
            seenFolders.insert(mod.folder)

            guard let existing = registry[mod.folder] else {
                // Jamais vu : on l'horodate à maintenant, et surtout **pas** à
                // la date du dossier — une copie conserve la date d'empaquetage
                // de l'archive, toujours antérieure à la mise en ligne, ce qui
                // ferait signaler une mise à jour pour la version déjà installée.
                registry[mod.folder] = InstalledModRecord(version: mod.version,
                                                          installedAt: now)
                didChange = true
                continue
            }

            if existing.version != mod.version {
                // La version a changé depuis le dernier scan : c'est une mise à
                // jour. C'est aussi l'événement que `ModVersionAnchorRules
                // .afterDiskChange` consomme — le seul moment où l'app peut
                // constater une installation qu'elle n'a pas faite.
                registry[mod.folder] = InstalledModRecord(version: mod.version,
                                                          installedAt: now)
                didChange = true
            }
        }

        // Les dossiers disparus du disque quittent le registre.
        let before = registry.count
        registry = registry.filter { seenFolders.contains($0.key) }
        if registry.count != before { didChange = true }

        return (registry, didChange)
    }
}
