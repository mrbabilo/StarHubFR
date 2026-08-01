import Foundation

/// Ce qu'on sait d'un mod installé : la version vue sur disque, la date à
/// laquelle on l'a constatée, et la version publiée sur Nexus si on la connaît.
struct InstalledModRecord: Codable, Equatable {
    let version: String
    let installedAt: Date
    var nexusVersion: String? = nil

    init(version: String, installedAt: Date, nexusVersion: String? = nil) {
        self.version = version
        self.installedAt = installedAt
        self.nexusVersion = nexusVersion
    }
}

/// Met à jour le registre des mods installés à partir de ce qu'un scan a vu.
///
/// Extrait du ViewModel, où rien ne le testait — alors que ses décisions
/// commandent la détection des mises à jour : une date d'installation erronée
/// signale une mise à jour qui n'existe pas, et une version Nexus perdue en
/// réintroduit une déjà écartée.
///
/// Pur : l'appelant fournit le registre courant, ce que le scan a vu, et
/// **l'instant présent**. Cette dernière injection est ce qui rend la logique
/// vérifiable, les trois quarts des règles portant sur l'horodatage.
enum InstalledModRegistry {
    /// Un mod tel que le scan l'a vu, sa version Nexus déjà résolue par
    /// l'appelant (la résolution dépend du registre Nexus, pas d'ici).
    struct Seen {
        let folder: String
        let version: String
        let nexusVersion: String?

        init(folder: String, version: String, nexusVersion: String? = nil) {
            self.folder = folder
            self.version = version
            // Une version vide ou blanche vaut « inconnue » : stocker un
            // marqueur obligerait chaque comparateur à le traiter à part.
            self.nexusVersion = nexusVersion
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }
    }

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
                                                          installedAt: now,
                                                          nexusVersion: mod.nexusVersion)
                didChange = true
                continue
            }

            if existing.version != mod.version {
                // La version a changé depuis le dernier scan : c'est une mise à
                // jour. On reporte la version Nexus connue plutôt que de la
                // perdre — sans quoi une réinstallation ferait réapparaître une
                // mise à jour déjà écartée.
                registry[mod.folder] = InstalledModRecord(
                    version: mod.version,
                    installedAt: now,
                    nexusVersion: mod.nexusVersion ?? existing.nexusVersion)
                didChange = true
            } else if let known = mod.nexusVersion, known != existing.nexusVersion {
                // Même version, mais on vient d'apprendre celle de Nexus (par
                // exemple à la première vérification après une pose manuelle) :
                // on l'enregistre sans toucher à la date d'installation.
                registry[mod.folder] = InstalledModRecord(version: existing.version,
                                                          installedAt: existing.installedAt,
                                                          nexusVersion: known)
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
