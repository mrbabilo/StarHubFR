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

    @Test func mergeKeepsTheFirstOccurrenceOfAKey() {
        // `ReadTranslationFiles` fusionne par `TryAdd` : à clé égale, l'entrée
        // déjà présente est conservée et le doublon signalé. Le fichier qui
        // gagne dépend donc de l'ordre de lecture — que nous fixons par le tri
        // sur le nom, là où SMAPI suit l'ordre du système de fichiers. Sans ce
        // test, cette promesse de déterminisme n'existe que dans un commentaire.
        let merged = I18nLocaleResolver.merge([["k": "premier", "a": "1"],
                                               ["k": "second", "b": "2"]])
        #expect(merged["k"] == "premier")
        #expect(merged["a"] == "1")
        #expect(merged["b"] == "2")
    }

    @Test func layoutBFilesAreMergedInNameOrder() throws {
        // Deux fichiers d'une même locale définissant la même clé : c'est le
        // tri par nom qui tranche, donc `a.json` avant `z.json`.
        let fixture = try I18nFixture(files: ["fr/z.json", "fr/a.json"])
        defer { fixture.cleanup() }
        let files = I18nLocaleResolver.files(in: fixture.directory, locale: "fr")
        #expect(files.map(\.lastPathComponent) == ["a.json", "z.json"])
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


/// Quelles langues un **mod** fournit — tous ses dossiers `i18n` confondus.
///
/// Distinct de la couverture : pour la détection on **unit** les locales (un mod
/// est traduit en français dès qu'un de ses composants l'est) ; pour la
/// couverture chaque dossier `i18n` reste une unité séparée, avec son propre
/// `default.json` au dénominateur.
struct ModLanguageDetectionTests {
    private struct ModFixture {
        let directory: URL
        init(files: [String]) throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("mod-\(UUID().uuidString)", isDirectory: true)
            for relative in files {
                let url = directory.appendingPathComponent(relative)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try Data("{}".utf8).write(to: url)
            }
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func aPlainModAtTheTopLevel() throws {
        let mod = try ModFixture(files: ["i18n/default.json", "i18n/fr.json"])
        defer { mod.cleanup() }
        #expect(I18nLocaleResolver.languageCodes(inModDirectory: mod.directory) == ["en", "fr"])
    }

    @Test func aContentPackNestsItsI18nOneLevelDown() throws {
        // Forme dominante du parc : 121 dossiers `i18n` sont à deux niveaux.
        // Ne regarder que `<mod>/i18n` rendait invisible le français de 81 mods.
        let mod = try ModFixture(files: [
            "[CP] Something/i18n/default.json", "[CP] Something/i18n/fr.json",
        ])
        defer { mod.cleanup() }
        #expect(I18nLocaleResolver.languageCodes(inModDirectory: mod.directory) == ["en", "fr"])
    }

    @Test func severalComponentsUnionTheirLanguages() throws {
        let mod = try ModFixture(files: [
            "A/i18n/default.json", "A/i18n/fr.json",
            "B/i18n/default.json", "B/i18n/es.json",
        ])
        defer { mod.cleanup() }
        #expect(I18nLocaleResolver.languageCodes(inModDirectory: mod.directory) == ["en", "es", "fr"])
    }

    @Test func aLayoutBComponentIsSeenToo() throws {
        let mod = try ModFixture(files: ["i18n/Default/strings.json", "i18n/Fr/strings.json"])
        defer { mod.cleanup() }
        #expect(I18nLocaleResolver.languageCodes(inModDirectory: mod.directory) == ["en", "fr"])
    }

    @Test func deeplyNestedI18nIsStillFound() throws {
        // Un mod du parc range son `i18n` à quatre niveaux. Une limite à deux
        // le perdrait — même faute que de ne lire que `<mod>/i18n`.
        let mod = try ModFixture(files: ["a/b/c/i18n/default.json", "a/b/c/i18n/fr.json"])
        defer { mod.cleanup() }
        #expect(I18nLocaleResolver.languageCodes(inModDirectory: mod.directory) == ["en", "fr"])
    }

    @Test func strayJsonFilesAreNotLanguages() throws {
        // Un `content.json` ou un `manifest.json` dans un `i18n/` ne fait pas
        // une langue : seuls les codes que SMAPI connaît comptent.
        let mod = try ModFixture(files: [
            "i18n/default.json", "i18n/fr.json", "i18n/content.json", "i18n/notes.json",
        ])
        defer { mod.cleanup() }
        #expect(I18nLocaleResolver.languageCodes(inModDirectory: mod.directory) == ["en", "fr"])
    }

    @Test func aModWithoutI18nHasNoLanguages() throws {
        let mod = try ModFixture(files: ["manifest.json"])
        defer { mod.cleanup() }
        #expect(I18nLocaleResolver.languageCodes(inModDirectory: mod.directory).isEmpty)
    }

    @Test func i18nDirectoriesAreListedSeparatelyForCoverage() throws {
        // La couverture ne peut pas fusionner : chaque dossier a son propre
        // `default.json` au dénominateur.
        let mod = try ModFixture(files: ["A/i18n/default.json", "B/i18n/default.json"])
        defer { mod.cleanup() }
        let dirs = I18nLocaleResolver.i18nDirectories(inModDirectory: mod.directory)
        #expect(dirs.count == 2)
    }
}

/// Les variantes régionales et les langues que notre liste ignorait.
struct ModLanguageVariantTests {
    private func fixture(_ files: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("variant-\(UUID().uuidString)", isDirectory: true)
        for relative in files {
            let url = dir.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url)
        }
        return dir
    }

    @Test func aRegionalVariantCountsAsItsBaseLanguage() throws {
        // `Translator.GetRelevantLocales` remonte `pt-BR` → `pt` → `default` :
        // une variante régionale est bien servie à qui demande la langue de
        // base. 19 `pt-br.json` dans le parc.
        let mod = try fixture(["i18n/default.json", "i18n/pt-BR.json"])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(I18nLocaleResolver.languageCodes(inModDirectory: mod) == ["en", "pt"])
    }

    @Test func vietnameseIsALanguageToo() throws {
        // 27 fichiers `vi.json` dans le parc, qui ne comptaient pour rien.
        let mod = try fixture(["i18n/default.json", "i18n/vi.json"])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(I18nLocaleResolver.languageCodes(inModDirectory: mod).contains("vi"))
    }

    @Test func aLocaleTheGameNeverAsksForIsNotALanguage() throws {
        // Un dossier `French/` produirait la locale « french », qui n'est dans
        // la chaîne de repli d'aucune locale du jeu : SMAPI ne la servira
        // jamais. La compter afficherait une traduction fantôme — précisément
        // le mensonge que ce hub ne peut pas se permettre.
        let mod = try fixture(["i18n/default.json", "i18n/French/strings.json"])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(!I18nLocaleResolver.languageCodes(inModDirectory: mod).contains("fr"))
    }
}

/// La couverture d'un **mod entier**, composants compris.
///
/// Chaque dossier `i18n` est calculé séparément — il a son propre
/// `default.json` au dénominateur — puis les compteurs sont additionnés.
/// Fusionner les dictionnaires de clés donnerait un pourcentage qui ne
/// correspondrait à aucun fichier réel.
struct ModCoverageTests {
    private func fixture(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("modcov-\(UUID().uuidString)", isDirectory: true)
        for (relative, content) in files {
            let url = dir.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return dir
    }

    @Test func aSingleComponentIsItsOwnCoverage() throws {
        let mod = try fixture([
            "i18n/default.json": #"{"a": "1", "b": "2"}"#,
            "i18n/fr.json": #"{"a": "un"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let c = try #require(TranslationCoverage.coverage(forModAt: mod, locale: "fr"))
        #expect(c.total == 2)
        #expect(c.translated == 1)
    }

    @Test func componentsAddUpWithoutMergingTheirKeys() throws {
        // Les deux composants définissent une clé `a` : additionner les
        // compteurs donne 2 clés au total, alors que fusionner les
        // dictionnaires n'en compterait qu'une.
        let mod = try fixture([
            "A/i18n/default.json": #"{"a": "1"}"#,
            "A/i18n/fr.json": #"{"a": "un"}"#,
            "B/i18n/default.json": #"{"a": "2"}"#,
            "B/i18n/fr.json": #"{"a": "deux"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let c = try #require(TranslationCoverage.coverage(forModAt: mod, locale: "fr"))
        #expect(c.total == 2)
        #expect(c.translated == 2)
    }

    @Test func anUntranslatedComponentStillCountsAgainstTheMod() throws {
        // Un mod dont un composant sur deux est traduit n'est pas à 100 %.
        let mod = try fixture([
            "A/i18n/default.json": #"{"a": "1"}"#,
            "A/i18n/fr.json": #"{"a": "un"}"#,
            "B/i18n/default.json": #"{"b": "2"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let c = try #require(TranslationCoverage.coverage(forModAt: mod, locale: "fr"))
        #expect(c.total == 2)
        #expect(c.translated == 1)
        #expect(c.missing == ["b"])
    }

    @Test func aComponentWithoutASourceHasNoDenominator() throws {
        // Un pack de traduction pur (`i18n/fr.json` sans `default.json`) n'a
        // rien à mesurer : il ne doit ni compter pour 0 %, ni fausser le total.
        let mod = try fixture([
            "A/i18n/default.json": #"{"a": "1"}"#,
            "A/i18n/fr.json": #"{"a": "un"}"#,
            "B/i18n/fr.json": #"{"z": "orphelin"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let c = try #require(TranslationCoverage.coverage(forModAt: mod, locale: "fr"))
        #expect(c.total == 1)
        #expect(c.translated == 1)
    }

    @Test func aModWithNoTranslationsAtAllHasNoCoverage() throws {
        let mod = try fixture(["manifest.json": "{}"])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationCoverage.coverage(forModAt: mod, locale: "fr") == nil)
    }

    @Test func layoutBComponentsAreMeasuredToo() throws {
        let mod = try fixture([
            "i18n/default/a.json": #"{"a": "1"}"#,
            "i18n/default/b.json": #"{"b": "2"}"#,
            "i18n/fr/a.json": #"{"a": "un"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let c = try #require(TranslationCoverage.coverage(forModAt: mod, locale: "fr"))
        #expect(c.total == 2)
        #expect(c.translated == 1)
    }
}

/// Le nombre affiché sur le badge.
struct CoverageDisplayTests {
    private func coverage(total: Int, translated: Int) -> TranslationCoverage.Coverage {
        TranslationCoverage.Coverage(total: total, translated: translated, missing: [],
                                     empty: [], orphan: [], identicalToSource: [])
    }

    @Test func everythingTranslatedShowsOneHundred() {
        #expect(coverage(total: 200, translated: 200).displayPercent == 100)
    }

    @Test func oneMissingKeyOutOfAThousandNeverShowsOneHundred() {
        // 99,9 % arrondi au plus proche donnerait « 100 % » sur un mod auquel
        // il manque une clé. C'est le seul arrondi que ce badge ne peut pas se
        // permettre : il s'agit d'annoncer un travail terminé.
        #expect(coverage(total: 1000, translated: 999).displayPercent == 99)
    }

    @Test func partialCoverageRoundsDown() {
        // 2/3 = 66,67 % → 66, jamais 67 : mieux vaut annoncer un peu moins que
        // ce qui est fait qu'un peu plus.
        #expect(coverage(total: 3, translated: 2).displayPercent == 66)
    }

    @Test func nothingTranslatedShowsZero() {
        #expect(coverage(total: 10, translated: 0).displayPercent == 0)
    }

    @Test func aTranslatedKeyNeverShowsZero() {
        // 1/1000 = 0,1 % : arrondir à 0 ferait passer un début de traduction
        // pour rien du tout.
        #expect(coverage(total: 1000, translated: 1).displayPercent == 1)
    }

    @Test func nothingToTranslateShowsZero() {
        #expect(coverage(total: 0, translated: 0).displayPercent == 0)
    }
}

/// Le diff d'un **mod entier**, dont les composants restent distincts.
///
/// Un mod multi-composants a plusieurs dossiers `i18n`, chacun avec son propre
/// `default.json`. Deux composants peuvent définir la même clé : ce sont deux
/// lignes à traduire, pas une. Les fusionner en perdrait une — et ferait
/// collision sur l'identité des rangées.
struct ModDiffRowsTests {
    private func fixture(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moddiff-\(UUID().uuidString)", isDirectory: true)
        for (relative, content) in files {
            let url = dir.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return dir
    }

    @Test func aSingleComponentCarriesNoComponentLabel() throws {
        let mod = try fixture([
            "i18n/default.json": #"{"a": "Hello"}"#,
            "i18n/fr.json": #"{"a": "Bonjour"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let rows = TranslationCoverage.diffRows(forModAt: mod, locale: "fr")
        #expect(rows.count == 1)
        #expect(rows.first?.component == nil)
        #expect(rows.first?.french == "Bonjour")
    }

    @Test func sameKeyInTwoComponentsGivesTwoRows() throws {
        let mod = try fixture([
            "A/i18n/default.json": #"{"a": "One"}"#,
            "A/i18n/fr.json": #"{"a": "Un"}"#,
            "B/i18n/default.json": #"{"a": "Two"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let rows = TranslationCoverage.diffRows(forModAt: mod, locale: "fr")
        #expect(rows.count == 2)
        // Les identités doivent différer, sinon la liste en perdrait une.
        #expect(Set(rows.map(\.id)).count == 2)
        #expect(Set(rows.compactMap(\.component)) == ["A", "B"])
    }

    @Test func componentsAreNamedByTheirFolder() throws {
        let mod = try fixture([
            "[CP] Something/i18n/default.json": #"{"a": "1"}"#,
            "Other/i18n/default.json": #"{"b": "2"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let rows = TranslationCoverage.diffRows(forModAt: mod, locale: "fr")
        #expect(Set(rows.compactMap(\.component)) == ["[CP] Something", "Other"])
    }

    @Test func rowsAreGroupedByComponentThenFollowTheFileOrder() throws {
        // Les composants restent triés entre eux, mais **à l'intérieur** d'un
        // fichier c'est l'ordre de l'auteur qui prime — ici `z` avant `a`,
        // comme écrit. Trier alphabétiquement disperserait ses sections.
        let mod = try fixture([
            "B/i18n/default.json": #"{"z": "1", "a": "2"}"#,
            "A/i18n/default.json": #"{"m": "3"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let rows = TranslationCoverage.diffRows(forModAt: mod, locale: "fr")
        #expect(rows.map { "\($0.component ?? "")/\($0.key)" } == ["A/m", "B/z", "B/a"])
    }

    @Test func aModWithoutTranslationsHasNoRows() throws {
        let mod = try fixture(["manifest.json": "{}"])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationCoverage.diffRows(forModAt: mod, locale: "fr").isEmpty)
    }
}

/// Les rangées du diff portent la section que l'auteur a écrite dans son
/// fichier anglais — la seule structure fiable de ces fichiers.
struct DiffRowSectionTests {
    private func fixture(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diffsec-\(UUID().uuidString)", isDirectory: true)
        for (relative, content) in files {
            let url = dir.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return dir
    }

    @Test func rowsCarryTheSourceSection() throws {
        // La section vient de `default.json` : c'est l'anglais qui fait
        // référence, et un `fr.json` peut n'avoir aucun commentaire.
        let mod = try fixture([
            "i18n/default.json": """
            {
              // Config
              "a": "1",
              // Dialogue
              "b": "2"
            }
            """,
            "i18n/fr.json": #"{"a": "un", "b": "deux"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let rows = TranslationCoverage.diffRows(forModAt: mod, locale: "fr")
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.section) })
        #expect(byKey["a"] == "Config")
        #expect(byKey["b"] == "Dialogue")
    }

    @Test func rowsFollowTheFileOrderNotTheAlphabet() throws {
        // Trier alphabétiquement disperserait les sections : une clé « alpha »
        // de la dernière section remonterait au-dessus de la première.
        let mod = try fixture([
            "i18n/default.json": """
            {
              // Premiere
              "zebre": "1",
              // Seconde
              "alpha": "2"
            }
            """,
            "i18n/fr.json": "{}",
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationCoverage.diffRows(forModAt: mod, locale: "fr").map(\.key)
                == ["zebre", "alpha"])
    }

    @Test func aFileWithoutCommentsHasNoSections() throws {
        let mod = try fixture([
            "i18n/default.json": #"{"a": "1"}"#,
            "i18n/fr.json": #"{"a": "un"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationCoverage.diffRows(forModAt: mod, locale: "fr").first?.section == nil)
    }

    @Test func orphanRowsHaveNoSection() throws {
        // Une clé qui n'existe qu'en français n'a pas de place dans la
        // structure de l'anglais.
        let mod = try fixture([
            "i18n/default.json": "{\n  // Config\n  \"a\": \"1\"\n}",
            "i18n/fr.json": #"{"a": "un", "zz": "orpheline"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let rows = TranslationCoverage.diffRows(forModAt: mod, locale: "fr")
        #expect(rows.first { $0.key == "zz" }?.section == nil)
    }

    @Test func rowsCarryTheSectionRank() throws {
        let mod = try fixture([
            "i18n/default.json": """
            {
              // Spring
              "a": "1",
              // Summer
              "b": "2",
              // Spring
              "c": "3"
            }
            """,
            "i18n/fr.json": "{}",
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let rows = TranslationCoverage.diffRows(forModAt: mod, locale: "fr")
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.sectionIndex) })
        // Les deux « Spring » sont deux sections, pas une.
        #expect(byKey["a"] == 0)
        #expect(byKey["b"] == 1)
        #expect(byKey["c"] == 2)
    }

    @Test func ranksDoNotCollideAcrossSplitLocaleFiles() throws {
        // Layout B : une locale éclatée en plusieurs fichiers. Chaque fichier
        // recommence à 0 ; sans décalage, la section 0 de `two.json` se
        // confondrait avec celle de `one.json`.
        let mod = try fixture([
            "i18n/default/one.json": "{\n  // Alpha\n  \"a\": \"1\"\n}",
            "i18n/default/two.json": "{\n  // Beta\n  \"b\": \"2\"\n}",
            // Un `fr.json` à la racine ferait gagner la racine sur tout le
            // dossier `i18n/` — y compris pour `default` — et viderait la
            // fixture ; `fr/` en sous-dossier garde le layout B cohérent.
            "i18n/fr/dialogue.json": "{}",
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let rows = TranslationCoverage.diffRows(forModAt: mod, locale: "fr")
        let ranks = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.sectionIndex) })
        #expect(ranks["a"] != nil)
        #expect(ranks["a"] != ranks["b"])
    }

    @Test func aRowWithoutSectionHasNoRank() throws {
        let mod = try fixture([
            "i18n/default.json": #"{"a": "1"}"#,
            "i18n/fr.json": "{}",
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationCoverage.diffRows(forModAt: mod, locale: "fr")
                    .first?.sectionIndex == nil)
    }

    @Test func aDuplicateKeyProducesOneRowAtItsFirstOccurrence() throws {
        // Mesuré sur `[CP] Tea` : `spring_23` est défini deux fois dans le
        // même `default.json`, sous deux sections différentes — du JSON à
        // clés dupliquées, que Newtonsoft (donc le jeu) accepte. `orderedKeys`
        // porte les deux occurrences ; sans dédoublonnage, la clé produirait
        // deux `DiffRow` de même `id`.
        let mod = try fixture([
            "i18n/default.json": """
            {
              // Seasonal
              "spring_23": "1",
              "other": "x",
              // Marriage
              "spring_23": "2"
            }
            """,
            "i18n/fr.json": #"{"spring_23": "un", "other": "x"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let rows = TranslationCoverage.diffRows(forModAt: mod, locale: "fr")
        let matches = rows.filter { $0.key == "spring_23" }
        #expect(matches.count == 1)
        // L'anglais affiché (`source["spring_23"]`) est celui de la
        // **première** occurrence : notre parseur JSON garde le premier
        // gagnant sur une clé dupliquée. La section et le rang doivent
        // désigner la même occurrence que la valeur montrée, sous peine
        // d'un intitulé qui ne correspond pas au texte affiché en dessous.
        #expect(matches.first?.section == "Seasonal")
        #expect(matches.first?.sectionIndex == 0)
        #expect(Set(rows.map(\.id)).count == rows.count)
    }
}

/// Le regroupement des rangées du diff par section.
///
/// L'identité d'une section est son **rang**, jamais son titre : Ridgeside
/// Village porte 65 sections « Spring ». Les comptes portent sur les rangées
/// reçues — donc sur les rangées filtrées, ce que l'en-tête doit afficher.
struct DiffGroupTests {
    private func row(_ key: String, _ state: TranslationCoverage.DiffRow.State,
                     section: String? = nil, index: Int? = nil,
                     component: String? = nil) -> TranslationCoverage.DiffRow {
        TranslationCoverage.DiffRow(key: key, english: "en", french: "fr", state: state,
                                    component: component, section: section, sectionIndex: index)
    }

    @Test func twoHomonymousSectionsStayTwoGroups() {
        let rows = [
            row("a", .translated, section: "Spring", index: 0),
            row("b", .missing, section: "Summer", index: 1),
            row("c", .missing, section: "Spring", index: 2),
        ]
        let groups = TranslationCoverage.diffGroups(rows: rows)
        #expect(groups.count == 3)
        #expect(Set(groups.map(\.id)).count == 3)
        #expect(groups.map(\.title) == ["Spring", "Summer", "Spring"])
    }

    @Test func groupsFollowTheFileOrderNotTheAlphabet() {
        let rows = [
            row("z", .translated, section: "Zebre", index: 0),
            row("a", .translated, section: "Alpha", index: 1),
        ]
        #expect(TranslationCoverage.diffGroups(rows: rows).map(\.title) == ["Zebre", "Alpha"])
    }

    @Test func keysAboveTheFirstCommentFormAnUntitledGroupFirst() {
        let rows = [
            row("intro", .translated),
            row("a", .translated, section: "Config", index: 0),
        ]
        let groups = TranslationCoverage.diffGroups(rows: rows)
        #expect(groups.first?.title == nil)
        #expect(groups.first?.rows.map(\.key) == ["intro"])
        #expect(groups.count == 2)
    }

    @Test func aFileWithoutSectionsGivesOneUntitledGroup() {
        let groups = TranslationCoverage.diffGroups(rows: [row("a", .translated),
                                                           row("b", .missing)])
        #expect(groups.count == 1)
        #expect(groups.first?.title == nil)
        #expect(groups.first?.rows.count == 2)
    }

    @Test func countsMatchTheRowsReceived() {
        let rows = [
            row("a", .missing, section: "Config", index: 0),
            row("b", .missing, section: "Config", index: 0),
            row("c", .empty, section: "Config", index: 0),
            row("d", .translated, section: "Config", index: 0),
        ]
        let group = try! #require(TranslationCoverage.diffGroups(rows: rows).first)
        #expect(group.remaining(.missing) == 2)
        #expect(group.remaining(.empty) == 1)
        #expect(group.remaining(.orphan) == 0)
        #expect(group.rows.count == 4)
    }

    @Test func theSameSectionInTwoComponentsStaysSeparate() {
        // Deux composants d'un même mod peuvent avoir chacun leur « Config » :
        // ce sont deux sections, et leurs rangs se recouvrent.
        let rows = [
            row("a", .translated, section: "Config", index: 0, component: "A"),
            row("b", .translated, section: "Config", index: 0, component: "B"),
        ]
        let groups = TranslationCoverage.diffGroups(rows: rows)
        #expect(groups.count == 2)
        #expect(Set(groups.map(\.id)).count == 2)
    }

    @Test func theFirstKeyDistinguishesHomonymousSections() {
        // C'est ce que montre la table des matières : sans elle, 65 lignes
        // « Spring » indiscernables.
        let rows = [
            row("Ravi.Spring.1", .translated, section: "Spring", index: 0),
            row("Elis.Spring.1", .translated, section: "Spring", index: 1),
        ]
        #expect(TranslationCoverage.diffGroups(rows: rows).map(\.firstKey)
                == ["Ravi.Spring.1", "Elis.Spring.1"])
    }

    @Test func untitledLeadingRowsAndOrphansAreNotTheSameGroup() {
        // Deux blocs sans rang, aux deux bouts du tableau : les clés d'avant le
        // premier commentaire, et les orphelines que `diffRows` ajoute à la fin.
        // Sans discriminant, ils partageraient une identité — replier l'un
        // replierait l'autre.
        let rows = [row("intro", .translated),
                    row("a", .translated, section: "Config", index: 0),
                    row("zz", .orphan)]
        let groups = TranslationCoverage.diffGroups(rows: rows)
        #expect(groups.count == 3)
        #expect(Set(groups.map(\.id)).count == 3)
        #expect(groups.last?.isOrphan == true)
        #expect(groups.first?.isOrphan == false)
    }

    @Test func noRowsGiveNoGroups() {
        #expect(TranslationCoverage.diffGroups(rows: []).isEmpty)
    }

    @Test func nonContiguousBlocksOfTheSameRankGetDistinctIds() {
        // Mesuré sur le parc (7 mods / 512) : une clé dupliquée dans le
        // fichier source entrelace les rangs (69, 77, 69, 77…). Même après le
        // dédoublonnage des rangées (une clé, une rangée), rien ne garantit
        // structurellement qu'un même rang ne réapparaisse pas plus loin —
        // l'unicité de l'identité ne doit pas en dépendre.
        let rows = [
            row("a", .translated, section: "Seasonal", index: 69),
            row("b", .translated, section: "Marriage", index: 77),
            row("c", .translated, section: "Seasonal", index: 69),
        ]
        let groups = TranslationCoverage.diffGroups(rows: rows)
        #expect(groups.count == 3)
        #expect(Set(groups.map(\.id)).count == 3)
    }

    @Test func filteredKeepsIdTitleAndFirstKeyEvenWhenTheFirstRowIsDropped() {
        let rows = [
            row("a", .missing, section: "Config", index: 0),
            row("b", .translated, section: "Config", index: 0),
        ]
        let group = try! #require(TranslationCoverage.diffGroups(rows: rows).first)
        let filtered = try! #require(group.filtered { $0.state == .translated })
        #expect(filtered.id == group.id)
        #expect(filtered.title == group.title)
        #expect(filtered.firstKey == group.firstKey)
        #expect(filtered.rows.map(\.key) == ["b"])
    }

    @Test func filteredReturnsNilWhenNothingSurvives() {
        let rows = [row("a", .missing, section: "Config", index: 0)]
        let group = try! #require(TranslationCoverage.diffGroups(rows: rows).first)
        #expect(group.filtered { $0.state == .translated } == nil)
    }

    @Test func filteredCountsOnlyTheRowsRetained() {
        let rows = [
            row("a", .missing, section: "Config", index: 0),
            row("b", .missing, section: "Config", index: 0),
            row("c", .translated, section: "Config", index: 0),
        ]
        let group = try! #require(TranslationCoverage.diffGroups(rows: rows).first)
        let filtered = try! #require(group.filtered { $0.state == .missing })
        #expect(filtered.remaining(.missing) == 2)
        #expect(filtered.remaining(.translated) == 0)
        #expect(filtered.rows.count == 2)
    }

    // MARK: - displayTitle

    @Test func displayTitleRendersTheTitleForATitledGroup() {
        let rows = [row("a", .translated, section: "Spring", index: 0)]
        let group = try! #require(TranslationCoverage.diffGroups(rows: rows).first)
        #expect(group.displayTitle(fallback: "Avant la première section", orphan: "Orpheline") == "Spring")
    }

    @Test func displayTitleFallsBackForAnUntitledGroup() {
        let rows = [row("intro", .translated)]
        let group = try! #require(TranslationCoverage.diffGroups(rows: rows).first)
        #expect(group.title == nil)
        #expect(group.displayTitle(fallback: "Avant la première section", orphan: "Orpheline")
                == "Avant la première section")
    }

    @Test func displayTitleUsesTheOrphanLabelNotTheUntitledOne() {
        // C'est exactement la confusion que la tâche 4 avait dû corriger :
        // les orphelines n'ont pas de titre non plus, mais ce n'est pas pour
        // la même raison que les clés d'avant le premier commentaire.
        let rows = [row("a", .translated, section: "Config", index: 0), row("zz", .orphan)]
        let group = try! #require(TranslationCoverage.diffGroups(rows: rows).last)
        #expect(group.isOrphan)
        #expect(group.displayTitle(fallback: "Avant la première section", orphan: "Orpheline") == "Orpheline")
    }

    @Test func displayTitlePrefixesTheComponentForEveryKindOfGroup() {
        // La même règle de préfixe s'applique aux trois : un mod à plusieurs
        // dossiers `i18n` doit distinguer ses groupes sans titre et ses
        // orphelins par composant, pas seulement ses sections titrées.
        let rows = [
            row("intro", .translated, component: "NPCs"),
            row("a", .translated, section: "Spring", index: 0, component: "NPCs"),
            row("zz", .orphan, component: "NPCs"),
        ]
        let groups = TranslationCoverage.diffGroups(rows: rows)
        #expect(groups.count == 3)
        #expect(groups[0].displayTitle(fallback: "Avant", orphan: "Orpheline") == "NPCs — Avant")
        #expect(groups[1].displayTitle(fallback: "Avant", orphan: "Orpheline") == "NPCs — Spring")
        #expect(groups[2].displayTitle(fallback: "Avant", orphan: "Orpheline") == "NPCs — Orpheline")
    }

    /// La seule justification du `@autoclosure` sur `fallback`/`orphan` :
    /// un seul des deux libellés se résout jamais par groupe. Sans ce test,
    /// une signature en `String` ordinaire compilerait tout aussi bien et
    /// doublerait silencieusement les recherches localisées à l'appel.
    @Test func displayTitleEvaluatesOnlyTheLabelItUses() {
        final class CallCounter {
            private(set) var fallbackCalls = 0
            private(set) var orphanCalls = 0
            func fallback() -> String { fallbackCalls += 1; return "F" }
            func orphan() -> String { orphanCalls += 1; return "O" }
        }

        let titled = try! #require(
            TranslationCoverage.diffGroups(rows: [row("a", .translated, section: "Spring", index: 0)]).first)
        let titledCounter = CallCounter()
        _ = titled.displayTitle(fallback: titledCounter.fallback(), orphan: titledCounter.orphan())
        #expect(titledCounter.fallbackCalls == 0)
        #expect(titledCounter.orphanCalls == 0)

        let untitled = try! #require(TranslationCoverage.diffGroups(rows: [row("intro", .translated)]).first)
        let untitledCounter = CallCounter()
        _ = untitled.displayTitle(fallback: untitledCounter.fallback(), orphan: untitledCounter.orphan())
        #expect(untitledCounter.fallbackCalls == 1)
        #expect(untitledCounter.orphanCalls == 0)

        let orphanGroup = try! #require(TranslationCoverage.diffGroups(rows: [row("zz", .orphan)]).first)
        let orphanCounter = CallCounter()
        _ = orphanGroup.displayTitle(fallback: orphanCounter.fallback(), orphan: orphanCounter.orphan())
        #expect(orphanCounter.fallbackCalls == 0)
        #expect(orphanCounter.orphanCalls == 1)
    }
}

/// Le soupçon par les dates : l'anglais d'un mod a-t-il été touché après son
/// français ?
///
/// C'est le seul signal disponible **le premier jour** : les archives de mods
/// conservent les dates de l'auteur, et sur le parc réel 21 fichiers anglais
/// sont plus récents que leur français, jusqu'à 454 jours d'écart. La référence
/// par clé, elle, ne dira rien avant la prochaine mise à jour.
struct TranslationFreshnessTests {
    /// Crée un mod jetable dont chaque fichier porte la date demandée.
    private func fixture(_ files: [(path: String, date: Date)]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fresh-\(UUID().uuidString)", isDirectory: true)
        for file in files {
            let url = dir.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(#"{"a": "1"}"#.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: file.date],
                                                  ofItemAtPath: url.path)
        }
        return dir
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func englishTouchedAfterFrenchIsFlagged() throws {
        let mod = try fixture([("i18n/default.json", now),
                               ("i18n/fr.json", now.addingTimeInterval(-86_400))])
        defer { try? FileManager.default.removeItem(at: mod) }
        let stale = try #require(TranslationFreshness.staleness(forModAt: mod, locale: "fr"))
        #expect(stale.gap == 86_400)
        #expect(stale.component == nil)
    }

    @Test func frenchNewerThanEnglishIsNotFlagged() throws {
        let mod = try fixture([("i18n/default.json", now.addingTimeInterval(-86_400)),
                               ("i18n/fr.json", now)])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationFreshness.staleness(forModAt: mod, locale: "fr") == nil)
    }

    @Test func aGapUnderTheMarginIsNotFlagged() throws {
        // 55 paires du parc partagent leur horodatage à la seconde près : des
        // mods installés par copie, que rien ne distingue. La marge les écarte.
        let mod = try fixture([("i18n/default.json", now),
                               ("i18n/fr.json", now.addingTimeInterval(-30))])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationFreshness.staleness(forModAt: mod, locale: "fr") == nil)
    }

    /// Encadre la marge de 60 s : au-delà elle signale, en deçà elle se tait.
    /// Verrouille l'usage de la marge, pas seulement sa valeur — un
    /// `#expect(margin == 60)` seul laisserait passer un appelant qui l'ignore.
    @Test func aGapJustOverTheMarginIsFlagged() throws {
        let mod = try fixture([("i18n/default.json", now),
                               ("i18n/fr.json", now.addingTimeInterval(-61))])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationFreshness.staleness(forModAt: mod, locale: "fr")?.gap == 61)
    }

    @Test func aGapJustUnderTheMarginIsNotFlagged() throws {
        let mod = try fixture([("i18n/default.json", now),
                               ("i18n/fr.json", now.addingTimeInterval(-59))])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationFreshness.staleness(forModAt: mod, locale: "fr") == nil)
    }

    @Test func aModWithoutFrenchIsNeverFlagged() throws {
        let mod = try fixture([("i18n/default.json", now)])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationFreshness.staleness(forModAt: mod, locale: "fr") == nil)
    }

    @Test func theWidestGapWinsAndNamesItsComponent() throws {
        let mod = try fixture([
            ("A/i18n/default.json", now),
            ("A/i18n/fr.json", now.addingTimeInterval(-3_600)),
            ("B/i18n/default.json", now),
            ("B/i18n/fr.json", now.addingTimeInterval(-864_000)),
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let stale = try #require(TranslationFreshness.staleness(forModAt: mod, locale: "fr"))
        #expect(stale.gap == 864_000)
        #expect(stale.component == "B")
    }

    @Test func aSplitLocaleIsDatedByItsNewestFile() throws {
        // Layout B : une locale éclatée en plusieurs fichiers. Dater par
        // `fr.json` n'aurait rien trouvé — ce fichier n'existe pas.
        let mod = try fixture([
            ("i18n/default/one.json", now),
            ("i18n/fr/a.json", now.addingTimeInterval(-864_000)),
            ("i18n/fr/b.json", now.addingTimeInterval(-3_600)),
        ])
        defer { try? FileManager.default.removeItem(at: mod) }
        let stale = try #require(TranslationFreshness.staleness(forModAt: mod, locale: "fr"))
        #expect(stale.gap == 3_600)
    }

    @Test func anEnglishNamedSourceCounts() throws {
        // Certains auteurs nomment leur source `en.json` plutôt que
        // `default.json` ; c'est la même chose pour SMAPI.
        let mod = try fixture([("i18n/en.json", now),
                               ("i18n/fr.json", now.addingTimeInterval(-7_200))])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationFreshness.staleness(forModAt: mod, locale: "fr")?.gap == 7_200)
    }
}

/// Le magasin de références : ce que l'anglais et le français disaient le jour
/// où on les a vus pour la première fois.
///
/// On garde la **valeur** anglaise, pas son empreinte : c'est ce qui permet de
/// montrer plus tard ce que la phrase disait, seule information qui permette de
/// juger si le français tient encore.
struct TranslationBaselineTests {
    private func makeDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func whatIsSavedComesBack() throws {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entries = [TranslationBaseline.key(component: nil, key: "a"):
                        TranslationBaseline.Entry(source: "Hello", target: "Bonjour")]
        try TranslationBaseline.save(entries, modFolderName: "MyMod", in: dir)
        #expect(TranslationBaseline.load(modFolderName: "MyMod", in: dir) == entries)
    }

    @Test func twoComponentsKeepTheSameKeyApart() {
        // Deux composants d'un même mod peuvent définir la même clé : ce sont
        // deux traductions distinctes, avec chacune son anglais.
        #expect(TranslationBaseline.key(component: "A", key: "a")
                != TranslationBaseline.key(component: "B", key: "a"))
        #expect(TranslationBaseline.key(component: nil, key: "a")
                != TranslationBaseline.key(component: "A", key: "a"))
        // Le cas qui distingue un vrai séparateur d'une simple concaténation :
        // sans octet nul entre les deux membres, `"Aa" + ""` et `"A" + "a"`
        // produiraient la même chaîne.
        #expect(TranslationBaseline.key(component: "Aa", key: "")
                != TranslationBaseline.key(component: "A", key: "a"))
    }

    @Test func anUnknownModHasNoBaseline() {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(TranslationBaseline.load(modFolderName: "Absent", in: dir).isEmpty)
    }

    @Test func aCorruptedStoreIsTreatedAsAbsent() throws {
        // Un magasin illisible ne doit jamais faire échouer l'affichage du
        // diff : au pire on perd la détection, on ne perd pas l'écran.
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try TranslationBaseline.save([:], modFolderName: "Broken", in: dir)
        let file = dir.appendingPathComponent("mods").appendingPathComponent("Broken.json")
        try Data("ceci n'est pas du JSON".utf8).write(to: file)
        #expect(TranslationBaseline.load(modFolderName: "Broken", in: dir).isEmpty)
    }

    @Test func savingTwiceReplacesRatherThanAppends() throws {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = [TranslationBaseline.key(component: nil, key: "a"):
                      TranslationBaseline.Entry(source: "One", target: "Un")]
        let second = [TranslationBaseline.key(component: nil, key: "b"):
                       TranslationBaseline.Entry(source: "Two", target: "Deux")]
        try TranslationBaseline.save(first, modFolderName: "MyMod", in: dir)
        try TranslationBaseline.save(second, modFolderName: "MyMod", in: dir)
        #expect(TranslationBaseline.load(modFolderName: "MyMod", in: dir) == second)
    }

    @Test func theIndexRemembersACountPerMod() throws {
        // Le filtre de la liste lit ce seul fichier : ouvrir 350 magasins à
        // chaque scan pour compter des clés serait payer cher un chiffre.
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try TranslationBaseline.updateIndex(modFolderName: "A", outdatedCount: 3, in: dir)
        try TranslationBaseline.updateIndex(modFolderName: "B", outdatedCount: 0, in: dir)
        let index = TranslationBaseline.loadIndex(in: dir)
        #expect(index["A"] == 3)
        #expect(index["B"] == 0)
        #expect(index["C"] == nil)
    }

    @Test func theIndexUpdatesInPlace() throws {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try TranslationBaseline.updateIndex(modFolderName: "A", outdatedCount: 3, in: dir)
        try TranslationBaseline.updateIndex(modFolderName: "A", outdatedCount: 1, in: dir)
        #expect(TranslationBaseline.loadIndex(in: dir) == ["A": 1])
    }

    @Test func aModNameWithASlashDoesNotEscapeTheDirectory() throws {
        // Un nom de dossier ne peut pas contenir de `/` sur macOS, mais le
        // magasin ne doit pas s'y fier : un nom qui en porterait un écrirait
        // ailleurs que dans le dossier prévu.
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entries = [TranslationBaseline.key(component: nil, key: "a"):
                        TranslationBaseline.Entry(source: "s", target: "t")]
        try TranslationBaseline.save(entries, modFolderName: "../evil", in: dir)
        // Le seul contenu attendu à la racine du magasin est le sous-dossier
        // `mods/` : aucune trace de `../evil` en dehors du dossier prévu.
        let written = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(written == ["mods"])
        #expect(TranslationBaseline.load(modFolderName: "../evil", in: dir) == entries)
    }

    @Test func aModNamedIndexDoesNotCollideWithTheSharedIndex() throws {
        // `fileURL("index", …)` et `indexURL(…)` pointaient jadis vers le même
        // chemin : le magasin d'un mod nommé « index » et l'index partagé
        // s'écrasaient l'un l'autre en silence, et `loadIndex` échouait alors à
        // décoder un magasin de clés comme un index de comptes — perdant le
        // décompte de *tous* les autres mods sans la moindre erreur visible.
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try TranslationBaseline.updateIndex(modFolderName: "Other", outdatedCount: 5, in: dir)
        let entries = [TranslationBaseline.key(component: nil, key: "a"):
                        TranslationBaseline.Entry(source: "s", target: "t")]
        try TranslationBaseline.save(entries, modFolderName: "index", in: dir)
        #expect(TranslationBaseline.load(modFolderName: "index", in: dir) == entries)
        #expect(TranslationBaseline.loadIndex(in: dir) == ["Other": 5])
    }
}

/// L'adoption et la détection : deux fonctions pures, sans disque.
///
/// L'état obsolète est **dérivé** à chaque calcul, jamais stocké — rien à
/// invalider, rien à migrer, et l'état ne peut pas mentir.
struct TranslationBaselineRulesTests {
    private func row(_ key: String, english: String, french: String,
                     state: TranslationCoverage.DiffRow.State = .translated,
                     component: String? = nil) -> TranslationCoverage.DiffRow {
        TranslationCoverage.DiffRow(key: key, english: english, french: french,
                                    state: state, component: component)
    }

    private func entry(_ source: String, _ target: String) -> TranslationBaseline.Entry {
        TranslationBaseline.Entry(source: source, target: target)
    }

    // MARK: - Adoption

    @Test func aTranslatedRowWithoutBaselineIsAdopted() {
        let adopted = TranslationBaselineRules.adoptions(
            rows: [row("a", english: "Hello", french: "Bonjour")], existing: [:])
        #expect(adopted == [TranslationBaseline.key(component: nil, key: "a"):
                             entry("Hello", "Bonjour")])
    }

    @Test func adoptionIsIdempotent() {
        let existing = [TranslationBaseline.key(component: nil, key: "a"):
                         entry("Hello", "Bonjour")]
        #expect(TranslationBaselineRules.adoptions(
            rows: [row("a", english: "Hello", french: "Bonjour")],
            existing: existing).isEmpty)
    }

    @Test func rowsWithoutAFrenchValueAreNotAdopted() {
        // Rien à dater : il n'y a pas de traduction dont l'anglais pourrait
        // avoir bougé depuis.
        let rows = [row("a", english: "Hello", french: "", state: .missing),
                    row("b", english: "Hi", french: "", state: .empty)]
        #expect(TranslationBaselineRules.adoptions(rows: rows, existing: [:]).isEmpty)
    }

    @Test func orphanRowsAreNotAdopted() {
        // Une clé qui n'existe qu'en français n'a pas d'anglais de référence.
        let rows = [row("zz", english: "", french: "Orpheline", state: .orphan)]
        #expect(TranslationBaselineRules.adoptions(rows: rows, existing: [:]).isEmpty)
    }

    @Test func twoComponentsAreAdoptedSeparately() {
        let rows = [row("a", english: "One", french: "Un", component: "A"),
                    row("a", english: "Two", french: "Deux", component: "B")]
        #expect(TranslationBaselineRules.adoptions(rows: rows, existing: [:]).count == 2)
    }

    // MARK: - Rafraîchissement

    @Test func aRetranslatedKeyIsReanchored() {
        // Le français a changé : quelqu'un a retraduit. Sans réancrage, la
        // référence resterait sur l'ancien couple pour toujours et la clé ne
        // pourrait plus **jamais** être signalée obsolète — la détection exige
        // que le français corresponde à la référence.
        let existing = [TranslationBaseline.key(component: nil, key: "a"):
                         entry("Hello", "Bonjour")]
        let refreshed = TranslationBaselineRules.refreshments(
            rows: [row("a", english: "Hello there", french: "Salut à toi")],
            existing: existing)
        #expect(refreshed == [TranslationBaseline.key(component: nil, key: "a"):
                               entry("Hello there", "Salut à toi")])
    }

    @Test func anUnchangedKeyIsNotReanchored() {
        let existing = [TranslationBaseline.key(component: nil, key: "a"):
                         entry("Hello", "Bonjour")]
        #expect(TranslationBaselineRules.refreshments(
            rows: [row("a", english: "Hello", french: "Bonjour")],
            existing: existing).isEmpty)
    }

    @Test func anOutdatedKeyIsNotReanchored() {
        // L'anglais a changé, le français non : c'est précisément le cas qu'on
        // veut continuer à signaler. Réancrer ici effacerait le signal.
        let existing = [TranslationBaseline.key(component: nil, key: "a"):
                         entry("Hello", "Bonjour")]
        #expect(TranslationBaselineRules.refreshments(
            rows: [row("a", english: "Hello there", french: "Bonjour")],
            existing: existing).isEmpty)
    }

    @Test func anUnknownKeyIsNotReanchored() {
        #expect(TranslationBaselineRules.refreshments(
            rows: [row("a", english: "Hello", french: "Bonjour")], existing: [:]).isEmpty)
    }

    // MARK: - Détection

    @Test func englishChangedAndFrenchDidNotIsOutdated() {
        let baseline = [TranslationBaseline.key(component: nil, key: "a"):
                         entry("Hello", "Bonjour")]
        let rows = TranslationBaselineRules.applying(
            baseline: baseline, to: [row("a", english: "Hello there", french: "Bonjour")])
        #expect(rows.first?.state == .outdated)
        #expect(rows.first?.previousEnglish == "Hello")
    }

    @Test func bothChangedMeansSomeoneRetranslated() {
        let baseline = [TranslationBaseline.key(component: nil, key: "a"):
                         entry("Hello", "Bonjour")]
        let rows = TranslationBaselineRules.applying(
            baseline: baseline, to: [row("a", english: "Hello there", french: "Salut à toi")])
        #expect(rows.first?.state == .translated)
        #expect(rows.first?.previousEnglish == nil)
    }

    @Test func anUnchangedEnglishIsNotOutdated() {
        let baseline = [TranslationBaseline.key(component: nil, key: "a"):
                         entry("Hello", "Bonjour")]
        let rows = TranslationBaselineRules.applying(
            baseline: baseline, to: [row("a", english: "Hello", french: "Bonjour")])
        #expect(rows.first?.state == .translated)
    }

    @Test func aRowWithoutBaselineIsNeverOutdated() {
        // Pas de référence, pas de verdict : c'est toute la limite du signal,
        // et elle doit se voir dans le code.
        let rows = TranslationBaselineRules.applying(
            baseline: [:], to: [row("a", english: "Hello there", french: "Bonjour")])
        #expect(rows.first?.state == .translated)
        #expect(rows.first?.previousEnglish == nil)
    }

    @Test func anUntranslatedRowIsNeverOutdated() {
        // Une clé à traduire le reste : la signaler obsolète masquerait le
        // travail réel derrière un état plus faible.
        let baseline = [TranslationBaseline.key(component: nil, key: "a"):
                         entry("Hello", "")]
        let rows = TranslationBaselineRules.applying(
            baseline: baseline, to: [row("a", english: "New", french: "", state: .missing)])
        #expect(rows.first?.state == .missing)
    }

    @Test func theBaselineOfTheRightComponentIsUsed() {
        let baseline = [TranslationBaseline.key(component: "A", key: "a"): entry("One", "Un"),
                        TranslationBaseline.key(component: "B", key: "a"): entry("Two", "Deux")]
        let rows = TranslationBaselineRules.applying(baseline: baseline, to: [
            row("a", english: "One", french: "Un", component: "A"),
            row("a", english: "Two changed", french: "Deux", component: "B"),
        ])
        #expect(rows[0].state == .translated)
        #expect(rows[1].state == .outdated)
        #expect(rows[1].previousEnglish == "Two")
    }
}
