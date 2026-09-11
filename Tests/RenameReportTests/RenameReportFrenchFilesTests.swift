import Foundation
import Testing
@testable import StarHubTHCore

/// Répartir un report de renommages sur **tous** les fichiers d'une locale.
///
/// Le report composait `i18n/fr.json` en dur : sur un mod rangé en layout B
/// (`i18n/fr/dialogue.json`, `i18n/fr/items.json`…), la lecture échouait et la
/// boucle abandonnait **sans journaliser**. 5 mods du parc de référence sont
/// dans ce cas (mesuré le 2026-09-11) : `.Merchant`, `East Scarp NPCs`,
/// `[CP] Button's Extra Books`, `Hootin' & Hollerin'`, `[CP] Sword & Sorcery`.
struct RenameReportFrenchFilesTests {

    private func pair(_ old: String, _ new: String) -> RenamePair {
        RenamePair(oldKey: old, newKey: new)
    }

    @Test func aSingleFileBehavesExactlyLikeTheOneFileForm() {
        let text = #"{"greet": "Bonjour"}"#
        let spread = RenameReport.applyToFrenchFiles(
            [.init(id: "fr.json", text: text)], pairs: [pair("greet", "hello")])

        #expect(spread.applied == [pair("greet", "hello")])
        let rewritten = spread.files.first { $0.id == "fr.json" }?.text
        #expect(rewritten == RenameReport.applyToFrench(text, pairs: [pair("greet", "hello")]).text)
    }

    @Test func aPairIsAppliedInWhicheverFileCarriesIt() {
        // Le défaut que ce chemin ferme : la clé vit dans le second fichier,
        // et composer `fr.json` ne l'atteignait jamais.
        let spread = RenameReport.applyToFrenchFiles([
            .init(id: "dialogue.json", text: #"{"hi": "Salut"}"#),
            .init(id: "items.json", text: #"{"sword": "Épée"}"#),
        ], pairs: [pair("sword", "blade")])

        #expect(spread.applied == [pair("sword", "blade")])
        #expect(spread.files.first { $0.id == "items.json" }?.text.contains("blade") == true)
    }

    @Test func aFileThatChangesNothingIsNotRewritten() {
        // Sans cette garde, chaque report réécrirait tous les fichiers de la
        // locale — et chaque réécriture ouvre les droits du dossier du mod.
        let spread = RenameReport.applyToFrenchFiles([
            .init(id: "dialogue.json", text: #"{"hi": "Salut"}"#),
            .init(id: "items.json", text: #"{"sword": "Épée"}"#),
        ], pairs: [pair("sword", "blade")])

        #expect(spread.files.map(\.id) == ["items.json"])
    }

    @Test func pairsSpreadOverTwoFilesAreBothApplied() {
        let spread = RenameReport.applyToFrenchFiles([
            .init(id: "dialogue.json", text: #"{"hi": "Salut"}"#),
            .init(id: "items.json", text: #"{"sword": "Épée"}"#),
        ], pairs: [pair("sword", "blade"), pair("hi", "greeting")])

        #expect(Set(spread.applied) == [pair("sword", "blade"), pair("hi", "greeting")])
        #expect(spread.files.map(\.id).sorted() == ["dialogue.json", "items.json"])
    }

    @Test func aPairCarriedByTwoFilesIsAppliedOnceOnly() {
        // SMAPI garde la **première** occurrence d'une clé d'une même locale
        // (`I18nLocaleResolver.merge`) : c'est celle-là qu'il faut renommer.
        // Compter deux fois annoncerait à l'écran plus de clés reportées
        // qu'il n'y a de clés.
        let spread = RenameReport.applyToFrenchFiles([
            .init(id: "a.json", text: #"{"sword": "Épée"}"#),
            .init(id: "b.json", text: #"{"sword": "Glaive"}"#),
        ], pairs: [pair("sword", "blade")])

        #expect(spread.applied == [pair("sword", "blade")])
        #expect(spread.files.map(\.id) == ["a.json"])
    }

    @Test func nothingApplicableRewritesNothing() {
        let spread = RenameReport.applyToFrenchFiles([
            .init(id: "dialogue.json", text: #"{"hi": "Salut"}"#),
        ], pairs: [pair("sword", "blade")])

        #expect(spread.applied.isEmpty)
        #expect(spread.files.isEmpty)
    }

    @Test func anUnreadableFileDoesNotStopTheOthers() {
        // `applyToFrench` s'abstient sur un texte qu'il ne sait pas lire. Un
        // fichier abîmé ne doit pas emporter le report des autres sections.
        let spread = RenameReport.applyToFrenchFiles([
            .init(id: "broken.json", text: "{ pas du JSON"),
            .init(id: "items.json", text: #"{"sword": "Épée"}"#),
        ], pairs: [pair("sword", "blade")])

        #expect(spread.applied == [pair("sword", "blade")])
        #expect(spread.files.map(\.id) == ["items.json"])
    }
}
