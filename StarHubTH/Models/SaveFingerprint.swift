import Foundation

/// A1-T8/A1-T6 — les empreintes qu'un mod laisse dans une sauvegarde.
///
/// Mesure du 2026-09-23 (sonde sur `Zofia_443716371`, 37 Mo, et
/// `TestOK_444827372`) : les empreintes namespacées portent par
/// `<itemId>`/`<name>` (objets — un même objet porte les deux, il compte une
/// fois), `<buildingType>` (bâtiments) et `<key><string>` (`modData`).
/// Une valeur namespacée hors de ces porteurs — les listes de butin
/// `<string>` — est une *référence*, pas une instance : elle ne compte pas.
/// A1-T9 : le `<name>` d'une `<GameLocation>` compte en lieux, celui d'un
/// `<NPC>` nulle part ; `<treeType>` / `<treeId>` comptent en arbres.
public struct SaveFingerprintScan: Equatable, Sendable {
    /// Empreinte brute namespacée → instances d'objets.
    public var objects: [String: Int]
    /// Empreinte brute namespacée → instances de bâtiments.
    public var buildings: [String: Int]
    /// Clé brute namespacée → occurrences `modData`.
    public var modDataKeys: [String: Int]
    /// Nom namespacé → GameLocations de mods (A1-T9).
    public var locations: [String: Int]
    /// Id d'arbre namespacé (`treeType` / `treeId`) → arbres de mods.
    public var trees: [String: Int]

    public init(
        objects: [String: Int] = [:],
        buildings: [String: Int] = [:],
        modDataKeys: [String: Int] = [:],
        locations: [String: Int] = [:],
        trees: [String: Int] = [:]
    ) {
        self.objects = objects
        self.buildings = buildings
        self.modDataKeys = modDataKeys
        self.locations = locations
        self.trees = trees
    }

    /// Vrai si un mod du parc possède au moins une empreinte ici.
    public var isEmpty: Bool {
        objects.isEmpty && buildings.isEmpty && modDataKeys.isEmpty
            && locations.isEmpty && trees.isEmpty
    }
}

