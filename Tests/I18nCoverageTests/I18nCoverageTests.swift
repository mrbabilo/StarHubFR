import Testing
import Foundation
@testable import StarHubTHCore

// MARK: - Test helpers

/// Un dossier `i18n/` jetable, peuplé à partir de chemins relatifs.
/// `cleanup()` doit être appelé via `defer`, comme dans les suites de backup.
struct I18nFixture {
    let directory: URL

    /// - Parameter files: chemins relatifs au dossier `i18n`, par exemple
    ///   `"fr.json"` (layout A) ou `"fr/dialogue.json"` (layout B).
    init(files: [String]) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("i18n-fixture-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("i18n", isDirectory: true)
        for relative in files {
            let url = directory.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }
}

/// Le parseur i18n laxiste : il reproduit la tolérance du chargeur SMAPI
/// (Newtonsoft.Json) en 4 passes string-aware — commentaires, virgules
/// trailing, clés nues, caractères de contrôle bruts — pour ne refuser
/// aucun fichier qu'un auteur a écrit à la main et que le jeu charge.
/// Port fidèle de `scanner.rs` (Nana1873/stardew-i18n-translator).
struct I18nLenientParserTests {
    @Test func parsesCleanFlatObject() throws {
        let json = #"{"a": "Hello", "b": "World"}"#
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "Hello")
        #expect(out["b"] == "World")
        #expect(out.count == 2)
    }

    @Test func stripsLineComments() throws {
        // Vue en conditions réelles (Sebastian's Frog Sanctuary) : des `//`
        // servent de séparateurs de section devant les clés.
        let json = """
        {
            // Config
            "config.name": "Frogs",
            // Dialogue
            "dialogue": "Hi"
        }
        """
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["config.name"] == "Frogs")
        #expect(out["dialogue"] == "Hi")
        #expect(out.count == 2)
    }

    @Test func doesNotStripDoubleSlashInsideAString() throws {
        // Une URL ou un chemin dans une valeur ne doit pas être coupé.
        let json = #"{"url": "https://nexusmods.com/x"}"#
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["url"] == "https://nexusmods.com/x")
    }

    @Test func stripsBlockComments() throws {
        let json = """
        { /* a comment */
            "a": "1" /* trailing */,
            "b": "2"
        }
        """
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "1")
        #expect(out["b"] == "2")
    }

    @Test func stripsTrailingCommas() throws {
        let json = #"{"a": "1", "b": "2",}"#
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out.count == 2)
        #expect(out["b"] == "2")
    }

    @Test func trailingCommaRemovalIsStringAware() throws {
        // Une virgule suivie de `}` dans une valeur ne doit pas être retirée —
        // seul le séparateur structural trailing l'est. Un regex non
        // string-aware corromprait `"x,}"` en `"x}"`. (Bug évité dans la réf.)
        let out = try #require(try? I18nLenientParser.parse(#"{"a": "x,}",}"#))
        #expect(out["a"] == "x,}")
        #expect(out.count == 1)
    }

    @Test func quotesBareJavaScriptStyleKeys() throws {
        // Newtonsoft accepte les clés non quotées ; JSONSerialization non.
        let out = try #require(try? I18nLenientParser.parse(#"{ Key: "v", "other": "w" }"#))
        #expect(out["Key"] == "v")
        #expect(out["other"] == "w")
    }

    @Test func doesNotQuoteBareLookingTextInValues() throws {
        // Le quantage des clés nues n'agit qu'en position de clé (après `{`/`,`),
        // jamais dans une valeur.
        let out = try #require(try? I18nLenientParser.parse(#"{"a": "not: a key"}"#))
        #expect(out["a"] == "not: a key")
    }

    @Test func stripsBom() throws {
        let json = "\u{FEFF}" + #"{"a": "1"}"#
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "1")
    }

    @Test func escapesRawNewlineInsideAString() throws {
        // SMAPI accepte un raw \n dans une valeur ; JSON strict non.
        // Le parseur l'échappe avant JSONSerialization.
        let json = "{\n\"a\": \"line one\nline two\"\n}"
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "line one\nline two")
    }

    @Test func stripsLineCommentsInACrlfFile() throws {
        // Cas réel ([CP] Cornucopia More Flowers) : fichier en CRLF avec des
        // commentaires de section. En Swift, `\r\n` est **un seul** Character —
        // le comparer à `"\n"` échoue, et un parcours par Character fait courir
        // la coupure du commentaire jusqu'à la fin du fichier.
        let json = "{\r\n\t// Crop produce\r\n  \"a\": \"1\",\r\n  \"b\": \"2\"\r\n}"
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "1")
        #expect(out["b"] == "2")
        #expect(out.count == 2)
    }

    @Test func stripsLineCommentsTerminatedByALoneCarriageReturn() throws {
        // Fins de ligne héritées de Mac OS classique : le commentaire s'arrête
        // au `\r` seul comme il s'arrêterait à un `\n`.
        let json = "{\r // note\r \"a\": \"1\"\r}"
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "1")
    }

    @Test func escapesRawCrlfInsideAString() throws {
        // Même racine que ci-dessus, passe 4 : le cluster `\r\n` ne correspond
        // ni au cas `"\n"` ni au cas `"\r"` et resterait brut dans le JSON.
        let json = "{\"a\": \"line one\r\nline two\"}"
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "line one\r\nline two")
    }

    @Test func ignoresDollarSchemaKey() throws {
        let json = #"{"$schema": "http://…", "a": "1"}"#
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out.count == 1)
        #expect(out["a"] == "1")
    }

    @Test func rejectsMalformedJson() throws {
        #expect(throws: I18nLenientParser.ParseError.self) {
            _ = try I18nLenientParser.parse("{not json at all")
        }
    }

    @Test func rejectsNonStringValue() throws {
        // Un objet i18n SMAPI est plat et string-string ; une valeur
        // non-string n'en est pas un.
        #expect(throws: I18nLenientParser.ParseError.self) {
            _ = try I18nLenientParser.parse(#"{"a": 42}"#)
        }
    }

    @Test func parsesARealShape() throws {
        // Forme réelle observée (.StorageTerminal) : indentation, lignes vides,
        // tokens entre accolades.
        let json = """
        {
            "menu.network-chests.one": "Network: {{count}} chest linked",
            "menu.filtered-count": "   [{{shown}}/{{total}} filtered]"
        }
        """
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["menu.network-chests.one"] == "Network: {{count}} chest linked")
    }
}

