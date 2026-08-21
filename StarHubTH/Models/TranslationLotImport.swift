import Foundation

/// La relecture d'un lot revenu d'un modèle de chat.
///
/// Deux niveaux de refus, et la distinction est ce qui rend l'import
/// utilisable : ce qui met en cause le **fichier** (mauvais mod, mauvaise
/// langue, format illisible, ou un lot dont **aucune** clé ne concerne
/// l'état courant) le fait rejeter en bloc **avant toute écriture** ; ce
/// qui met en cause **une entrée** (marque dure perdue ou doublée, clé
/// inventée, source modifiée) écarte cette entrée-là et laisse passer le
/// reste.
public enum TranslationLotImport {

    public struct Accepted: Equatable, Sendable {
        public let component: String?
        public let key: String
        public let source: String
        public let target: String
    }

    public struct Rejection: Equatable, Sendable {
        public enum Reason: Equatable, Sendable {
            case missingHardMarkers([String])
            case extraHardMarkers([String])
            case unknownKey
            case sourceAltered
        }
        public let component: String?
        public let key: String
        public let reason: Reason
    }

    public struct Report: Equatable, Sendable {
        public let accepted: [Accepted]
        public let rejected: [Rejection]
    }

    public enum FileRefusal: Error, Equatable, Sendable {
        case unreadable
        case wrongMod
        case wrongLanguage
        case staleDigest
        case unsupportedFormat(Int)
    }

    public static func read(_ data: Data, expecting sent: TranslationLot) throws -> Report {
        guard let lot = decode(data) else { throw FileRefusal.unreadable }
        guard lot.formatVersion == TranslationLot.currentFormatVersion else {
            throw FileRefusal.unsupportedFormat(lot.formatVersion)
        }
        guard lot.mod == sent.mod else { throw FileRefusal.wrongMod }
        guard lot.language == sent.language else { throw FileRefusal.wrongLanguage }

        // Les sources envoyées, par identité : c'est elles qui font foi, pas
        // celles que le fichier prétend porter.
        var expected: [String: TranslationLot.Entry] = [:]
        for entry in sent.entries {
            expected[identity(entry.component, entry.key)] = entry
        }

        // L'empreinte du fichier ne fait plus foi à elle seule : un chat rend
        // volontiers un gros lot en plusieurs messages, et l'import du premier
        // fait sortir ses clés de l'état courant — l'empreinte du second ne
        // peut alors plus correspondre, et le refuser en bloc perdrait tout
        // son travail. Le refus en bloc d'« empreinte périmée » ne survit que
        // ici : un fichier dont **aucune** clé ne concerne l'état courant ne
        // peut rien apporter, c'est le lot d'un autre moment du mod.
        guard lot.entries.contains(where: { expected[identity($0.component, $0.key)] != nil })
        else { throw FileRefusal.staleDigest }

        var accepted: [Accepted] = []
        var rejected: [Rejection] = []
        for entry in lot.entries {
            let target = entry.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { continue }   // travail non fait, pas une erreur
            guard let origin = expected[identity(entry.component, entry.key)] else {
                rejected.append(Rejection(component: entry.component, key: entry.key,
                                          reason: .unknownKey))
                continue
            }
            guard origin.source == entry.source else {
                rejected.append(Rejection(component: entry.component, key: entry.key,
                                          reason: .sourceAltered))
                continue
            }
            // Marques dures : `saveTranslation` bloque sur toute divergence,
            // dans les deux sens — la relecture doit voir exactement la même
            // chose, sans quoi l'entrée serait acceptée ici puis refusée à
            // l'écriture, et finirait dans un compte nu sans clé ni motif.
            let diverging = TranslationTokenCheck
                .mismatches(source: origin.source, target: target)
                .filter(\.isHard)
            let missing = diverging.filter { $0.found < $0.expected }.map(\.token)
            guard missing.isEmpty else {
                rejected.append(Rejection(component: entry.component, key: entry.key,
                                          reason: .missingHardMarkers(missing)))
                continue
            }
            let extra = diverging.filter { $0.found > $0.expected }.map(\.token)
            guard extra.isEmpty else {
                rejected.append(Rejection(component: entry.component, key: entry.key,
                                          reason: .extraHardMarkers(extra)))
                continue
            }
            accepted.append(Accepted(component: entry.component, key: entry.key,
                                     source: origin.source, target: target))
        }
        return Report(accepted: accepted, rejected: rejected)
    }

    /// Les rangées qu'une entrée acceptée a le droit d'écrire, par identité —
    /// le même filtre et le même ordre que `TranslationLot.build` applique à
    /// l'export (`eligibleRows`, puis le garde-fou « anglais non vide »), et
    /// la même règle de dernière occurrence : `read` n'apparie une entrée
    /// rendue qu'à la dernière entrée exportée de son identité, l'écriture
    /// doit donc résoudre vers cette rangée-là. Un écart entre les deux —
    /// typiquement une clé dupliquée dont la dernière occurrence a un
    /// anglais vide — ferait évaluer les marques depuis une source vide :
    /// plus rien ne serait attendu, et le gate d'écriture deviendrait plus
    /// laxiste que celui de la relecture.
    public static func writableRows(_ rows: [TranslationCoverage.DiffRow])
        -> [String: TranslationCoverage.DiffRow] {
        var byIdentity: [String: TranslationCoverage.DiffRow] = [:]
        for row in TranslationBatchPlanner.eligibleRows(rows) where !row.english.isEmpty {
            byIdentity[identity(row.component, row.key)] = row
        }
        return byIdentity
    }

    /// L'identité d'une entrée ou d'une rangée : son composant et sa clé,
    /// joints par un séparateur qui ne peut pas apparaître dans une clé.
    /// Publique parce que la formule n'a pas le droit d'être copiée — deux
    /// formules d'identité, c'est une de trop : elles divergeraient.
    public static func identity(_ component: String?, _ key: String) -> String {
        "\(component ?? "")\u{1F}\(key)"
    }

    /// Un chat rend volontiers son JSON dans une clôture Markdown, précédé
    /// d'une phrase. Cette phrase peut elle-même citer une accolade — nos
    /// consignes (`TranslationLot.instructions`) lui demandent justement de
    /// préserver des marques comme `{{Token}}` — donc un découpage
    /// première-`{`/dernière-`}` naïf risquerait de démarrer dans
    /// l'introduction. On cherche d'abord la clôture ```` ``` ````, la forme
    /// la plus fréquente et la plus fiable, et on ne retombe sur le
    /// découpage première/dernière accolade qu'à défaut.
    private static func decode(_ data: Data) -> TranslationLot? {
        if let lot = attempt(data) { return lot }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        if let fenced = fencedBody(in: text), let lot = attempt(Data(fenced.utf8)) {
            return lot
        }
        guard let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}"), first < last else { return nil }
        return attempt(Data(text[first...last].utf8))
    }

    /// Le contenu d'une clôture ```` ``` ```` (avec ou sans étiquette de
    /// langage, ex. ` ```json `), sans les lignes de clôture elles-mêmes.
    private static func fencedBody(in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let openIndex = lines.firstIndex(where: { $0.hasPrefix("```") }),
              let closeOffset = lines[(openIndex + 1)...].firstIndex(where: { $0.hasPrefix("```") })
        else { return nil }
        return lines[(openIndex + 1)..<closeOffset].joined(separator: "\n")
    }

    private static func attempt(_ data: Data) -> TranslationLot? {
        do {
            return try JSONDecoder().decode(TranslationLot.self, from: data)
        } catch {
            return nil
        }
    }
}
