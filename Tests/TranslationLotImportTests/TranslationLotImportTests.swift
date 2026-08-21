import Foundation
import Testing
@testable import StarHubTHCore

struct TranslationLotImportTests {

    private func lot(_ pairs: [(String, String)]) -> TranslationLot {
        TranslationLot(mod: "M", language: "fr",
                       entries: pairs.map {
                           TranslationLot.Entry(component: nil, key: $0.0, source: $0.1,
                                                section: nil, glossary: [:], target: "")
                       })
    }

    private func json(_ lot: TranslationLot, filling targets: [String: String]) -> Data {
        var filled = lot
        filled.entries = filled.entries.map {
            var entry = $0
            entry.target = targets[$0.key] ?? ""
            return entry
        }
        return try! JSONEncoder().encode(filled)
    }

    @Test func aFilledLotComesBackAsAcceptedEntries() throws {
        let sent = lot([("a", "One"), ("b", "Two")])
        let report = try TranslationLotImport.read(
            json(sent, filling: ["a": "Un", "b": "Deux"]), expecting: sent)
        #expect(report.accepted.count == 2)
        #expect(report.accepted.first?.target == "Un")
        #expect(report.rejected.isEmpty)
    }

    /// Une entrée laissée vide n'est pas une erreur : c'est du travail non
    /// fait. Elle est simplement ignorée.
    @Test func anEmptyTargetIsSkippedSilently() throws {
        let sent = lot([("a", "One"), ("b", "Two")])
        let report = try TranslationLotImport.read(
            json(sent, filling: ["a": "Un"]), expecting: sent)
        #expect(report.accepted.map(\.key) == ["a"])
        #expect(report.rejected.isEmpty)
    }

    /// Le chat a perdu une marque dure : cette entrée-là est écartée et
    /// nommée, les autres passent. Rejeter 500 clés pour une seule serait
    /// payer très cher une ligne.
    @Test func anEntryThatLostAHardMarkerIsRejectedAlone() throws {
        let sent = lot([("a", "Hello {{Name}}"), ("b", "Two")])
        let report = try TranslationLotImport.read(
            json(sent, filling: ["a": "Bonjour", "b": "Deux"]), expecting: sent)
        #expect(report.accepted.map(\.key) == ["b"])
        #expect(report.rejected.count == 1)
        #expect(report.rejected.first?.key == "a")
    }

    /// Une source qui a changé depuis l'export ne fait plus tomber le fichier
    /// entier : elle est écartée **entrée par entrée**, avec son motif. C'est
    /// le contrôle `sourceAltered` qui porte l'invariant « ne jamais écrire
    /// sur une clé qui a bougé », pas l'empreinte du fichier.
    @Test func anAlteredSourceIsSetAsideEntryByEntry() throws {
        let sent = lot([("a", "One")])
        let other = lot([("a", "Changed")])
        let report = try TranslationLotImport.read(json(other, filling: ["a": "Un"]),
                                                   expecting: sent)
        #expect(report.accepted.isEmpty)
        #expect(report.rejected.map(\.reason) == [.sourceAltered])
    }

    /// **Le cas qui motive tout ce chemin.** Un chat rend un gros lot en deux
    /// messages : le premier fichier s'importe, ce qui fait sortir ses clés de
    /// l'ensemble éligible et change donc l'empreinte de l'état courant. Le
    /// second fichier ne doit pas être refusé en bloc pour autant — la clé
    /// déjà écrite est simplement inconnue de l'état courant, donc écartée,
    /// et le reste passe.
    @Test func anEntryWrittenSinceTheExportDoesNotSinkTheRest() throws {
        let file = lot([("a", "One"), ("b", "Two")])
        let sent = lot([("b", "Two")])          // « a » a acquis un français
        #expect(file.digest != sent.digest)
        let report = try TranslationLotImport.read(
            json(file, filling: ["a": "Un", "b": "Deux"]), expecting: sent)
        #expect(report.accepted.map(\.key) == ["b"])
        #expect(report.rejected.map(\.key) == ["a"])
        #expect(report.rejected.first?.reason == .unknownKey)
    }