public enum SaveFingerprintScanner {
    /// Parse le XML d'une sauvegarde et compte les empreintes namespacées.
    ///
    /// Retourne `nil` si le XML est illisible — l'appelant ne doit **pas**
    /// cacher un résultat absent (piège du cache d'octets étrangers : un
    /// scan illisible ne vaut pas « zéro empreinte »).
    public static func scan(_ data: Data) -> SaveFingerprintScan? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.sawError else { return nil }
        return delegate.scan
    }

    /// La forme namespacée mesurée sur le parc : `Auteur.Mod` — segments
    /// lettres/chiffres/`_`/`-`/`.`, le premier commençant par une lettre
    /// ASCII, au moins un point suivi d'une lettre. Le résidu vanilla
    /// (`9`, `Lava Katana`, `eventSeen_7001`) n'entre jamais dans le scan.
    static func isNamespaced(_ value: String) -> Bool {
        let chars = Array(value.unicodeScalars)
        guard chars.count >= 3, isASCIIAlpha(chars[0]) else { return false }
        for c in chars.dropFirst() where !(isASCIIAlpha(c) || c.properties.numericType != nil
            || c == "_" || c == "." || c == "-") {
            return false
        }
        guard let last = chars.count > 1 ? chars.count - 1 : nil else { return false }
        for i in 1..<last where chars[i] == "." {
            if isASCIIAlpha(chars[i + 1]) { return true }
        }
        return false
    }

    /// Une clé modData à `/` dont la tête a la forme d'un UniqueID — lettres,
    /// chiffres, `_`, `.`, `-`, première lettre ASCII, **point facultatif**
    /// (`Cropgenics/…`, et `smapi/…`). Les salles vanilla (`Fish Tank/…`)
    /// sont écartées par l'espace ; `Pantry/…` entre et ne résout vers
    /// personne.
    static func isSlashKey(_ value: String) -> Bool {
        guard let slash = value.firstIndex(of: "/") else { return false }
        let head = value[..<slash].unicodeScalars
        guard let first = head.first, isASCIIAlpha(first) else { return false }
        return head.allSatisfy { isASCIIAlpha($0) || $0.properties.numericType != nil
            || $0 == "_" || $0 == "." || $0 == "-" }
    }

    /// Parséur événementiel : chaque élément ouvert tient les empreintes que
    /// ses enfants feuilles lui ont posées ; le comptage se fait **à la
    /// fermeture de l'élément porteur**, une seule fois (name + itemId du
    /// même objet ne comptent donc pas double).
    private final class Delegate: NSObject, XMLParserDelegate {
        struct Frame {
            let tag: String
            var itemId: String?
            var name: String?
            var buildingType: String?
            var modDataKey: String?
            var treeId: String?
        }

        var scan = SaveFingerprintScan()
        var sawError = false
        private var stack: [Frame] = []
        private var accumulator = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            accumulator = ""
            stack.append(Frame(tag: elementName))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            accumulator += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let text = accumulator.trimmingCharacters(in: .whitespacesAndNewlines)
            accumulator = ""
            let closedIndex = stack.count - 1
            // Les clés `<uid>/…` et `smapi/mod-data/<uid>/…` portent un `/`
            // que `isNamespaced` refuse : elles entrent par leur tête.
            if closedIndex > 0, elementName == "string",
                stack[closedIndex - 1].tag == "key",
                isSlashKey(text) {
                stack[closedIndex - 1].modDataKey = text
            }
            // Poser sur le parent par INDEX — stack.last rend une copie.
            if isNamespaced(text), closedIndex > 0 {
                switch elementName {
                case "itemId": stack[closedIndex - 1].itemId = text
                case "name" where stack[closedIndex - 1].name == nil:
                    stack[closedIndex - 1].name = text
                case "buildingType": stack[closedIndex - 1].buildingType = text
                case "treeType", "treeId": stack[closedIndex - 1].treeId = text
                case "string" where stack[closedIndex - 1].tag == "key":
                    stack[closedIndex - 1].modDataKey = text
                default: break
                }
            }
            // Compter l'élément fermé, une seule fois.
            guard closedIndex >= 0 else { return }
            let closed = stack[closedIndex]
            // Le repli `<name>` porte aussi des lieux et des personnages :
            // chacun dans sa famille, un NPC dans aucune (A1-T9).
            if let empreinte = closed.itemId ?? closed.name,
                isNamespaced(empreinte) {
                switch closed.tag {
                case "GameLocation": scan.locations[empreinte, default: 0] += 1
                case "NPC": break
                default: scan.objects[empreinte, default: 0] += 1
                }
            }
            if let arbre = closed.treeId, isNamespaced(arbre) {
                scan.trees[arbre, default: 0] += 1
            }
            if let empreinte = closed.buildingType, isNamespaced(empreinte) {
                scan.buildings[empreinte, default: 0] += 1
            }
            if let cle = closed.modDataKey,
                isNamespaced(cle) || isSlashKey(cle) {
                scan.modDataKeys[cle, default: 0] += 1
            }
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
            sawError = true
        }
    }
}

/// Compteurs d'empreintes d'un mod résolu dans une sauvegarde.
public struct FingerprintCounts: Equatable, Sendable {
    public var objects: Int = 0
    public var buildings: Int = 0
    public var modDataKeys: Int = 0
    public var locations: Int = 0
    public var trees: Int = 0

    public init(objects: Int = 0, buildings: Int = 0, modDataKeys: Int = 0,
                locations: Int = 0, trees: Int = 0) {
        self.objects = objects
        self.buildings = buildings
        self.modDataKeys = modDataKeys
        self.locations = locations
        self.trees = trees
    }