/// Ce que SMAPI **charge réellement**. Le parseur va plus loin que lui pour
/// pouvoir lire un fichier abîmé ; cette fonction dit si le jeu l'accepterait.
/// Sans elle, un mod afficherait « 100 % traduit » alors que son français ne se
/// chargera jamais — l'inverse du service rendu.
struct I18nSmapiAcceptanceTests {
    @Test func whatSmapiToleratesIsAccepted() throws {
        // Commentaires et virgules trailing : le schéma officiel i18n.json les
        // autorise (allowComments, allowTrailingCommas).
        #expect(I18nLenientParser.smapiAccepts(#"{"a": "1"}"#))
        #expect(I18nLenientParser.smapiAccepts("{\n // note\n \"a\": \"1\",\n}"))
    }

    @Test func crlfLineEndingsStayAcceptedBySmapi() throws {
        // Un CRLF entre deux entrées est une espace JSON parfaitement légale :
        // la réparation ne doit pas s'y déclencher, sinon la moitié du parc de
        // fichiers (écrits sous Windows) serait signalée à tort comme refusée
        // par le jeu.
        #expect(I18nLenientParser.smapiAccepts("{\r\n\t// note\r\n  \"a\": \"1\",\r\n}"))
    }

    @Test func ordinaryBareKeysAreAcceptedBySmapi() throws {
        // Mesuré sur la `Newtonsoft.Json.dll` du jeu : une clé nue passe tant
        // qu'elle reste dans son jeu de caractères — lettres, chiffres, `_`, `$`.
        #expect(I18nLenientParser.smapiAccepts(#"{ Key: "v" }"#))
        #expect(I18nLenientParser.smapiAccepts(#"{ key_1: "v", $x: "w", clé: "y" }"#))
    }

