import Foundation

/// Ce que smapi.io sait de la compatibilité d'un mod avec la version du jeu.
///
/// La donnée arrivait déjà à chaque vérification — `compatibilityStatus`,
/// `compatibilitySummary`, `brokeIn` — et repartait à la poubelle : rien ne la
/// décodait, rien ne l'affichait. Ce type la retient sous une forme montrable.
///
/// **Mesuré sur le parc réel le 2026-08-25, 840 mods interrogés** — c'est ce
/// que cette fonctionnalité peut dire, et pas davantage :
/// - **552 sans aucun statut** (66 %) : smapi.io ne connaît pas ces mods. Leur
///   silence n'est pas un blanc-seing, et rien ne doit le présenter comme tel.
/// - **281 `Ok`**, **5 `Unofficial`**, **2 `Workaround`**, et aucun `Broken`,
///   `Abandoned` ni `Obsolete`.
/// - Les sept signalés portent tous un `brokeIn` (« Stardew Valley 1.6 », une
///   fois « 1.5 ») et **aucun `suggestedUpdate`** : ils sont invisibles pour la
///   liste des mises à jour, qui ne montre que ce qui a une version plus
///   récente.
public struct ModCompatibility: Codable, Equatable, Sendable {

    /// Les verdicts de smapi.io. `Ok` en fait partie : ne pas le retenir
    /// reviendrait à confondre « vérifié et sain » avec « inconnu », qui sont
    /// deux choses très différentes quand deux tiers du parc sont inconnus.
    public enum Status: String, Codable, Equatable, Sendable {
        case ok, unofficial, workaround, broken, abandoned, obsolete

        /// `true` quand le mod demande une décision de l'utilisateur.
        public var needsAttention: Bool { self != .ok }

        /// De quoi comparer deux verdicts — un pack porte celui du **plus
        /// grave** de ses composants, puisque c'est le dossier qu'on active,
        /// pas ses enfants.
        ///
        /// `broken` et `abandoned` en tête : rien n'est proposé pour les
        /// remplacer. `obsolete` ensuite (le jeu fait désormais la chose
        /// lui-même), puis `unofficial` et `workaround`, qui ont l'un et
        /// l'autre une voie de sortie.
        public var severity: Int {
            switch self {
            case .ok:         return 0
            case .workaround: return 1
            case .unofficial: return 2
            case .obsolete:   return 3
            case .abandoned:  return 4
            case .broken:     return 5
            }
        }
    }

    /// Un lien que portait la phrase de smapi.io.
    public struct Link: Codable, Equatable, Sendable {
        public let label: String
        public let url: String

        public init(label: String, url: String) {
            self.label = label
            self.url = url
        }
    }

    public let status: Status
    /// La version du jeu qui a cassé le mod, telle que smapi.io la nomme :
    /// « Stardew Valley 1.6 ». C'est ce qui transforme « ce mod a planté » en
    /// « ce mod est cassé depuis la 1.6 ».
    public let brokeIn: String?
    /// La phrase de smapi.io, débarrassée de son balisage.
    public let summary: String
    /// Ce vers quoi elle pointait, dans l'ordre où elle les citait.
    ///
    /// **C'est ici qu'est l'action, pas dans le champ `unofficial`.** Mesuré :
    /// sur les sept mods signalés du parc, `unofficial` n'est renseigné que
    /// deux fois, et son URL pointe vers `smapi.io/mods#saat.mod` — la page qui
    /// vient de répondre. Les liens utiles (mod de remplacement, correctif non
    /// officiel du forum, dépôt GitHub) vivent dans la phrase.
    public let links: [Link]

    public init(status: Status, brokeIn: String?, summary: String, links: [Link]) {
        self.status = status
        self.brokeIn = brokeIn
        self.summary = summary
        self.links = links
    }

    /// Le verdict tiré des métadonnées d'une réponse smapi.io, ou `nil` quand
    /// il n'y en a pas.
    ///
    /// Un statut que ce type ne connaît pas rend `nil` plutôt qu'une valeur de
    /// repli : smapi.io peut en ajouter un demain, et le ranger d'office parmi
    /// les sains serait le pire des deux.
    public static func from(status rawStatus: String?, brokeIn: String?,
                            summary rawSummary: String?) -> ModCompatibility? {
        guard let rawStatus,
              let status = Status(rawValue: rawStatus.lowercased()) else { return nil }
        let parsed = parseSummary(rawSummary ?? "")
        return ModCompatibility(status: status,
                                brokeIn: brokeIn?.trimmed.nonEmpty,
                                summary: parsed.text,
                                links: parsed.links)
    }

    /// Sépare la phrase de smapi.io de ses liens.
    ///
    /// Le format n'est documenté nulle part ; il est relevé sur les sept
    /// résumés réels du parc, qui mêlent trois balisages :
    /// - des liens Markdown `[libellé](url)` — un ou deux par phrase ;
    /// - des `<small>…</small>` autour d'un numéro de version, qu'on garde :
    ///   « 1.1.3-unofficial.1-p1xel8ted » est justement ce qu'il faut installer ;
    /// - un `⚠` de tête, que l'interface porte déjà par son icône.
    ///
    /// Affichée telle quelle, la phrase montrerait ce balisage à l'utilisateur.
    public static func parseSummary(_ raw: String) -> (text: String, links: [Link]) {
        var links: [Link] = []
        var text = ""
        var rest = Substring(raw)

        while let open = rest.firstIndex(of: "[") {
            // Un `[` sans le `](url)` qui le suit n'est pas un lien : c'est un
            // crochet ordinaire, et il reste dans la phrase.
            guard let close = rest[open...].firstIndex(of: "]"),
                  rest.index(after: close) < rest.endIndex,
                  rest[rest.index(after: close)] == "(",
                  let urlEnd = rest[close...].firstIndex(of: ")") else {
                text += rest[..<rest.index(after: open)]
                rest = rest[rest.index(after: open)...]
                continue
            }
            let label = String(rest[rest.index(after: open)..<close])
            let url = String(rest[rest.index(close, offsetBy: 2)..<urlEnd])
            text += rest[..<open] + label
            links.append(Link(label: label, url: url))
            rest = rest[rest.index(after: urlEnd)...]
        }
        text += rest

        return (cleanUp(text), links)
    }

    /// Retire le balisage résiduel : les `<small>` qui encadrent un numéro de
    /// version, et l'avertissement de tête que l'icône dit déjà.
    private static func cleanUp(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "<small>", with: "")
            .replacingOccurrences(of: "</small>", with: "")
        while let first = text.first, first == "⚠" || first.isWhitespace {
            text.removeFirst()
        }
        return text.trimmed
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
