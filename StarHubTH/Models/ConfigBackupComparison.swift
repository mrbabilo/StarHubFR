import Foundation

/// Une version sauvegardée d'un `config.json` contre le fichier actuel —
/// ce qu'on voit **avant** de restaurer (vue des sauvegardes par mod,
/// 2026-10-16). Même diff que la comparaison entre profils (`ConfigJSONDiff`) :
/// A = la sauvegarde, B = le fichier actuel.
public enum ConfigBackupComparison {

    public enum Outcome: Equatable, Sendable {
        /// L'un des deux fichiers manque : mod désinstallé, `config.json`
        /// jamais écrit, ou sauvegarde sans ce fichier.
        case missing
        /// L'un des deux ne se lit pas comme du JSON (SMAPI le refuserait aussi).
        case unparseable
        case identical
        case differs([ConfigKeyDiff])
    }

    public static func compare(backup: String?, current: String?) -> Outcome {
        guard let backup, let current else { return .missing }
        guard let a = ConfigJSONTree.parse(backup), let b = ConfigJSONTree.parse(current) else { return .unparseable }
        let diffs = ConfigJSONDiff.compare(a, b)
        return diffs.isEmpty ? .identical : .differs(diffs)
    }
}