    @Test func dottedOrHyphenatedBareKeysAreRejectedBySmapi() throws {
        // C'est là que Newtonsoft s'arrête, et c'est le seul cas où notre
        // réparation de clé nue signale un refus du jeu. Les clés i18n étant
        // pointées par convention, la distinction n'est pas théorique.
        #expect(!I18nLenientParser.smapiAccepts(#"{ config.name: "v" }"#))
        #expect(!I18nLenientParser.smapiAccepts(#"{ my-key: "v" }"#))
    }

    @Test func rawControlCharactersAreAcceptedBySmapi() throws {
        // Newtonsoft lit un retour à la ligne ou une tabulation bruts dans une
        // valeur ; seul `JSONSerialization` les refuse, d'où notre passe 4.
        #expect(I18nLenientParser.smapiAccepts("{\"a\": \"line one\nline two\"}"))
        #expect(I18nLenientParser.smapiAccepts("{\"a\": \"col\tonne\"}"))
    }

    @Test func aFileSmapiRefusesIsStillReadable() throws {
        // Les deux réponses sont indépendantes : on lit, et on signale.
        let text = #"{ config.name: "v" }"#
        #expect((try? I18nLenientParser.parse(text)) != nil)
        #expect(!I18nLenientParser.smapiAccepts(text))
    }

    @Test func malformedJsonIsNotAcceptedEither() throws {
        #expect(!I18nLenientParser.smapiAccepts("{not json at all"))
    }
}

/// La couverture de traduction d'un mod : combien de clés de l'anglais de
/// référence sont réellement traduites en français, et ce qui cloche pour les
/// autres. C'est le calcul que la liste et la fiche mod afficheront.
struct TranslationCoverageTests {
    /// Compare deux pourcentages sans exiger l'égalité binaire : `1/3*100` et
    /// `100/3` ne suivent pas le même ordre d'opérations et peuvent différer du
    /// dernier bit. Un test qui passerait ici et échouerait sur une autre
    /// chaîne d'outils serait pire que pas de test.
    private func isClose(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.000_001 }

    @Test func fullTranslationIs100Percent() {
        let c = TranslationCoverage.compute(source: ["a": "X", "b": "Y"],
                                            target: ["a": "Xfr", "b": "Yfr"])
        #expect(c.total == 2)
        #expect(c.translated == 2)
        #expect(c.missing.isEmpty)
        #expect(c.orphan.isEmpty)
        #expect(isClose(c.percent, 100))
    }

    @Test func missingKeysAreReported() {
        let c = TranslationCoverage.compute(source: ["a": "1", "b": "2", "c": "3"],
                                            target: ["a": "1fr"])
        #expect(c.total == 3)
        #expect(c.translated == 1)
        #expect(c.missing == ["b", "c"])
        #expect(isClose(c.percent, 100.0 / 3.0))
    }

    @Test func orphanKeysExistOnlyInTarget() {
        let c = TranslationCoverage.compute(source: ["a": "1"],
                                            target: ["a": "1fr", "z": "extra"])
        #expect(c.orphan == ["z"])
    }

    @Test func anEmptyValueIsWorseThanAMissingKey() {
        // Vérifié dans les sources de SMAPI (`Framework/Translator.cs`,
        // `Translation.cs`) : `GetRaw` fait `TryGetValue` — la clé existe, donc
        // il retourne `""` sans jamais consulter `default.json`. Une clé
        // **absente** laisse l'anglais s'afficher (bénin) ; une clé **vide**
        // affiche un texte de remplacement (cassé). Les deux ne peuvent pas être
        // comptées ensemble.
        let c = TranslationCoverage.compute(source: ["a": "1", "b": "2"],
                                            target: ["a": ""])
        #expect(c.translated == 0)
        #expect(c.empty == ["a"])
        #expect(c.missing == ["b"])
    }

    @Test func aWhitespaceOnlyValueCountsAsEmpty() {
        // Une valeur faite d'espaces n'est pas « vide » au sens de SMAPI :
        // `HasValue()` teste `!IsNullOrEmpty`, donc le jeu affiche bel et bien
        // les espaces — c'est-à-dire rien, et sans le texte de remplacement qui
        // aurait au moins signalé le problème. Du point de vue du joueur c'est
        // le pire des deux cas ; il se compte avec les vides.
        // (Comportement repris de `stardew-i18n-translator`, recoupé sur
        // `Translation.cs`.)
        let c = TranslationCoverage.compute(source: ["a": "1"], target: ["a": "   "])
        #expect(c.translated == 0)
        #expect(c.empty == ["a"])
    }

