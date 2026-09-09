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
/// portée de la réécriture reste `installed_translations.json` seul.
public enum AppSupportMigration {

    /// `true` quand ce JSON porte au moins un chemin de l'ancienne racine.
    public static func needsRewrite(_ json: Data, oldRoot: String) -> Bool {
        guard let text = String(data: json, encoding: .utf8) else { return false }
        return text.contains(oldRoot + "/")
    }

    /// Le même JSON, ses chemins repointés. `nil` quand il n'y a rien à faire
    /// ou que la donnée n'est pas du texte lisible — dans les deux cas, ne rien
    /// écrire vaut mieux qu'écrire à tort.
    ///
    /// La substitution porte sur `<racine>/`, jamais sur le seul nom : un mod
    /// nommé « StarHubTH » dans `Mods/` garderait sinon un chemin faux.
    public static func rewrite(_ json: Data, from oldRoot: String, to newRoot: String) -> Data? {
        guard let text = String(data: json, encoding: .utf8),
              text.contains(oldRoot + "/") else { return nil }
        return Data(text.replacingOccurrences(of: oldRoot + "/", with: newRoot + "/").utf8)
    }
}
