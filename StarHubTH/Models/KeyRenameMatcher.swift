import Foundation

/// C2-T4 §8.1 — apparier les clés disparues et les clés neuves d'une même
/// mise à jour quand ce sont les mêmes, renommées.
public enum KeyRenameMatcher {

    /// Pairage par valeur EN identique : sûr. Un-à-un, déterministe.
    public static func pairsByValue(old: [String: String],
                                    new: [String: String]) -> [RenamePair] {
        var byValue: [String: [String]] = [:]
        for (key, value) in new.sorted(by: { $0.key < $1.key }) {
            byValue[value, default: []].append(key)
        }
        var used = Set<String>()
        var pairs: [RenamePair] = []
        for (key, value) in old.sorted(by: { $0.key < $1.key }) {
            guard let candidates = byValue[value] else { continue }
            guard let elected = candidates.first(where: { !used.contains($0) })
            else { continue }
            used.insert(elected)
            pairs.append(RenamePair(oldKey: key, newKey: elected))
        }
        return pairs
    }

    /// Similarité de nom : normalisation casse/séparateurs, Levenshtein borné,
    /// un-à-un par meilleur score. Rend seulement les paires sous seuil.
    ///
    /// Pré-filtre de longueur : la distance majore l'écart des longueurs
    /// **normalisées** — au-delà de la borne, le calcul ne peut pas passer.
    /// Sans lui, une grosse mise à jour rewordée (~1 000 × 1 000 clés) paie
    /// 10⁶ Levenshtein sur le fil principal ; avec lui, quelques milliers.
    /// Juger les longueurs normalisées, jamais brutes : la normalisation
    /// change la longueur (séparateurs → espaces).
    public static func pairsBySimilarity(removed: [String],
                                         added: [String]) -> [RenamePair] {
        // Seuil : distance ≤ max(2, 30 % de la longueur du plus long).
        struct Candidate: Comparable {
            let distance: Int
            let oldKey: String
            let newKey: String
            static func < (l: Candidate, r: Candidate) -> Bool {
                l.distance != r.distance ? l.distance < r.distance
                    : (l.oldKey, l.newKey) < (r.oldKey, r.newKey)
            }
        }
        var all: [Candidate] = []
        for oldKey in removed {
            for newKey in added {
                let a = normalize(oldKey), b = normalize(newKey)
                let bound = max(2, max(a.count, b.count) * 3 / 10)
                if abs(a.count - b.count) > bound { continue }
                let d = levenshtein(a, b)
                if d <= bound {
                    all.append(Candidate(distance: d, oldKey: oldKey, newKey: newKey))
                }
            }
        }
        var usedOld = Set<String>()
        var usedNew = Set<String>()
        var pairs: [RenamePair] = []
        for c in all.sorted() where !usedOld.contains(c.oldKey) && !usedNew.contains(c.newKey) {
            usedOld.insert(c.oldKey)
            usedNew.insert(c.newKey)
            pairs.append(RenamePair(oldKey: c.oldKey, newKey: c.newKey))
        }
        return pairs.sorted { $0.oldKey < $1.oldKey }
    }

    /// camelCase / snake_case / kebab-case → mots minuscules joints par un
    /// espace : `enable_beta_features` et `enable.feature` mesurent une
    /// distance nulle, et un camelCase voisin passe sous la borne.
    static func normalize(_ key: String) -> String {
        let separators: Set<Unicode.Scalar> = ["_", "-", ".", " "]
        var words: [String] = []
        var current = ""
        for scalar in key.lowercased().unicodeScalars {
            if separators.contains(scalar) {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.joined(separator: " ")
    }

    /// Levenshtein classique, borné par la longueur des entrées.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a.unicodeScalars), t = Array(b.unicodeScalars)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var cur = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            cur[0] = i
            for j in 1...t.count {
                let cost = s[i-1] == t[j-1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[t.count]
    }
}
