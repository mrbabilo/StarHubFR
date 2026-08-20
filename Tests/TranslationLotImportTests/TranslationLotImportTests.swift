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

    /// Un fichier qui ne correspond plus au mod est refusé **en bloc**, avant
    /// toute écriture : le mod a bougé depuis l'export.
    @Test func aLotWhoseDigestNoLongerMatchesIsRefusedWhole() {
        let sent = lot([("a", "One")])
        let other = lot([("a", "Changed")])
        #expect(throws: TranslationLotImport.FileRefusal.staleDigest) {
            _ = try TranslationLotImport.read(json(other, filling: ["a": "Un"]),
                                              expecting: sent)
        }
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
    /// du modèle, et elle n'a rien à faire dans le `fr.json` du mod. Une
    /// entrée légitime et remplie voisine ("a") doit survivre : sinon rien ne
    /// prouve que c'est bien la clé inventée qui a été identifiée, plutôt
    /// qu'un court-circuit qui n'atteint jamais son traitement.
    @Test func anInventedKeyIsRejected() throws {
        let sent = lot([("a", "One")])
        var tampered = sent
        tampered.entries[0].target = "Un"
        tampered.entries.append(TranslationLot.Entry(component: nil, key: "inventée",
                                                     source: "One", section: nil,
                                                     glossary: [:], target: "Inventé"))
        let data = try JSONEncoder().encode(tampered)
        // L'empreinte du fichier reste celle du lot envoyé : c'est le contenu
        // qui a été altéré après coup, pas le lot.
        let report = try TranslationLotImport.read(data, expecting: sent)
        #expect(report.accepted.map(\.key) == ["a"])
        #expect(report.rejected.map(\.key) == ["inventée"])
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
}
