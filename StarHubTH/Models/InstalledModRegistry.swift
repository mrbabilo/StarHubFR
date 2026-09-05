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
    /// - Parameter installDateGrace: les dossiers dont un changement de version
    ///   ne doit **pas** ré-estampiller la date d'installation, parce qu'il
    ///   vient d'un changement de lecture et non du disque. Alimenté une seule
    ///   fois, par la migration qui retire `nexusVersion` du registre ;
    ///   l'appelant vide le lot après la passe qui suit. Un dossier absent de
    ///   cette passe est de toute façon purgé du registre, donc une passe suffit.
    /// - Parameter pruneMissing: faux quand le scan **n'a pas pu lire** le
    ///   dossier `Mods/`. Un lot vide veut alors dire « on n'a rien vu », pas
    ///   « il n'y a rien » — dossier de jeu déplacé, volume externe débranché,
    ///   droits refusés. Purger sur cette base viderait le registre entier
    ///   (1 097 entrées sur le parc de référence) **et** sa copie de secours,
    ///   qui reçoit le même blob à la même écriture. Ce qui a été vu
    ///   s'enregistre quand même : seule la purge est suspendue. C'est la règle
    ///   que `MaintenanceInventory.stalePreferenceKeys` s'était déjà donnée
    ///   (X70), appliquée ici au magasin voisin.
    /// - Returns: le registre mis à jour, et `didChange` — faux quand rien n'a
    ///   bougé. Un rafraîchissement sans installation ni suppression est le cas
    ///   courant : ne rien réécrire épargne un encodage JSON à chaque scan.
    static func sync(registry current: [String: InstalledModRecord],
                     seen: [Seen],
                     now: Date,
                     installDateGrace: Set<String> = [],
                     pruneMissing: Bool = true) -> (registry: [String: InstalledModRecord], didChange: Bool) {
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

            if existing.version != mod.version, installDateGrace.contains(mod.folder) {
                // Ce dossier figure au lot de grâce : sa version « change »
                // parce que la LECTURE a changé, pas le disque. Le registre
                // enregistrait la version Nexus quand elle dépassait celle du
                // manifest ; depuis le retrait de cette substitution, il
                // enregistre celle du manifest. Ré-estampiller ici écraserait
                // sans retour la seule trace de la date d'installation — elle
                // n'est écrite nulle part ailleurs, et la date du dossier ne la
                // reconstitue pas (c'est la date d'empaquetage de l'archive).
                registry[mod.folder] = InstalledModRecord(version: mod.version,
                                                          installedAt: existing.installedAt)
                didChange = true
            } else if existing.version != mod.version {
                // La version a changé depuis le dernier scan : c'est une mise à
                // jour. C'est aussi l'événement que `ModVersionAnchorRules
                // .afterDiskChange` consomme — le seul moment où l'app peut
                // constater une installation qu'elle n'a pas faite.
                registry[mod.folder] = InstalledModRecord(version: mod.version,
                                                          installedAt: now)
                didChange = true
            }
        }

        // Les dossiers disparus du disque quittent le registre — sauf si le
        // scan n'a pas pu lire `Mods/` : voir `pruneMissing`.
        if pruneMissing {
            let before = registry.count
            registry = registry.filter { seenFolders.contains($0.key) }
            if registry.count != before { didChange = true }
        }

        return (registry, didChange)
    }
}
