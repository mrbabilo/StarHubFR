import Foundation
import Testing
@testable import StarHubTHCore

/// La relecture d'un lot revenu d'un **humain** alors que le mod a pu être
/// traduit entre-temps : la fusion juge chaque entrée contre l'état courant
/// **complet** — traduit compris — là où `TranslationLotImport.read` n'apparie
/// que les clés encore à traduire.
struct TranslationLotMergeTests {

    private func rows(_ triples: [(String, String, String)],
                      state: TranslationCoverage.DiffRow.State = .missing)
        -> [TranslationCoverage.DiffRow] {
        triples.map {
            TranslationCoverage.DiffRow(key: $0.0, english: $0.1, french: $0.2,
                                        state: $0.2.isEmpty
                                            ? (state == .missing ? .missing : state)
                                            : .translated)
        }
    }

    private func lot(_ entries: [(String, String, String)]) -> TranslationLot {
        TranslationLot(mod: "M", language: "fr",
                       entries: entries.map {
                           TranslationLot.Entry(component: nil, key: $0.0, source: $0.1,
                                                section: nil, glossary: [:], target: $0.2)
                       })
    }

    @Test func aFilledEntryOnAMissingKeyIsProposedForImmediateWrite() throws {
        let current = rows([("a", "One", ""), ("b", "Two", "")])
        let data = try JSONEncoder().encode(lot([("a", "One", "Un")]))
        let review = try TranslationLotMerge.review(data, rows: current,
                                                    mod: "M", language: "fr")
        #expect(review.proposals.count == 1)
        #expect(review.proposals.first?.disposition == .writeNow)
        #expect(review.proposals.first?.incoming == "Un")
        #expect(review.rejections.isEmpty)
    }

    // MARK: - Pins sémantiques

    /// Les deux côtés ont traduit, différemment : divergence à arbitrer —
    /// et jamais une écriture directe sur un français existant.
    @Test func aDifferentValueOnATranslatedKeyIsADivergence() throws {
        let current = rows([("a", "One", "Une fois")])
        let data = try JSONEncoder().encode(lot([("a", "One", "Un")]))
        let review = try TranslationLotMerge.review(data, rows: current,
                                                    mod: "M", language: "fr")
        #expect(review.proposals.count == 1)
        #expect(review.proposals.first?.disposition == .divergent)
        #expect(review.proposals.first?.currentFrench == "Une fois")
    }

    /// Même valeur des deux côtés (à l'espace près) : rien à faire. Le trim
    /// des deux côtés évite le bruit des espaces traînants et des fins CRLF.
    @Test func theSameValueIsIdenticalEvenWithTrailingWhitespace() throws {
        let current = rows([("crlf", "One", "Un\r\n"), ("spaces", "Two", " Deux ")])
        let data = try JSONEncoder().encode(lot([("crlf", "One", "Un"),
                                                 ("spaces", "Two", "Deux")]))
        let review = try TranslationLotMerge.review(data, rows: current,
                                                    mod: "M", language: "fr")
        #expect(review.proposals.map(\.disposition) == [.identical, .identical])
    }

    /// Cible non remplie : travail non fait, pas une divergence — même si le
    /// français existe déjà.
    @Test func anUnfilledTargetStaysUnfilled() throws {
        let current = rows([("a", "One", "Une fois")])
        let data = try JSONEncoder().encode(lot([("a", "One", "")]))
        let review = try TranslationLotMerge.review(data, rows: current,
                                                    mod: "M", language: "fr")
        #expect(review.proposals.count == 1)
        #expect(review.proposals.first?.disposition == .unfilled)
    }

    /// Une clé que l'état courant ne connaît pas : écartée nommément — mais
    /// dès qu'une autre clé résout, le fichier entier reste reçu. Le refus en
    /// bloc ne survit qu'au lot qui ne touche rien (`staleLot`).
    @Test func anUnknownKeyIsRejectedAlone() throws {
        let current = rows([("a", "One", "")])
        let data = try JSONEncoder().encode(lot([("a", "One", "Un"),
                                                 ("zzz", "Elsewhere", "Ailleurs")]))
        let review = try TranslationLotMerge.review(data, rows: current,
                                                    mod: "M", language: "fr")
        #expect(review.proposals.map(\.key) == ["a"])
        #expect(review.rejections.map(\.reason) == [.unknownKey])
    }

    /// L'anglais a bougé depuis l'export du traducteur : jamais écrit sur
    /// l'ancien anglais — écartée entrée par entrée.
    @Test func anAlteredSourceIsRejectedEntryByEntry() throws {
        let current = rows([("a", "One day, long ago", "")])
        let data = try JSONEncoder().encode(lot([("a", "One", "Un")]))
        let review = try TranslationLotMerge.review(data, rows: current,
                                                    mod: "M", language: "fr")
        #expect(review.rejections.map(\.reason) == [.sourceAltered])
    }

