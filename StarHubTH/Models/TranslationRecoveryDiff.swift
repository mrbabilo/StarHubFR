import Foundation

/// Un écart entre le fichier de traduction d'une sauvegarde et celui installé.
struct TranslationKeyDiff: Identifiable, Equatable {
    enum Kind: Equatable {
        /// La sauvegarde porte la clé, l'installé ne l'a plus. **La seule
        /// famille récupérable** : rien de ce qui existe aujourd'hui n'est
        /// écrasé en la réinjectant.
        case onlyInBackup
        /// Les deux la portent, avec des valeurs différentes. La valeur de la
        /// sauvegarde est plus ancienne, pas meilleure : montrée, jamais
        /// proposée au remplacement.
        case valueDiffers
        /// Seul l'installé la porte — le mod a grandi, ou elle a été traduite
        /// depuis. Rien à faire, mais elle explique l'écart de comptage.
        case onlyInInstalled
    }

    var id: String { key }
    /// La clé telle que l'écrit le fichier qui la porte — la sauvegarde quand
    /// elle y est, puisque c'est cette graphie qu'on réinjecterait.
    let key: String
    let backupValue: String?
    let installedValue: String?
    let kind: Kind
}

/// Compare la traduction d'une sauvegarde à celle du mod installé, clé à clé.
///
/// Une mise à jour de mod rend souvent le fichier à sa version anglaise. Le
/// traducteur en refait une partie, et le reste dort dans une sauvegarde :
/// remplacer le fichier entier lui coûterait ce qu'il vient d'écrire, ne rien
/// faire lui coûte ce qu'il avait écrit avant. La seule réponse juste est **clé
/// par clé**, et seulement sur celles que l'installé n'a plus.
enum TranslationRecoveryDiff {
    /// - Parameters:
    ///   - backup: les clés du fichier de la sauvegarde.
    ///   - installed: celles du fichier installé.
    /// - Returns: les écarts, récupérables d'abord ; à l'intérieur d'une
    ///   famille, par ordre de clé — un affichage qui se réordonne d'un rendu
    ///   à l'autre est illisible.
    static func compare(backup: [String: String],
                        installed: [String: String]) -> [TranslationKeyDiff] {
        // SMAPI compare ses clés en `OrdinalIgnoreCase` : `Item.Name` et
        // `item.name` sont la même clé. `TranslationCoverage.fold` porte déjà
        // cette règle — la réécrire ici en ferait une seconde, qui finirait par
        // en diverger, et réinjecter la « même » clé sous une autre casse
        // créerait un doublon invisible en jeu.
        let installedByFold = Dictionary(installed.map { (TranslationCoverage.fold($0.key), $0.value) },
                                         uniquingKeysWith: { first, _ in first })
        let backupByFold = Dictionary(backup.map { (TranslationCoverage.fold($0.key), $0.value) },
                                      uniquingKeysWith: { first, _ in first })

        var diffs: [TranslationKeyDiff] = []
        for (key, value) in backup {
            let folded = TranslationCoverage.fold(key)
            guard let installedValue = installedByFold[folded] else {
                // Une valeur vide n'est pas une traduction : la proposer
                // effacerait la clé sans rien apporter.
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                diffs.append(TranslationKeyDiff(key: key, backupValue: value,
                                                installedValue: nil, kind: .onlyInBackup))
                continue
            }
            guard installedValue != value else { continue }
            diffs.append(TranslationKeyDiff(key: key, backupValue: value,
                                            installedValue: installedValue, kind: .valueDiffers))
        }
        for (key, value) in installed where backupByFold[TranslationCoverage.fold(key)] == nil {
            diffs.append(TranslationKeyDiff(key: key, backupValue: nil,
                                            installedValue: value, kind: .onlyInInstalled))
        }

        let rank: (TranslationKeyDiff.Kind) -> Int = { kind in
            switch kind {
            case .onlyInBackup: return 0
            case .valueDiffers: return 1
            case .onlyInInstalled: return 2
            }
        }
        return diffs.sorted {
            rank($0.kind) != rank($1.kind)
                ? rank($0.kind) < rank($1.kind)
                : $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }
    }

    /// Les clés à réécrire, prêtes pour `TranslationDocument.apply`.
    ///
    /// Filtre une dernière fois sur `onlyInBackup` : c'est la barrière avant
    /// d'écrire dans le fichier du traducteur, et elle ne doit pas dépendre de
    /// ce que l'appelant a bien voulu passer.
    static func edits(for diffs: [TranslationKeyDiff]) -> [String: String] {
        var edits: [String: String] = [:]
        for diff in diffs where diff.kind == .onlyInBackup {
            guard let value = diff.backupValue else { continue }
            edits[diff.key] = value
        }
        return edits
    }
}