    /// Vrai si le mod possède au moins une empreinte de quelque famille.
    public var isEmpty: Bool {
        objects == 0 && buildings == 0 && modDataKeys == 0 && locations == 0 && trees == 0
    }
}

public enum SaveFingerprintResolution {
    /// Croise un scan avec les UniqueIDs du parc.
    ///
    /// Formes mesurées sur Zofia (7 293 clés modData, 2 185 objets — scan
    /// réel du 2026-09-23), sans ambiguïté (1 125 UniqueIDs, deux saves) :
    /// identique ; préfixe `UniqueID_…` / `UniqueID.…` (objets) ;
    /// convention `<uid>/<clé>` (la masse des clés : ~4 600, dont
    /// `mistyspring.ItemExtensions/…` ×2 064 ; tête entière, insensible à
    /// la casse, uid parfois sans point) ; clé de jeu `<fonction>_<uid>…` — 138 clés mesurées
    /// (`firstVisit_`, `eventSeen_`, `cropMatured_`, `questComplete_`,
    /// `structureBuilt_`) résolues par une règle **générique** — la
    /// fonction est un mot de lettres avant le premier underscore, jamais
    /// une liste codée en dur qui divergerait des mises à jour du jeu ;
    /// et `smapi/mod-data/<uid>/…` (35 clés, 26 mods ; uid en minuscules,
    /// segment entier).
    /// Quand deux ids se préfixent (`A.B`, `A.B_C`), **le plus long gagne**.
    public static func resolve(
        _ scan: SaveFingerprintScan,
        modIDs: Set<String>
    ) -> [String: FingerprintCounts] {
        let triParLongueur = modIDs.sorted { $0.count > $1.count }
        // SMAPI écrit l'uid en minuscules ; les UniqueIDs sont insensibles
        // à la casse.
        let parMinuscules = Dictionary(
            modIDs.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        func proprietaire(_ empreinte: String) -> String? {
            // Forme SMAPI : smapi/mod-data/<uid>/… — l'uid est le segment
            // entier, jamais un préfixe : la suite peut citer un autre mod.
            if empreinte.hasPrefix(smapiModDataPrefix) {
                let suite = empreinte.dropFirst(smapiModDataPrefix.count)
                let segment = suite.prefix { $0 != "/" }
                return parMinuscules[segment.lowercased()]
            }
            // Convention `<uid>/<clé>` : la tête entière est l'uid.
            if let slash = empreinte.firstIndex(of: "/"),
                let uid = parMinuscules[empreinte[..<slash].lowercased()] {
                return uid
            }
            if modIDs.contains(empreinte) { return empreinte }
            let parPrefixe = triParLongueur.first { uid in
                empreinte.hasPrefix(uid + "_") || empreinte.hasPrefix(uid + ".")
            }
            if let uid = parPrefixe { return uid }
            // Clé de jeu : <fonction>_<uid>… — l'uid commence après le
            // premier underscore d'une tête qui n'est qu'un mot de lettres.
            if let sep = empreinte.firstIndex(of: "_") {
                let tete = empreinte[..<sep]
                if !tete.isEmpty, tete.allSatisfy({ $0.isASCII && $0.isLetter }) {
                    let suffixe = empreinte[empreinte.index(after: sep)...]
                    let uid = triParLongueur.first { suffixe == $0
                        || suffixe.hasPrefix($0 + "_")
                        || suffixe.hasPrefix($0 + ".") }
                    if let uid { return uid }
                }
            }
            return nil
        }
        var result: [String: FingerprintCounts] = [:]
        for (empreinte, occurrences) in scan.objects {
            guard let uid = proprietaire(empreinte) else { continue }
            result[uid, default: FingerprintCounts()].objects += occurrences
        }
        for (empreinte, occurrences) in scan.buildings {
            guard let uid = proprietaire(empreinte) else { continue }
            result[uid, default: FingerprintCounts()].buildings += occurrences
        }
        for (cle, occurrences) in scan.modDataKeys {
            guard let uid = proprietaire(cle) else { continue }
            result[uid, default: FingerprintCounts()].modDataKeys += occurrences
        }
        for (lieu, occurrences) in scan.locations {
            guard let uid = proprietaire(lieu) else { continue }
            result[uid, default: FingerprintCounts()].locations += occurrences
        }
        for (arbre, occurrences) in scan.trees {
            guard let uid = proprietaire(arbre) else { continue }
            result[uid, default: FingerprintCounts()].trees += occurrences
        }
        return result
    }
}

/// Préfixe fixe des clés `modData` écrites par l'API de données de SMAPI.
private let smapiModDataPrefix = "smapi/mod-data/"

/// Lettre ASCII — les UniqueIDs du parc et les fonctions de clés du jeu
/// n'en portent pas d'autres (mesure du 2026-09-23).
private func isASCIIAlpha(_ c: Unicode.Scalar) -> Bool {
    (c >= "a" && c <= "z") || (c >= "A" && c <= "Z")
}

/// A1-T8 — le rapport affiché à la bascule : ce que **ces** mods laissent
/// dans **chaque** sauvegarde. La résolution reçoit exactement les
/// UniqueIDs du plan de bascule, donc le rapport ne porte que leurs
/// empreintes — celles du reste du parc restent hors du compte.
public struct SaveFingerprintReport: Equatable, Sendable {
    /// Nom de dossier de save → totaux des mods du plan dans cette save.
    public var perSave: [String: FingerprintCounts]

