import Foundation

/// Deux mods, sans ordre entre eux.
///
/// « A avec B » et « B avec A » sont le même signalement : sans cette
/// normalisation, l'utilisateur en créerait deux sans le savoir, et le rapport
/// afficherait la même incompatibilité deux fois.
///
/// La clé est le `folderName` **logique** — jamais l'`UniqueID`, que 111 mods du
/// parc ne déclarent pas, et jamais le nom physique, qui gagne un point quand le
/// mod passe en pause.
public struct ModConflictPair: Codable, Hashable, Sendable {
    public let first: String
    public let second: String

    public init(_ a: String, _ b: String) {
        let ordered = [a, b].sorted()
        self.first = ordered[0]
        self.second = ordered[1]
    }

    public func contains(_ folderName: String) -> Bool {
        first == folderName || second == folderName
    }
}

/// Ce que l'utilisateur a décidé d'une paire.
public struct ModConflictVerdict: Codable, Equatable, Sendable {
    public let isDeclared: Bool
    public let note: String
    public let decidedAt: Date
}

/// Les verdicts que l'utilisateur a posés sur des paires de mods.
///
/// Deux sens, et le second compte autant que le premier : **déclarer** une
/// incompatibilité que rien n'a détectée, et **écarter** une ligne détectée qu'il
/// juge fausse. Sans le second, un faux positif resterait affiché pour toujours —
/// et c'est ainsi qu'on apprend à ignorer une alerte.
public struct ModConflictVerdicts: Codable, Equatable, Sendable {
    private var verdicts: [ModConflictPair: ModConflictVerdict]

    public init() { verdicts = [:] }

    public func verdict(for pair: ModConflictPair) -> ModConflictVerdict? {
        verdicts[pair]
    }

    /// Un seul verdict par paire : le dernier remplace le précédent, avec sa
    /// date. Pas d'historique — la note du verdict courant dit pourquoi.
    public mutating func declare(_ pair: ModConflictPair, note: String, at date: Date) {
        verdicts[pair] = ModConflictVerdict(isDeclared: true, note: note, decidedAt: date)
    }

    public mutating func dismiss(_ pair: ModConflictPair, note: String, at date: Date) {
        verdicts[pair] = ModConflictVerdict(isDeclared: false, note: note, decidedAt: date)
    }

    /// Trie les paires dans un ordre **total** — sur le couple `(first, second)`,
    /// pas le seul `first`. Trier sur lui seul laisserait l'ordre des paires qui
    /// le partagent au hasard du hachage, et le fichier JSON changerait à chaque
    /// sauvegarde sans qu'aucune donnée n'ait bougé.
    private func sortPairs(_ pairs: [ModConflictPair]) -> [ModConflictPair] {
        pairs.sorted { ($0.first, $0.second) < ($1.first, $1.second) }
    }

    /// Les paires portant un verdict d'un sens donné.
    private func pairs(declared wanted: Bool) -> [ModConflictPair] {
        let filtered = verdicts.filter { $0.value.isDeclared == wanted }.keys
        return sortPairs(Array(filtered))
    }

    public var declared: [ModConflictPair] {
        pairs(declared: true)
    }

    public var dismissed: [ModConflictPair] {
        pairs(declared: false)
    }

    /// Les paires dont au moins un mod n'est plus installé. **On les rend, on ne
    /// les efface pas** : l'utilisateur a appris quelque chose en les posant.
    public func orphans(among installed: [String]) -> [ModConflictPair] {
        let known = Set(installed)
        let orphaned = verdicts.keys.filter { !known.contains($0.first) || !known.contains($0.second) }
        return sortPairs(Array(orphaned))
    }

    // Un dictionnaire à clé non-`String` ne se code pas en JSON d'objet : on
    // passe par un tableau de couples, ce qui garde le fichier lisible à l'œil.
    private enum CodingKeys: String, CodingKey { case entries }
    private struct Entry: Codable { let pair: ModConflictPair; let verdict: ModConflictVerdict }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decode([Entry].self, forKey: .entries)
        verdicts = Dictionary(uniqueKeysWithValues: entries.map { ($0.pair, $0.verdict) })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let entries = sortPairs(Array(verdicts.keys)).map { pair in
            Entry(pair: pair, verdict: verdicts[pair]!)
        }
        try container.encode(entries, forKey: .entries)
    }
}