    /// Le lot d'un autre moment : **aucune** de ses clés ne figure dans
    /// l'état courant complet (traduit compris).
    @Test func aLotMatchingNothingAtAllIsRefusedInBlock() throws {
        let current = rows([("a", "One", "Une fois")])
        let data = try JSONEncoder().encode(lot([("x", "Old", "Vieux")]))
        #expect(throws: TranslationLotMerge.FileRefusal.staleLot) {
            try TranslationLotMerge.review(data, rows: current, mod: "M", language: "fr")
        }
    }

    /// Mauvais mod, mauvaise langue, format inconnu : refus en bloc, avant
    /// toute lecture d'entrée — les mêmes seuils que la relecture du lot IA.
    @Test func wrongModWrongLanguageAndFormatAreRefusedInBlock() throws {
        let current = rows([("a", "One", "")])
        let data = try JSONEncoder().encode(lot([("a", "One", "Un")]))
        #expect(throws: TranslationLotMerge.FileRefusal.wrongMod) {
            try TranslationLotMerge.review(data, rows: current, mod: "Autre", language: "fr")
        }
        #expect(throws: TranslationLotMerge.FileRefusal.wrongLanguage) {
            try TranslationLotMerge.review(data, rows: current, mod: "M", language: "de")
        }
        #expect(throws: TranslationLotMerge.FileRefusal.unsupportedFormat(7)) {
            let other: [String: Any] = ["formatVersion": 7, "mod": "M", "language": "fr",
                                        "instructions": [], "entries": []]
            let encoded = try JSONSerialization.data(withJSONObject: other)
            try TranslationLotMerge.review(encoded, rows: current, mod: "M", language: "fr")
        }
    }

    /// Un chat rend volontiers son JSON dans une clôture Markdown, précédé
    /// d'une phrase : la fusion relit le même genre de fichier que le lot IA,
    /// la même formule de décodage s'applique.
    @Test func aFencedChatAnswerIsDecoded() throws {
        let current = rows([("a", "One", "")])
        let json = String(data: try JSONEncoder().encode(lot([("a", "One", "Un")])),
                          encoding: .utf8)!
        let fenced = Data("Voici votre traduction :\n```json\n\(json)\n```\nBonne journée.".utf8)
        let review = try TranslationLotMerge.review(fenced, rows: current,
                                                    mod: "M", language: "fr")
        #expect(review.proposals.count == 1)
        #expect(review.proposals.first?.disposition == .writeNow)
    }

    // MARK: - Gate de marques dures

    /// Une marque dure perdue : l'entrée est écartée et nommée — l'écriture
    /// la refuserait de toute façon, mieux vaut le dire à la relecture.
    @Test func anEntryThatLostAHardMarkerIsRejectedAlone() throws {
        let current = rows([("a", "Hello {{Name}}", ""), ("b", "Two", "")])
        let data = try JSONEncoder().encode(lot([("a", "Hello {{Name}}", "Bonjour"),
                                                 ("b", "Two", "Deux")]))
        let review = try TranslationLotMerge.review(data, rows: current,
                                                    mod: "M", language: "fr")
        #expect(review.proposals.map(\.key) == ["b"])
        #expect(review.rejections.count == 1)
        #expect(review.rejections.first?.key == "a")
        #expect(review.rejections.first?.reason ==
                .missingHardMarkers(["{{Name}}"]))
    }

    /// Une marque dure inventée : même écart, autre motif.
    @Test func anEntryWithAnExtraHardMarkerIsRejectedAlone() throws {
        let current = rows([("a", "Two", "")])
        let data = try JSONEncoder().encode(lot([("a", "Two", "Deux {{bonus}}")]))
        let review = try TranslationLotMerge.review(data, rows: current,
                                                    mod: "M", language: "fr")
        #expect(review.rejections.count == 1)
        #expect(review.rejections.first?.reason == .extraHardMarkers(["{{bonus}}"]))
    }

    // MARK: - Dédoublonnage

    /// Deux entrées de même identité dans un même fichier : la dernière gagne
    /// — le même filtre que `writableRows` applique à l'export, l'écriture
    /// doit résoudre vers la même occurrence.
    @Test func theLastOccurrenceOfAnIdentityWins() throws {
        let current = rows([("a", "One", "")])
        let data = try JSONEncoder().encode(lot([("a", "One", "Faux"),
                                                 ("a", "One", "Un")]))
        let review = try TranslationLotMerge.review(data, rows: current,
                                                    mod: "M", language: "fr")
        #expect(review.proposals.count == 1)
        #expect(review.proposals.first?.incoming == "Un")
    }
}
