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
}
