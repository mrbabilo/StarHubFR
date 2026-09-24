import Foundation

/// La lecture partagée d'un fichier de lot : le décodage (y compris la
/// clôture Markdown d'un chat) et l'identité d'une entrée.
///
/// Depuis C3-T5, la relecture d'un lot vit dans `TranslationLotMerge` — elle
/// juge chaque entrée contre l'état courant **complet**, traduit compris.
/// Ce type ne garde que ce que la fusion partage : une seule formule de
/// décodage et une seule formule d'identité ont le droit d'exister — deux
/// formules divergeraient.
public enum TranslationLotImport {

    /// Les motifs d'écart d'une entrée, partagés par la fusion. Le compte
    /// rendu (`Accepted`/`Report` du lot IA) a suivi `read` à la retraite :
    /// la fusion porte ses propres propositions.
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

        init(component: String?, key: String, reason: Reason) {
            self.component = component
            self.key = key
            self.reason = reason
        }
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
    ///
    /// Interne (pas privé) : `TranslationLotMerge.review` relit le même genre
    /// de fichier — un JSON de lot, parfois revenu d'un chat — et une seule
    /// formule de décodage a le droit d'exister.
    static func decode(_ data: Data) -> TranslationLot? {
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
