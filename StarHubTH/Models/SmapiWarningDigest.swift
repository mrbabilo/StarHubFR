import Foundation

// Les avertissements récurrents de la carte de santé : ce qui se répète dans
// le journal sans rien bloquer. Sorti de `SmapiLogDiagnostics.swift`, déjà au
// plafond de taille ; seule la propriété stockée vit dans le corps du type.
extension SmapiDiagnostics {

    /// Un mod dont les lignes `WARN` reviennent dans le journal.
    ///
    /// **Information, pas alerte** : rien ici n'entre dans `problemCount`. Sur
    /// le journal de l'auteur (parc sain, jeu lancé normalement), 40 lignes
    /// venaient de Shads Context Tags Compatibility et 24 de CueSwap. Des
    /// patches sans effet, rien de cassé.
    public struct RecurringWarning: Identifiable, Sendable {
        public let id = UUID()
        /// Le mod mis en cause : le pack pour une ligne de Content Patcher.
        public let mod: String
        public let count: Int
        /// Combien de messages **différents** : 40 lignes de Shads étaient
        /// 4 patches répétés 10 fois. Sans ce chiffre, 40 exagère.
        public let distinct: Int
        /// La première ligne vue, pour retrouver le message dans le journal.
        public let sample: String

        public init(mod: String, count: Int, distinct: Int, sample: String) {
            self.mod = mod
            self.count = count
            self.distinct = distinct
            self.sample = sample
        }
    }

    /// Niveau et mod d'une ligne `[HH:MM:SS LEVEL  Contexte] …`, en-tête
    /// découpé **une seule fois** : le décompte des erreurs et celui des
    /// avertissements le partagent, sur des journaux de 239 000 lignes.
    /// `mod` vaut nil pour les contextes de framework (« SMAPI », « game »).
    static func header(of line: String) -> (level: String, mod: String?)? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let parts = line[line.index(after: line.startIndex)..<close]
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 2 else { return nil }
        let name = parts.count >= 3 ? parts[2...].joined(separator: " ") : ""
        let mod = name.isEmpty || name == "SMAPI" || name == "game" ? nil : name
        return (parts[1].uppercased(), mod)
    }

    /// Le mod à qui imputer un avertissement. Content Patcher journalise au
    /// nom de **ses packs** : le coupable est le premier segment du chemin de
    /// patch (`Pack > fichier > patch`). S'il ne se lit pas, la ligne reste
    /// imputée à Content Patcher plutôt qu'à un nom deviné.
    static func warningMod(context: String, body: String) -> String {
        guard context == "Content Patcher",
              let pack = contentPackName(inPatchMessage: body) else { return context }
        return pack
    }

    /// Le pack d'un message Content Patcher. Deux formes relevées :
    /// `Can't apply data patch "Pack > …" to …` et `Ignored Pack > … : …`.
    /// Une autre forme rend nil : mieux vaut Content Patcher qu'un faux nom.
    static func contentPackName(inPatchMessage body: String) -> String? {
        guard let separator = body.range(of: " > ") else { return nil }
        var head = body[..<separator.lowerBound]
        if let quote = head.lastIndex(of: "\"") {
            head = head[head.index(after: quote)...]
        } else if head.hasPrefix("Ignored ") {
            head = head.dropFirst("Ignored ".count)
        } else {
            return nil
        }
        let name = head.trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name.count > 80 ? nil : name
    }

    /// Le décompte des avertissements par mod, pendant la lecture.
    struct WarningTally {
        private var byMod: [String: (count: Int, bodies: Set<String>, first: String)] = [:]

        mutating func add(mod: String, body: String) {
            if var entry = byMod[mod] {
                entry.count += 1
                entry.bodies.insert(body)
                byMod[mod] = entry
            } else {
                byMod[mod] = (1, [body], body)
            }
        }

        /// Les mods qui se répètent (`minimum` lignes au moins), les plus
        /// bavards d'abord, puis par nom : même ordre que `topErrorMods`. Une
        /// ligne isolée n'est pas « récurrente », et la section la noierait.
        func top(limit: Int = 5, minimum: Int = 2) -> [RecurringWarning] {
            byMod
                .filter { $0.value.count >= minimum }
                .sorted { lhs, rhs in
                    lhs.value.count != rhs.value.count
                        ? lhs.value.count > rhs.value.count : lhs.key < rhs.key
                }
                .prefix(limit)
                .map { RecurringWarning(mod: $0.key, count: $0.value.count,
                                        distinct: $0.value.bodies.count,
                                        sample: SmapiDiagnostics.evidence(from: $0.value.first)) }
        }
    }
}