    @Test func emptyKeysAreNotCountedAsTranslated() {
        // Un mod « 100 % traduit » dont la moitié des valeurs sont vides est
        // plus cassé qu'un mod à 50 % : le pourcentage ne doit pas les absorber.
        let c = TranslationCoverage.compute(source: ["a": "1", "b": "2"],
                                            target: ["a": "un", "b": ""])
        #expect(isClose(c.percent, 50))
    }

    @Test func keysMatchCaseInsensitivelyButKeepWhitespace() {
        // SMAPI compare en `OrdinalIgnoreCase` : insensible à la casse, sensible
        // aux espaces. Plier avec un `trim` fusionnerait deux clés qu'il distingue.
        let matched = TranslationCoverage.compute(source: ["Key": "1"], target: ["key": "1fr"])
        #expect(matched.translated == 1)
        let spaced = TranslationCoverage.compute(source: ["key ": "1"], target: ["key": "1fr"])
        #expect(spaced.translated == 0)
    }

    @Test func identicalToSourceIsFlaggedButStillTranslated() {
        // Une valeur FR égale à l'EN peut être légitime (un nom propre) ou
        // trahir un copier-coller : on la compte, et on la signale.
        let c = TranslationCoverage.compute(source: ["name": "Sebastian"],
                                            target: ["name": "Sebastian"])
        #expect(c.translated == 1)
        #expect(c.identicalToSource == ["name"])
        #expect(isClose(c.percent, 100))
    }

    @Test func emptySourceIsZeroCoverage() {
        let c = TranslationCoverage.compute(source: [:], target: ["a": "1"])
        #expect(c.total == 0)
        #expect(isClose(c.percent, 0))
        #expect(c.orphan == ["a"])
    }
}

/// Le diff clé par clé qui alimentera la vue EN/FR.
struct TranslationDiffRowsTests {
    @Test func diffRowsClassifyEachKeyInOnePass() {
        let source = ["name": "Sebastian", "greeting": "Hi", "only_en": "X"]
        let target = ["name": "Sebastian", "greeting": "Salut", "orphan": "Z"]
        let rows = TranslationCoverage.diffRows(source: source, target: target)
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.state) })
        #expect(byKey["name"] == .identicalToSource)
        #expect(byKey["greeting"] == .translated)
        #expect(byKey["only_en"] == .missing)
        #expect(byKey["orphan"] == .orphan)
    }

    @Test func anEmptyValueGetsItsOwnRowState() {
        // L'état que le plan définissait sans jamais le produire : une valeur
        // vide tombait dans `.missing`, si bien que `.empty` était inatteignable
        // et que la vue n'aurait jamais pu montrer le seul défaut qui casse
        // réellement l'affichage en jeu.
        let rows = TranslationCoverage.diffRows(source: ["a": "Hello", "b": "Bye"],
                                                target: ["a": ""])
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.state) })
        #expect(byKey["a"] == .empty)
        #expect(byKey["b"] == .missing)
    }

    @Test func diffRowsAreSortedByKeyThenOrphans() {
        let rows = TranslationCoverage.diffRows(source: ["b": "1", "a": "2"],
                                                target: ["z": "extra"])
        #expect(rows.map(\.key) == ["a", "b", "z"])
    }

    @Test func aDiffRowCarriesBothValues() {
        let rows = TranslationCoverage.diffRows(source: ["k": "Hello"], target: ["k": "Bonjour"])
        #expect(rows.first?.english == "Hello")
        #expect(rows.first?.french == "Bonjour")
    }
}

