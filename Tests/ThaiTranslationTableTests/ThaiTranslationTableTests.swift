import Testing
import Foundation
@testable import StarHubTHCore

/// Le catalogue des traductions est un tableau Markdown publié dans un dépôt
/// tiers. Son découpage vivait dans le ViewModel, donc hors de portée des
/// tests, alors qu'il dépend entièrement d'une mise en forme sur laquelle nous
/// n'avons aucune prise.
struct ThaiTranslationTableTests {
    /// Ligne réelle du catalogue : nom en gras, lien Markdown imbriqué dans le
    /// nom (`[[CP] …](url)`), et une colonne Nexus elle-même en lien.
    private let table = """
    | ชื่อม็อด | ผู้แปล | เวอร์ชัน | สถานะ | Nexus |
    | :--- | :--- | :--- | :--- | :--- |
    | **[[CP] Additional Farm Cave](https://github.com/x/y)** | Somchai | 1.2.0 | เสร็จสมบูรณ์ | [Nexus](https://www.nexusmods.com/stardewvalley/mods/123) |
    """

    @Test func aRowIsSplitIntoItsColumns() {
        let out = ThaiTranslationTable.parse(table)
        #expect(out.count == 1)
        let mod = try! #require(out.first)
        #expect(mod.author == "Somchai")
        #expect(mod.version == "1.2.0")
        #expect(mod.status == "เสร็จสมบูรณ์")
    }

    @Test func theNameIsUnwrappedFromItsBoldMarkdownLink() {
        // `**[[CP] Nom](url)**` → nom = « [CP] Nom », url = la cible du lien.
        // Le nom contient lui-même des crochets : c'est le piège de ce format.
        let mod = try! #require(ThaiTranslationTable.parse(table).first)
        #expect(mod.name == "[CP] Additional Farm Cave")
        #expect(mod.url == "https://github.com/x/y")
    }

    @Test func theNexusColumnYieldsItsLinkTarget() {
        let mod = try! #require(ThaiTranslationTable.parse(table).first)
        #expect(mod.nexusUrl == "https://www.nexusmods.com/stardewvalley/mods/123")
    }

    @Test func theSeparatorRowIsNotAMod() {
        // `| :--- | :--- |` suit toujours l'en-tête : la compter donnerait une
        // entrée fantôme en tête de liste.
        #expect(ThaiTranslationTable.parse(table).count == 1)
    }

    @Test func aBlankLineEndsTheTable() {
        // Markdown : le tableau s'arrête à la première ligne vide. Ce qui suit
        // est de la prose, pas des mods.
        let doc = table + "\n\nDu texte, puis un autre tableau :\n| a | b | c | d | e | f |"
        #expect(ThaiTranslationTable.parse(doc).count == 1)
    }

    @Test func contentBeforeTheHeaderIsIgnored() {
        let doc = "# Titre\n\nUne introduction.\n\n" + table
        #expect(ThaiTranslationTable.parse(doc).count == 1)
    }

    @Test func aRowWithTooFewColumnsIsSkipped() {
        let doc = """
        | ชื่อม็อด | ผู้แปล | เวอร์ชัน | สถานะ | Nexus |
        | :--- | :--- | :--- | :--- | :--- |
        | **[Truncated](https://x)** | Auteur |
        """
        #expect(ThaiTranslationTable.parse(doc).isEmpty)
    }

    @Test func aPlainNameWithoutALinkKeepsItsText() {
        let doc = """
        | ชื่อม็อด | ผู้แปล | เวอร์ชัน | สถานะ | Nexus |
        | :--- | :--- | :--- | :--- | :--- |
        | **Nom sans lien** | Auteur | 1.0 | รอแปล | — |
        """
        let mod = try! #require(ThaiTranslationTable.parse(doc).first)
        #expect(mod.name == "Nom sans lien")
        #expect(mod.url.isEmpty)
        #expect(mod.nexusUrl.isEmpty)
    }

    @Test func aDocumentWithNoTableYieldsNothing() {
        // Le repère d'en-tête est en thaï, écrit en dur : si le dépôt source le
        // change, on ne trouve plus rien. Ce test fige le comportement — la
        // liste est vide, elle ne plante pas.
        #expect(ThaiTranslationTable.parse("# Rien à voir\n\ndu texte").isEmpty)
    }
}

struct ThaiTranslationAvailabilityTests {
    private func mod(installed: Bool, original: Bool) -> ThaiTranslationMod {
        ThaiTranslationMod(name: "n", author: "a", version: "1", status: "s",
                           url: "", nexusUrl: "",
                           isInstalled: installed, isOriginalModInstalled: original)
    }

    @Test func theStateIsExpressedAsAKeyNotAsRenderedText() {
        // Le modèle prenait le ViewModel en paramètre pour se traduire lui-même,
        // ce qui l'empêchait de vivre dans le module testable. Il rend
        // maintenant une clé, et la vue la traduit.
        #expect(mod(installed: true, original: false).availabilityKey == L10n.ThaiHub.installed)
        #expect(mod(installed: false, original: true).availabilityKey == L10n.ThaiHub.availableDownload)
        #expect(mod(installed: false, original: false).availabilityKey == L10n.ThaiHub.missingOriginal)
    }

    @Test func beingInstalledWinsOverTheBaseModBeingPresent() {
        #expect(mod(installed: true, original: true).availabilityKey == L10n.ThaiHub.installed)
    }

    // MARK: linkTarget (garde contre les parens inversées)

    @Test func linkTargetExtractsUrlBetweenParens() {
        #expect(ThaiTranslationTable.linkTarget(in: "[Nexus](https://nexusmods.com/stardewvalley/mods/123)") == "https://nexusmods.com/stardewvalley/mods/123")
    }

    @Test func reversedParensDoNotCrash() {
        // ")text(" : `)` précède `(` → sans garde, lowerBound > upperBound →
        // crash fatal. Le catalogue Nexus vient d'un dépôt tiers non contrôlé.
        #expect(ThaiTranslationTable.linkTarget(in: ")text(") == "")
        #expect(ThaiTranslationTable.linkTarget(in: ") (") == "")
    }
}
