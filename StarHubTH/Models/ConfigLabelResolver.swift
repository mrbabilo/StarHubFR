import Foundation

/// C4-T1 — les libellés `config.*` qu'un mod C# publie dans son `i18n/`,
/// rapprochés des clés de son `config.json`.
///
/// Un mod C# ne décrit ses options nulle part : le seul texte lisible posé
/// sur le disque vit dans `i18n/default.json` (anglais) et `i18n/fr.json`,
/// sous des clés du genre `config.fastWarp.name`. La règle de rapprochement —
/// mesurée sur le parc le 2026-08-28, puis confirmée par décompilation le
/// 2026-09-04 ([`audit-mods-config-perf.md`](../../../docs/audit-mods-config-perf.md)) —
/// compare la **tige** (clé i18n privée du préfixe `config.` et du suffixe
/// `name|description|tooltip|desc|label|title`) à la clé de configuration,
/// **insensible à la casse**, avec repli assumé sur la clé brute : UltraSmooth
/// suit `camelCase(champ)` à 100 %, SLO choisit librement et ne retombe pas —
/// le plafond est structurel, personne ne promet 100 %.
///
/// Le français gagne quand il existe, champ par champ : un label traduit
/// n'entraîne pas sa description — la description anglaise reste meilleure
/// qu'un vide.
public enum ConfigLabelResolver {

    /// Ce qu'on sait dire d'une clé de configuration.
    public struct Labels: Equatable, Sendable {
        /// Le texte d'affichage (`name`, puis `label`, puis `title`).
        public var text: String
        /// Le texte d'aide (`description`, puis `tooltip`, puis `desc`),
        /// `nil` quand le mod n'en publie pas.
        public var detail: String?

        public init(text: String, detail: String?) {
            self.text = text
            self.detail = detail
        }
    }

    /// Le préfixe qui dit « cette clé i18n décrit une option de config ».
    public static let keyPrefix = "config."

    /// L'index tige → libellés, insensible à la casse. La locale traduite
    /// gagne champ par champ sur l'anglais (`defaultFile`) : un label traduit
    /// n'entraîne pas sa description, et l'anglais reste meilleure qu'un vide.
    public static func index(defaultFile: [String: String],
                             localizedFile: [String: String]) -> [String: Labels] {
        // Rang de priorité : `name` gagne sur `label`, qui gagne sur `title`.
        // Sans ce rang, la prééminence dépendrait de l'ordre — aléatoire —
        // d'itération du dictionnaire.
        let labelRank: [String: Int] = ["name": 0, "label": 1, "title": 2]
        let detailRank: [String: Int] = ["description": 0, "tooltip": 1, "desc": 2]

        struct Bucket {
            var text: String?
            var textRank = Int.max
            var detail: String?
            var detailRank = Int.max
        }
        var buckets: [String: Bucket] = [:]

        // L'anglais absorbe d'abord : la locale traduite gagne champ par champ.
        for pass in [defaultFile, localizedFile] {
            for (key, value) in pass {
                let lowered = key.lowercased()
                guard lowered.hasPrefix(keyPrefix) else { continue }
                let rest = lowered.dropFirst(keyPrefix.count)
                // `config.heal.amount.name` a pour tige `heal.amount` : on
                // coupe au dernier point, le suffixe étant le dernier maillon.
                guard let lastDot = rest.lastIndex(of: ".") else { continue }
                let stem = String(rest[..<lastDot])
                let suffix = String(rest[rest.index(after: lastDot)...])
                guard !stem.isEmpty else { continue }

                var bucket = buckets[stem] ?? Bucket()
                // `<=` et pas `<` : la passe traduite doit gagner à rang
                // égal. Sans risque dans une même passe — une paire
                // (tige, suffixe) y est unique, le dictionnaire ne peut pas
                // porter deux fois la même clé.
                if let rank = labelRank[suffix], rank <= bucket.textRank {
                    bucket.text = value
                    bucket.textRank = rank
                } else if let rank = detailRank[suffix], rank <= bucket.detailRank {
                    bucket.detail = value
                    bucket.detailRank = rank
                } else {
                    continue
                }
                buckets[stem] = bucket
            }
        }

        var index: [String: Labels] = [:]
        for (stem, bucket) in buckets {
            index[stem] = Labels(text: bucket.text ?? "", detail: bucket.detail)
        }
        return index
    }

    /// Ce qu'on dit d'une clé de configuration, `nil` quand le mod ne publie
    /// rien pour elle. La comparaison est insensible à la casse (UltraSmooth
    /// écrit `camelCase`, le `config.json` peut porter `PascalCase`). Un
    /// résultat à `text` vide est possible — description orpheline — et
    /// l'appelant garde alors la clé brute comme libellé, tout en gagnant
    /// l'aide : mieux qu'un vide.
    public static func labels(for configKey: String,
                              in index: [String: Labels]) -> Labels? {
        index[configKey.lowercased()]
    }
}