    public init(perSave: [String: FingerprintCounts] = [:]) {
        self.perSave = perSave
    }

    public var isEmpty: Bool { perSave.isEmpty }

    /// Scan les fichiers de save donnés et totalise les empreintes des ids
    /// du plan. Une save illisible n'entre pas dans le rapport — l'alerte
    /// chiffre ce qu'elle peut lire, elle ne promet pas un audit complet
    /// (l'audit, c'est **A1-T9**) ; si tout est illisible, le rapport est
    /// vide et la bascule procède sans avertissement.
    public static func scanSaves(
        at saveFiles: [(name: String, url: URL)],
        modIDs: Set<String>
    ) -> SaveFingerprintReport {
        guard !modIDs.isEmpty else { return SaveFingerprintReport() }
        var perSave: [String: FingerprintCounts] = [:]
        for save in saveFiles {
            let data: Data
            do {
                data = try Data(contentsOf: save.url)
            } catch {
                continue // illisible → hors rapport (contrat du docstring)
            }
            guard let scan = SaveFingerprintScanner.scan(data) else { continue }
            let resolved = SaveFingerprintResolution.resolve(scan, modIDs: modIDs)
            var total = FingerprintCounts()
            for (_, counts) in resolved { total.add(counts) }
            if !total.isEmpty { perSave[save.name] = total }
        }
        return SaveFingerprintReport(perSave: perSave)
    }

    /// Les saves touchées, les plus chargées d'abord — l'ordre d'affichage.
    public var sortedEntries: [(name: String, counts: FingerprintCounts)] {
        perSave
            .map { (name: $0.key, counts: $0.value) }
            .sorted { $0.counts.total > $1.counts.total }
    }

    /// Combien de saves au-delà de `limit` le résumé tait — pour la ligne
    /// « et N autres sauvegardes » du pire cas (nombre de saves arbitraire).
    public func hiddenCount(beyond limit: Int) -> Int {
        max(0, sortedEntries.count - limit)
    }
}

extension FingerprintCounts {
    /// Somme famille par famille — le total d'un plan de bascule est
    /// l'addition des totaux de ses mods.
    public mutating func add(_ other: FingerprintCounts) {
        objects += other.objects
        buildings += other.buildings
        modDataKeys += other.modDataKeys
        locations += other.locations
        trees += other.trees
    }

    /// Toutes familles confondues — l'ordre d'affichage du rapport.
    public var total: Int { objects + buildings + modDataKeys + locations + trees }
}
