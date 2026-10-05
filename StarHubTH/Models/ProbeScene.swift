import Foundation

/// D4-T9 — la charge de la scène du lieu courant, relevée par la sonde en
/// fin de minute (champ `Scene` des lignes de `timings.jsonl`, sonde ≥ 0.9.21).
/// L'onglet s'en sert pour dire ce qui explique une minute lente et, dans une
/// comparaison avant/après, distinguer un mod coûteux d'une scène plus chargée.
public enum ProbeScene {
    /// Les compteurs connus, dans l'ordre d'affichage. La sonde peut en
    /// ajouter plus tard : une clé sans libellé n'est pas affichée, jamais
    /// une ligne tronquée de rien.
    public static let counters: [String] = [
        "npcs", "animals", "furniture", "objects", "terrainFeatures",
        "largeTerrainFeatures", "resourceClumps", "lights", "temporarySprites",
        "debris", "locations",
    ]

    /// Ces minutes portent-elles une scène ? Faux sur les sondes antérieures
    /// à 0.9.21 et sur les minutes hors monde : l'affichage se tait.
    public static func hasData(_ minutes: [ProbeMinute]) -> Bool {
        minutes.contains { $0.scene != nil }
    }

    /// Les valeurs d'un compteur, sur les minutes qui le portent.
    static func values(_ key: String, _ minutes: [ProbeMinute]) -> [Double] {
        var out: [Double] = []
        for minute in minutes {
            guard let count = minute.scene?[key] else { continue }
            out.append(Double(count))
        }
        return out
    }

    /// Médiane de chaque compteur connu, sur les minutes qui le portent. Un
    /// compteur absent de toutes les minutes (sonde antérieure) est absent du
    /// résultat : l'affichage ne montre que ce qui a été mesuré.
    public static func medians(_ minutes: [ProbeMinute]) -> [String: Double] {
        var result: [String: Double] = [:]
        for key in counters {
            guard let median = ProbeStats.median(values(key, minutes)) else { continue }
            result[key] = median
        }
        return result
    }

    /// Un compteur de scène qui sépare les deux côtés : ses médianes avant →
    /// après et le verdict net du comparateur commun (≥ 5 minutes, écart > 5 %
    /// et quartiles disjoints). Une scène stable donne des quartiles égaux :
    /// verdict bruit, et la ligne dit « comparable ».
    public struct Difference: Equatable, Sendable {
        public let key: String
        public let medianBefore: Double
        public let medianAfter: Double
        public let delta: Double
        public let percent: Double
    }

    /// Les différences nettes des deux côtés, compteurs connus dans l'ordre
    /// d'affichage. Vide si rien ne sépare (scène stable) ou si rien n'a été
    /// mesuré — l'appelant distingue les deux avec `hasData`.
    public static func differences(before: [ProbeMinute], after: [ProbeMinute]) -> [Difference] {
        let mediansBefore = medians(before)
        let mediansAfter = medians(after)
        var out: [Difference] = []
        for key in counters {
            guard let a = mediansBefore[key], let b = mediansAfter[key], a != b else { continue }
            guard case .netChange(let delta, let percent) =
                ProbeComparison.compare(values(key, before), values(key, after)).verdict
            else { continue }
            out.append(Difference(key: key, medianBefore: a, medianAfter: b,
                                  delta: delta, percent: percent))
        }
        return out
    }
}