/// Quels fichiers composent une locale — la question que tout le reste suppose
/// résolue. Un mod peut ranger ses traductions de deux façons, et n'en lire
/// qu'une afficherait « pas de traduction » sur un mod traduit : 6 mods du parc
/// de référence sont concernés, dont 4 en français.
///
/// Les règles reproduisent `SCore.GetTranslationFiles` / `ReadTranslationFiles`,
/// lues à la source.
struct I18nLocaleResolverTests {
    @Test func layoutAReturnsTheSingleLocaleFile() throws {
        let fixture = try I18nFixture(files: ["default.json", "fr.json", "zh.json"])
        defer { fixture.cleanup() }
        let files = I18nLocaleResolver.files(in: fixture.directory, locale: "fr")
        #expect(files.map(\.lastPathComponent) == ["fr.json"])
    }

    @Test func layoutBReturnsEveryFileOfTheLocaleDirectory() throws {
        // Forme réelle (`.Merchant`) : `i18n/fr/{gui,config,strings}.json`.
        let fixture = try I18nFixture(files: [
            "default/gui.json", "default/strings.json",
            "fr/gui.json", "fr/config.json", "fr/strings.json",
        ])
        defer { fixture.cleanup() }
        let files = I18nLocaleResolver.files(in: fixture.directory, locale: "fr")
        #expect(files.map(\.lastPathComponent) == ["config.json", "gui.json", "strings.json"])
    }

    @Test func rootFilesWinOverSubdirectoriesEntirely() throws {
        // SMAPI énumère la racine d'abord ; dès qu'un fichier de sous-dossier
        // suit un fichier racine, il enregistre une erreur et **s'arrête**.
        // Un seul `.json` à la racine suffit donc à faire ignorer *tous* les
        // sous-dossiers, pour toutes les locales — il n'y a pas de fusion.
        let fixture = try I18nFixture(files: ["default.json", "fr/dialogue.json"])
        defer { fixture.cleanup() }
        #expect(I18nLocaleResolver.files(in: fixture.directory, locale: "fr").isEmpty)
        #expect(I18nLocaleResolver.locales(in: fixture.directory) == ["default"])
    }

    @Test func localeNamesAreFoldedToLowercase() throws {
        // Cas réel (`East Scarp NPCs`) : `i18n/Default/` et `i18n/Fr/`.
        // SMAPI applique `.ToLower().Trim()` au nom du dossier comme du fichier.
        let fixture = try I18nFixture(files: ["Default/strings.json", "Fr/strings.json"])
        defer { fixture.cleanup() }
        #expect(I18nLocaleResolver.files(in: fixture.directory, locale: "fr").count == 1)
        #expect(I18nLocaleResolver.locales(in: fixture.directory) == ["default", "fr"])
    }

    @Test func anAbsentLocaleResolvesToNothing() throws {
        let fixture = try I18nFixture(files: ["default.json", "zh.json"])
        defer { fixture.cleanup() }
        #expect(I18nLocaleResolver.files(in: fixture.directory, locale: "fr").isEmpty)
    }

    @Test func anAbsentDirectoryResolvesToNothing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString)/i18n")
        #expect(I18nLocaleResolver.files(in: missing, locale: "fr").isEmpty)
        #expect(I18nLocaleResolver.locales(in: missing).isEmpty)
    }

    @Test func localesAreListedForBothLayouts() throws {
        let layoutA = try I18nFixture(files: ["default.json", "fr.json", "pt.json"])
        defer { layoutA.cleanup() }
        #expect(I18nLocaleResolver.locales(in: layoutA.directory) == ["default", "fr", "pt"])

        let layoutB = try I18nFixture(files: ["default/a.json", "fr/a.json", "zh/a.json"])
        defer { layoutB.cleanup() }
        #expect(I18nLocaleResolver.locales(in: layoutB.directory) == ["default", "fr", "zh"])
    }

    @Test func nonJsonFilesAreIgnored() throws {
        let fixture = try I18nFixture(files: ["fr.json", "readme.txt", "fr/notes.md", "fr/a.json"])
        defer { fixture.cleanup() }
        // La racine gagne : `fr.json` seul, et `readme.txt` n'est pas une locale.
        #expect(I18nLocaleResolver.files(in: fixture.directory, locale: "fr")
                    .map(\.lastPathComponent) == ["fr.json"])
        #expect(I18nLocaleResolver.locales(in: fixture.directory) == ["fr"])
    }
}

