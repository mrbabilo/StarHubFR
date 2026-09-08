import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct RenameReportTranslationTests {

    @Test func newKeyTakesTheOldPositionAndValue() throws {
        let text = """
        {
          "first": "Premier",
          "old.key": "Ma traduction",
          "last": "Dernier"
        }
        """
        let (out, applied) = RenameReport.applyToFrench(
            text, pairs: [RenamePair(oldKey: "old.key", newKey: "new.key")])
        #expect(applied == [RenamePair(oldKey: "old.key", newKey: "new.key")])
        #expect(!out.contains("old.key"))
        #expect(out.contains("\"new.key\": \"Ma traduction\""))
        // L'ordre de l'auteur : first < new.key < last.
        let outline = I18nOutline.read(out)
        #expect(outline.orderedKeys == ["first", "new.key", "last"])
    }

    @Test func abstainsWhenNewKeyAlreadyTranslated() {
        let text = """
        {
          "old.key": "Ancienne",
          "new.key": "Déjà fait"
        }
        """
        let (out, applied) = RenameReport.applyToFrench(
            text, pairs: [RenamePair(oldKey: "old.key", newKey: "new.key")])
        #expect(applied.isEmpty)
        #expect(out == text, "rien n'est changé quand la cible est déjà traduite")
    }

    @Test func pairsWithoutFrenchValueLeaveTheOldKeyAlone() {
        // L'ancienne clé n'est pas traduite (absente du fr.json) : rien à
        // reporter — le texte ressort intact, aucune paire appliquée.
        let text = """
        { "other": "Autre" }
        """
        let (out, applied) = RenameReport.applyToFrench(
            text, pairs: [RenamePair(oldKey: "gone", newKey: "fresh")])
        #expect(applied.isEmpty && out == text)
    }

    // MARK: - Routage par composant (revue C2-T4 n°6/n°9)

    @Test func qualifiedKeysRouteToTheirOldComponent() {
        // La paire vit dans Kid : le report écrit DANS Kid, sous la forme
        // brute de la clé — jamais sa forme qualifiée.
        let routed = RenameReport.routeByOldComponent(
            [RenamePair(oldKey: "Kid/greeting", newKey: "Kid/hello")],
            known: ["", "Kid"])
        #expect(routed.crossComponent.isEmpty)
        #expect(routed.byComponent["Kid"]?.count == 1)
        #expect(routed.byComponent["Kid"]?.first?.raw
                == RenamePair(oldKey: "greeting", newKey: "hello"))
        #expect(routed.byComponent[""] == nil)
    }

    @Test func crossComponentPairsAreNotReportable() {
        // Renommage d'un composant entier : écrire la forme brute de la
        // nouvelle clé dans l'ANCIEN composant y déposerait une orpheline
        // pendant que la vraie restera non traduite. La paire est rendue à
        // part — l'écran l'annonce, l'onglet diff reste l'outil.
        let routed = RenameReport.routeByOldComponent(
            [RenamePair(oldKey: "KidA/greeting", newKey: "KidB/greeting")],
            known: ["", "KidA", "KidB"])
        #expect(routed.byComponent.isEmpty)
        #expect(routed.crossComponent
                == [RenamePair(oldKey: "KidA/greeting", newKey: "KidB/greeting")])
    }

    @Test func unknownNewComponentCountsAsCrossComponent() {
        // La nouvelle clé vit sous un composant que le scan ne connaît pas :
        // on ne sait pas quel fr.json viser — cross, pas d'écriture à
        // l'aveugle chez l'ancien.
        let routed = RenameReport.routeByOldComponent(
            [RenamePair(oldKey: "Kid/greeting", newKey: "Elsewhere/greeting")],
            known: ["", "Kid"])
        #expect(routed.byComponent.isEmpty)
        #expect(routed.crossComponent.count == 1)
    }

    @Test func i18nKeyWithSlashKeepsLongestComponentPrefix() {
        // Un pack Content Patcher : la clé « Strings/… » contient un `/` —
        // le plus long préfixe de composant gagne, jamais le premier.
        let routed = RenameReport.routeByOldComponent(
            [RenamePair(oldKey: "Kid/Strings/old", newKey: "Kid/Strings/new")],
            known: ["", "Kid"])
        #expect(routed.crossComponent.isEmpty)
        #expect(routed.byComponent["Kid"]?.first?.raw
                == RenamePair(oldKey: "Strings/old", newKey: "Strings/new"))
    }

    @Test func bareKeysRouteToRoot() {
        let routed = RenameReport.routeByOldComponent(
            [RenamePair(oldKey: "gone", newKey: "fresh")],
            known: ["", "Kid"])
        #expect(routed.crossComponent.isEmpty)
        #expect(routed.byComponent[""]?.first?.raw
                == RenamePair(oldKey: "gone", newKey: "fresh"))
    }
}