    /// L'autre bout du même chemin : quand l'empreinte diffère **et** que rien
    /// de ce fichier ne concerne l'état courant, il n'y a rien à raconter
    /// entrée par entrée — le refus en bloc reste la bonne réponse.
    @Test func aLotWhereNothingResolvesIsRefusedWhole() {
        let sent = lot([("a", "One")])
        let other = lot([("b", "Two")])
        #expect(throws: TranslationLotImport.FileRefusal.staleDigest) {
            _ = try TranslationLotImport.read(json(other, filling: [:]), expecting: sent)
        }
    }

    /// Une marque dure **en trop** est écartée comme une marque manquante :
    /// `saveTranslation` bloque sur toute divergence dure, dans les deux sens,
    /// et la relecture du lot doit voir exactement la même chose — sans quoi
    /// l'entrée serait acceptée ici puis refusée à l'écriture, et finirait
    /// dans un nombre nu sans clé ni motif.
    @Test func anEntryThatDuplicatesAHardMarkerIsRejectedAlone() throws {
        let sent = lot([("a", "Hello {{Name}}"), ("b", "Two")])
        let report = try TranslationLotImport.read(
            json(sent, filling: ["a": "Bonjour {{Name}} {{Name}}", "b": "Deux"]),
            expecting: sent)
        #expect(report.accepted.map(\.key) == ["b"])
        #expect(report.rejected.map(\.reason) == [.extraHardMarkers(["{{Name}}"])])
    }

    /// Un chat rend volontiers `"Bonjour "` ou `"Bonjour\n"`. Cet espace ne
    /// doit pas atterrir dans le `fr.json` du mod : c'est la valeur élaguée —
    /// celle qui a servi au test de vide — qui est transportée.
    @Test func theAcceptedTargetIsTrimmed() throws {
        let sent = lot([("a", "One")])
        let report = try TranslationLotImport.read(
            json(sent, filling: ["a": "  Un\n"]), expecting: sent)
        #expect(report.accepted.map(\.target) == ["Un"])
    }

    @Test func aLotFromAnotherModIsRefusedWhole() {
        let sent = lot([("a", "One")])
        let elsewhere = TranslationLot(mod: "Autre", language: "fr", entries: sent.entries)
        #expect(throws: TranslationLotImport.FileRefusal.wrongMod) {
            _ = try TranslationLotImport.read(json(elsewhere, filling: ["a": "Un"]),
                                              expecting: sent)
        }
    }

    /// Même mod, même clés, mais une langue différente : la langue fait
    /// partie de l'empreinte, donc ce cas distingue bien le refus
    /// `wrongLanguage` d'un simple `staleDigest` — utile pour surveiller
    /// l'ordre des gardes dans `read`.
    @Test func aLotOfAnotherLanguageIsRefusedWhole() {
        let sent = lot([("a", "One")])
        let autreLangue = TranslationLot(mod: "M", language: "en", entries: sent.entries)
        #expect(throws: TranslationLotImport.FileRefusal.wrongLanguage) {
            _ = try TranslationLotImport.read(json(autreLangue, filling: ["a": "Un"]),
                                              expecting: sent)
        }
    }

    /// Un format de fichier plus récent (ou plus ancien) que celui que ce
    /// build sait lire : refusé en bloc, pas d'entrée par entrée. `formatVersion`
    /// n'étant pas modifiable via l'initialiseur public, on passe par un
    /// aller-retour JSON — ce qui rapproche aussi la fixture de ce qu'un chat
    /// pourrait réellement renvoyer.
    @Test func aLotOfAnUnsupportedFormatVersionIsRefusedWhole() throws {
        let sent = lot([("a", "One")])
        let data = json(sent, filling: ["a": "Un"])
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["formatVersion"] = 2
        let tampered = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: TranslationLotImport.FileRefusal.unsupportedFormat(2)) {
            _ = try TranslationLotImport.read(tampered, expecting: sent)
        }
    }

    /// Un chat rend volontiers son JSON dans une clôture Markdown. Le refuser
    /// pour ça ferait perdre tout le travail.
    @Test func aMarkdownFenceAroundTheJsonIsTolerated() throws {
        let sent = lot([("a", "One")])
        let body = String(decoding: json(sent, filling: ["a": "Un"]), as: UTF8.self)
        let fenced = Data("Voici le résultat :\n```json\n\(body)\n```\n".utf8)
        let report = try TranslationLotImport.read(fenced, expecting: sent)
        #expect(report.accepted.first?.target == "Un")
    }

    /// Nos propres consignes (`TranslationLot.instructions`) demandent au
    /// modèle de préserver les marques `{{Token}}` : une phrase d'introduction
    /// qui en cite une contient donc une accolade **avant** la clôture
    /// Markdown. Un découpage première-`{`/dernière-`}` naïf démarrerait dans
    /// cette phrase et perdrait tout le lot. La clôture doit être reconnue en
    /// priorité.
    @Test func aMarkdownFenceIsFoundEvenWhenTheIntroContainsABrace() throws {
        let sent = lot([("a", "One")])
        let body = String(decoding: json(sent, filling: ["a": "Un"]), as: UTF8.self)
        let fenced = Data(
            "Voici le JSON (j'ai bien gardé les {{Token}}) :\n```json\n\(body)\n```\n".utf8)
        let report = try TranslationLotImport.read(fenced, expecting: sent)
        #expect(report.accepted.first?.target == "Un")
    }

    @Test func anUnreadableFileIsRefusedWhole() {
        let sent = lot([("a", "One")])
        #expect(throws: TranslationLotImport.FileRefusal.unreadable) {
            _ = try TranslationLotImport.read(Data("pas du json".utf8), expecting: sent)
        }
    }

    /// Une clé que le lot n'a jamais envoyée n'entre pas : c'est une invention
    /// du modèle, et elle n'a rien à faire dans le `fr.json` du mod. La clé
    /// inventée est placée **avant** une entrée légitime et remplie ("a") :
    /// avec l'ordre inverse, "a" serait déjà acceptée à une itération
    /// antérieure et un court-circuit sur la dernière itération ne coûterait
    /// rien — le test ne pincerait alors plus rien. Ici, "a" ne peut survivre
    /// que si le traitement continue après le rejet de la clé inventée.
    @Test func anInventedKeyIsRejected() throws {
        let sent = lot([("a", "One")])
        var tampered = sent
        tampered.entries[0].target = "Un"
        tampered.entries.insert(TranslationLot.Entry(component: nil, key: "inventée",
                                                     source: "One", section: nil,
                                                     glossary: [:], target: "Inventé"), at: 0)
        let data = try JSONEncoder().encode(tampered)
        // L'empreinte du fichier reste celle du lot envoyé : c'est le contenu
        // qui a été altéré après coup, pas le lot.
        let report = try TranslationLotImport.read(data, expecting: sent)
        #expect(report.rejected.map(\.key) == ["inventée"])
        #expect(report.accepted.map(\.key) == ["a"])
    }

    /// Une entrée dont l'anglais a été modifié après l'export garde une
    /// empreinte de fichier valide : `digest` ne se recalcule pas depuis
    /// `lot.entries`, il compare la chaîne stockée à celle du lot envoyé. Le
    /// seul rempart restant est la comparaison de `source` entrée par entrée
    /// — c'est elle qu'on éprouve ici, pendant qu'une entrée voisine
    /// inchangée doit continuer à passer.
    @Test func anEntryWithAnAlteredSourceIsRejectedAlone() throws {
        let sent = lot([("a", "One"), ("b", "Two")])
        let data = json(sent, filling: ["a": "Un", "b": "Deux"])
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var entries = object["entries"] as! [[String: Any]]
        for index in entries.indices where entries[index]["key"] as? String == "a" {
            entries[index]["source"] = "One changed"
        }
        object["entries"] = entries
        let tampered = try JSONSerialization.data(withJSONObject: object)
        let report = try TranslationLotImport.read(tampered, expecting: sent)
        #expect(report.accepted.map(\.key) == ["b"])
        #expect(report.rejected.count == 1)
        #expect(report.rejected.first?.key == "a")
        #expect(report.rejected.first?.reason == .sourceAltered)
    }

    /// Un chat normalise volontiers les fins de ligne de ce qu'il renvoie :
    /// une source CRLF revient en LF. L'appariement est **octet à octet**
    /// (en Swift, `\r\n` est un caractère unique et `One\r\nTwo` diffère de
    /// `One\nTwo`) : l'entrée est écartée `.sourceAltered`, jamais « réparée »
    /// en silence — on ne sait pas ce que le chat a normalisé d'autre.
    @Test func aSourceWhoseLineEndingsWereNormalizedIsSetAside() throws {
        let sent = lot([("a", "One\r\nTwo")])
        let normalized = lot([("a", "One\nTwo")])
        let report = try TranslationLotImport.read(
            json(normalized, filling: ["a": "Un\nDeux"]), expecting: sent)
        #expect(report.accepted.isEmpty)
        #expect(report.rejected.map(\.reason) == [.sourceAltered])
    }

    /// L'autre bord : un CRLF qui survit à l'aller-retour du chat passe tel
    /// quel — le `\r\n` interne de la cible est le texte du mod, il ne doit
    /// être ni normalisé ni replié.
    @Test func aSourceAndTargetWhoseCrlfSurvivesTheChatAreKept() throws {
        let sent = lot([("a", "One\r\nTwo")])
        let report = try TranslationLotImport.read(
            json(sent, filling: ["a": "Un\r\nDeux"]), expecting: sent)
        #expect(report.accepted.map(\.target) == ["Un\r\nDeux"])
    }
}

