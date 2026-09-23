import Foundation

// A1-T10 — le geste de nettoyage : retirer d'une sauvegarde les clés
// `smapi/mod-data/<uid>` des mods **disparus** du parc. Qui est disparu,
// c'est `SaveAbsentMods.absentKeyCounts` qui le dit (même règle que la
// section de la fiche, `legacy-migrated` compris) ; ce type, lui, travaille
// sur le **texte** du XML.
//
// Forme mesurée sur Zofia (2026-09-23, 35/35 items ciblés) :
//   <item><key><string>smapi/mod-data/<uid>/<clé></string></key>
//        <value><string>…</string></value></item>
// Les dictionnaires <modData> sont partout dans le fichier (4 804 dans
// Zofia) : le parcours est global, comme le scan de la section. Un item
// de forme différente est **laissé** et rapporté — jamais de perte
// silencieuse. Rien d'autre que ces items ne bouge.

public struct RemovalResult: Equatable, Sendable {
    /// Le texte nouveau — identique à l'entrée si rien n'est retiré.
    public let content: String
    /// Clés complètes retirées, dans l'ordre du fichier.
    public let removedKeys: [String]
    /// Clés de mods disparus portées par un item atypique, laissé en place.
    public let untouchedKeys: [String]

    public init(content: String, removedKeys: [String], untouchedKeys: [String]) {
        self.content = content
        self.removedKeys = removedKeys
        self.untouchedKeys = untouchedKeys
    }
}

public enum SaveAbsentModsRemoval {
    private struct Occurrence {
        let key: String
        let uid: String
        /// Plage de l'item entier ; `nil` quand sa forme est atypique.
        let span: Range<String.Index>?
    }

    public static func removing(from content: String, mods: [ModItem]) -> RemovalResult {
        let occurrences = scan(content)
        var counts: [String: Int] = [:]
        for occurrence in occurrences { counts[occurrence.key, default: 0] += 1 }
        let absents = Set(SaveAbsentMods.absentKeyCounts(counts, mods: mods).keys)

        var spans: [Range<String.Index>] = []
        var removedKeys: [String] = []
        var untouchedKeys: [String] = []
        for occurrence in occurrences where absents.contains(occurrence.uid) {
            if let span = occurrence.span {
                spans.append(span)
                removedKeys.append(occurrence.key)
            } else {
                untouchedKeys.append(occurrence.key)
            }
        }
        guard !spans.isEmpty else {
            return RemovalResult(content: content, removedKeys: [], untouchedKeys: untouchedKeys)
        }
        var texte = content
        for span in spans.reversed() { texte.removeSubrange(span) }
        return RemovalResult(content: texte, removedKeys: removedKeys, untouchedKeys: untouchedKeys)
    }

    private static func scan(_ content: String) -> [Occurrence] {
        let prefixe = "smapi/mod-data/"
        let marqueur = "<item><key><string>" + prefixe
        let finDeClé = "</string>"
        let suiteAttendue = "</string></key><value><string>"
        let finDItem = "</item>"

        var result: [Occurrence] = []
        var curseur = content.startIndex
        while let début = content.range(of: marqueur, range: curseur..<content.endIndex) {
            let cléDébut = content.index(début.upperBound, offsetBy: -prefixe.count)
            guard let cléFin = content.range(of: finDeClé, range: début.upperBound..<content.endIndex)
            else { break }
            let clé = String(content[cléDébut..<cléFin.lowerBound])
            let uid = clé.dropFirst(prefixe.count).prefix { $0 != "/" }.lowercased()
            // Forme régulière : la clé est immédiatement suivie de
            // `</key><value><string>`, et l'item se referme.
            if content[cléFin.lowerBound...].hasPrefix(suiteAttendue),
               let fin = content.range(of: finDItem, range: cléFin.upperBound..<content.endIndex) {
                result.append(Occurrence(key: clé, uid: uid, span: début.lowerBound..<fin.upperBound))
                curseur = fin.upperBound
            } else {
                // Atypique : laissé, on repart après la clé.
                result.append(Occurrence(key: clé, uid: uid, span: nil))
                curseur = cléFin.upperBound
            }
        }
        return result
    }
}
