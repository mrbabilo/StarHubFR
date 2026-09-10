import Foundation

/// La réécriture des chemins **absolus** qu'un déplacement de dossier périme.
///
/// Deux fichiers d'index en portent, mesurés le 2026-08-26 :
/// `installed_translations.json` (2) et `Backups/ModInstalls/install_metadata.json`
/// (1 309). Seul le premier est concerné par la phase 1 — `Backups/` ne bouge pas.
///
/// **Pourquoi c'est le point sensible** : `ManifestlessInstaller.uninstall`
/// *supprime* le fichier déposé quand sa sauvegarde est introuvable, au lieu de
/// rendre l'original. Un dossier déplacé sans cette réécriture détruirait donc
/// les fichiers que les dépôts avaient recouverts.
///
/// Re-mesuré le 2026-09-10 (revue de dérive du plan) : les sept stores nés
/// depuis — `NexusArchiveStore`, `ProfileConfigStore`, `ProfileApplyJournal`,
/// `ModUpdateKeyDeltaStore`, `TranslationCoverageCache`,
/// `PathoschildCompatibilityList`, `ProfileApplyPlan.Move` — ne stockent
/// **aucun** chemin absolu (noms dérivés de la racine ou données pures). La
/// phase 1 réécrit donc `installed_translations.json` **et son `.bak`** — que
/// `InstalledTranslationStore` promeut quand le principal est corrompu.
/// X105 y ajoutera les index de `Backups/` : 220 `backupPath` absolus dans
/// `install_metadata.json`, aucun dans `metadata.json` (relevé 2026-09-10).
public enum AppSupportMigration {

    /// Les deux graphies d'une même racine dans un JSON, et leur remplacement.
    ///
    /// **La seconde est celle qui compte.** Les trois index que la migration
    /// réécrit sont écrits par un `JSONEncoder` **nu**, qui échappe les
    /// slashes : le disque porte `…\\/StarHubTH\\/…`. Ne chercher que la
    /// graphie nue revenait à ne rien trouver — `rewrite` rendait `nil`, la
    /// migration croyait n'avoir rien à faire, et le dossier partait avec ses
    /// chemins périmés. Le défaut a survécu à la livraison parce que toutes les
    /// fixtures étaient écrites à la main, avec des slashes nus.
    private static func substitutions(from oldRoot: String,
                                      to newRoot: String) -> [(needle: String, replacement: String)] {
        func escaped(_ path: String) -> String {
            path.replacingOccurrences(of: "/", with: "\\/")
        }
        return [(oldRoot + "/", newRoot + "/"),
                (escaped(oldRoot) + "\\/", escaped(newRoot) + "\\/")]
    }

    /// `true` quand ce JSON porte au moins un chemin de l'ancienne racine,
    /// dans l'une ou l'autre graphie.
    public static func needsRewrite(_ json: Data, oldRoot: String) -> Bool {
        guard let text = String(data: json, encoding: .utf8) else { return false }
        return substitutions(from: oldRoot, to: oldRoot)
            .contains { text.contains($0.needle) }
    }

    /// Le même JSON, ses chemins repointés. `nil` quand il n'y a rien à faire
    /// ou que la donnée n'est pas du texte lisible — dans les deux cas, ne rien
    /// écrire vaut mieux qu'écrire à tort.
    ///
    /// La substitution porte sur `<racine>/`, jamais sur le seul nom : un mod
    /// nommé « StarHubTH » dans `Mods/` garderait sinon un chemin faux.
    public static func rewrite(_ json: Data, from oldRoot: String, to newRoot: String) -> Data? {
        guard var text = String(data: json, encoding: .utf8) else { return nil }
        var touched = false
        for (needle, replacement) in substitutions(from: oldRoot, to: newRoot)
        where text.contains(needle) {
            text = text.replacingOccurrences(of: needle, with: replacement)
            touched = true
        }
        return touched ? Data(text.utf8) : nil
    }
}
