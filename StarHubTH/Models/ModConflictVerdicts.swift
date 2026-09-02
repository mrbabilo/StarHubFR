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

    /// Parmi `candidates` (paires déclarées **ou** observées dans le journal,
    /// non filtrées), le membre — actif aujourd'hui — d'une paire qui
    /// implique le mod qu'on active, si elle n'a pas été écartée. `nil`
    /// sinon, y compris si aucune paire ne cite `activating`.
    ///
    /// `activating` est un **ensemble**, pas un seul nom : le mod qu'on
    /// active peut être un pack, dont `folderName` (l'en-tête, ex. « SVE »)
    /// ne matche jamais un conflit du journal, qui cite ses composants
    /// (« SVE/Farm », le chemin logique complet). Sans cet ensemble, la
    /// moitié « observée dans le journal » de la règle ne se déclencherait
    /// jamais pour aucun pack. Il rend aussi gratuit le cas d'un
    /// `withinOnePack` (paire `(X, X)`) ou de deux composants du **même**
    /// pack qu'on active ensemble : si les deux membres de la paire sont
    /// dans `activating`, ni l'un ni l'autre n'est « déjà actif » au sens où
    /// on l'entend ici — ce n'est pas un mod tiers qui bloque le geste.
    ///
    /// Pure — ne connaît ni `ModItem` ni le journal SMAPI. C'est la seule
    /// partie de la décision d'avertissement à l'activation qui se teste
    /// sans le ViewModel (tâche 9).
    public func activationConflict(activating: Set<String>,
                                    candidates: [ModConflictPair],
                                    activeFolders: Set<String>) -> String? {
        for pair in candidates {
            guard activating.contains(pair.first) || activating.contains(pair.second) else { continue }
            // Écartée : silence, pas seulement retirée du rapport — c'est
            // précisément ce que « écarter » doit obtenir.
            if verdict(for: pair)?.isDeclared == false { continue }
            let other = activating.contains(pair.first) ? pair.second : pair.first
            guard !activating.contains(other) else { continue }
            if activeFolders.contains(other) { return other }
        }
        return nil
    }

    /// Combien de paires réclament une attention **aujourd'hui** — la pastille
    /// « Alertes système » (spec A5-T2). Une par paire non écartée — déclarée
    /// ou observée dans le journal — dont **les deux côtés sont actifs
    /// maintenant** : une paire dormante (un côté en pause, désinstallé, ou
    /// nom du journal non résolu à un dossier) ne demande rien, même règle
    /// que le rapport de raccourcis. La spécification est catégorique : la
    /// pastille se fonde sur l'état actuel du parc, jamais sur celui qu'avait
    /// le journal à la dernière partie.
    ///
    /// `candidates` peut répéter une paire (déclarée **et** observée) : elle
    /// ne compte qu'une fois. Pure, comme `activationConflict` — c'est la
    /// partie de la règle de la pastille qui se teste sans le ViewModel.
    ///
    /// Triée (`sortPairs`) : sans cela l'ordre viendrait de l'itération d'un
    /// `Set`, non déterministe d'un lancement à l'autre — et cette liste
    /// alimente maintenant un affichage (`HealthIssueResolver.resolve`), pas
    /// seulement un compte.
    public func liveConflicts(candidates: [ModConflictPair],
                              activeFolders: Set<String>) -> [ModConflictPair] {
        let filtered = Set(candidates).filter { pair in
            verdict(for: pair)?.isDeclared != false
                && activeFolders.contains(pair.first)
                && activeFolders.contains(pair.second)
        }
        return sortPairs(Array(filtered))
    }

    /// Le compte **dérive** de la liste : une seule règle de filtrage, pas
    /// deux qui finiraient par diverger.
    public func liveConflictCount(candidates: [ModConflictPair],
                                  activeFolders: Set<String>) -> Int {
        liveConflicts(candidates: candidates, activeFolders: activeFolders).count
    }

    // Un dictionnaire à clé non-`String` ne se code pas en JSON d'objet : on
    // passe par un tableau de couples, ce qui garde le fichier lisible à l'œil.
    private enum CodingKeys: String, CodingKey { case entries }
    private struct Entry: Codable { let pair: ModConflictPair; let verdict: ModConflictVerdict }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decode([Entry].self, forKey: .entries)
        // Un fichier qui répète une paire (édition manuelle, fusion) ne doit
        // pas tuer l'app : `uniqueKeysWithValues` lève un fatal error qu'aucun
        // `try?` de `load` n'attrape. Le **dernier** verdict du fichier
        // gagne, comme un verdict re-posé.
        verdicts = Dictionary(entries.map { ($0.pair, $0.verdict) },
                              uniquingKeysWith: { _, latest in latest })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let entries = sortPairs(Array(verdicts.keys)).map { pair in
            Entry(pair: pair, verdict: verdicts[pair]!)
        }
        try container.encode(entries, forKey: .entries)
    }
}
