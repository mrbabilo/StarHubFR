import Foundation
import Testing
@testable import StarHubTHCore

@Suite("Guide utilisateur — parseur")
struct HelpGuideTests {
    private let sample = """
    # Guide

    *[English version](GUIDE_EN.md).*

    **Sommaire**

    1. [Premier](#1-premier)

    ---

    <!-- help: first-launch -->
    ## 1. Premier lancement

    Un paragraphe
    sur deux lignes.

    - **Un** point ;
    - un autre.

    1. Étape une.
    2. Étape deux, voir [section 2](#2-installer-des-mods).

    ```bash
    ./run_tests.sh
    ```

    <!-- help: install -->
    ## 2. Installer des mods

    Texte.
    """

    @Test func lePreambuleNestPasUneSection() {
        let sections = HelpGuide.parse(sample)
        #expect(sections.map(\.id) == ["first-launch", "install"])
        #expect(sections[0].title == "1. Premier lancement")
    }

    @Test func lesBlocsSontReconnus() {
        let blocks = HelpGuide.parse(sample)[0].blocks
        #expect(blocks == [
            .paragraph("Un paragraphe sur deux lignes."),
            .bulletList(["**Un** point ;", "un autre."]),
            .numberedList(["Étape une.", "Étape deux, voir [section 2](#2-installer-des-mods)."]),
            .code("./run_tests.sh"),
        ])
    }

    @Test func leCRLFNeCoupePasLesParagraphes() {
        let crlf = sample.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(HelpGuide.parse(crlf) == HelpGuide.parse(sample))
    }

    @Test func uneSectionSansMarqueurPrendSonAncre() {
        let sections = HelpGuide.parse("## 5. Mises à jour\n\nTexte.")
        #expect(sections.map(\.id) == ["5-mises-à-jour"])
    }

    @Test func unTexteVideNaAucuneSection() {
        #expect(HelpGuide.parse("").isEmpty)
    }

    @Test func lesAncresSuiventGitHub() {
        #expect(HelpGuide.githubAnchor("3. Activer, mettre en pause : la convention `X` / `.X`")
                == "3-activer-mettre-en-pause--la-convention-x--x")
        #expect(HelpGuide.githubAnchor("6. When the game crashes or a mod won't load")
                == "6-when-the-game-crashes-or-a-mod-wont-load")
        #expect(HelpGuide.githubAnchor("5. Mises à jour") == "5-mises-à-jour")
    }

    @Test func leMarqueurSeLitAvecOuSansEspaces() {
        #expect(HelpGuide.marker(in: "<!-- help: install -->") == "install")
        #expect(HelpGuide.marker(in: "<!--help:install-->") == "install")
        #expect(HelpGuide.marker(in: "<!-- autre chose -->") == nil)
        #expect(HelpGuide.marker(in: "## Titre") == nil)
    }
}

@Suite("Guide utilisateur — liens")
struct HelpLinkTests {
    private let sections = HelpGuide.parse("""
    <!-- help: recover -->
    ## 10. Retrouver ce qui a été remplacé ou supprimé

    Texte.
    """)

    /// Mesuré le 2026-10-15 : `AttributedString(markdown:)` rend ce lien
    /// percent-encodé. Il doit quand même mener à la section.
    @Test func uneAncreAccentueeMeneASaSection() throws {
        let attributed = try AttributedString(
            markdown: "[voir](#10-retrouver-ce-qui-a-été-remplacé-ou-supprimé)",
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        let link = try #require(attributed.runs.compactMap(\.link).first)
        #expect(HelpLink.resolve(link, in: sections) == .section("recover"))
    }

    @Test func uneAncreInconnueEstIgnoree() throws {
        let url = try #require(URL(string: "#nulle-part"))
        #expect(HelpLink.resolve(url, in: sections) == .ignored)
    }

    @Test func unFichierDuDepotMeneAGitHub() throws {
        let url = try #require(URL(string: "README.md"))
        #expect(HelpLink.resolve(url, in: sections)
                == .external(try #require(URL(string: "https://github.com/mrbabilo/StarHubFR/blob/main/README.md"))))
    }

    @Test func lesReleasesMenentAGitHub() throws {
        let url = try #require(URL(string: "../../releases"))
        #expect(HelpLink.resolve(url, in: sections)
                == .external(try #require(URL(string: "https://github.com/mrbabilo/StarHubFR/releases"))))
    }

    @Test func uneURLAbsolueResteTelleQuelle() throws {
        let url = try #require(URL(string: "https://smapi.io/log"))
        #expect(HelpLink.resolve(url, in: sections) == .external(url))
    }
}