/// Les rangées qu'une entrée acceptée a le droit d'écrire : le miroir
/// exact du filtre d'export, parce qu'un écart entre les deux rendrait le
/// gate d'écriture plus laxiste que celui de la relecture.
struct TranslationLotWritableRowsTests {

    private func row(_ key: String, english: String,
                     state: TranslationCoverage.DiffRow.State) -> TranslationCoverage.DiffRow {
        TranslationCoverage.DiffRow(key: key, english: english, french: "", state: state,
                                    component: nil, section: nil)
    }

    /// Le garde-fou de l'export (`TranslationLot.build` écarte une rangée
    /// sans anglais) doit se refléter ici : une rangée éligible mais sans
    /// référence anglaise n'a pas de clés à écrire.
    @Test func anEligibleRowWithNoEnglishIsNotWritable() {
        let rows = [row("a", english: "", state: .missing)]
        #expect(TranslationLotImport.writableRows(rows).isEmpty)
    }

    /// Une clé dupliquée dont la dernière occurrence a un anglais vide
    /// résout vers l'occurrence pleine — celle-là même que la relecture a
    /// appariée. Sans le garde-fou, l'écriture évaluerait les marques
    /// depuis une source vide : rien ne serait jamais attendu, et une
    /// traduction truffée de marques passerait le gate.
    @Test func aDuplicatedKeyResolvesToItsFilledOccurrence() {
        let rows = [row("a", english: "One", state: .missing),
                    row("a", english: "", state: .missing)]
        let writable = TranslationLotImport.writableRows(rows)
        #expect(writable.count == 1)
        #expect(writable.values.first?.english == "One")
    }

    /// La règle de la relecture, reprise à l'identique : à identité
    /// partagée, la **dernière** occurrence pleine gagne — la même que le
    /// jeu lit (dernière valeur d'une clé dupliquée) et que
    /// `TranslationLotImport.read` retient dans `expected`.
    @Test func theLastFilledOccurrenceOfAKeyWins() {
        let rows = [row("a", english: "One", state: .missing),
                    row("a", english: "Two", state: .missing)]
        let writable = TranslationLotImport.writableRows(rows)
        #expect(writable.values.first?.english == "Two")
    }

    /// Ce qui a déjà un français ne se réécrit pas par ce chemin —
    /// `eligibleRows` l'écarte, comme à l'export.
    @Test func aTranslatedRowIsNotWritable() {
        let rows = [row("a", english: "One", state: .translated)]
        #expect(TranslationLotImport.writableRows(rows).isEmpty)
    }
}
