import Testing
import Foundation
@testable import StarHubTHCore

/// Trois familles au patron de `TranslationRecoveryDiff` (spec §7), mais sur
/// des arbres à 8 niveaux, pas des fichiers plats — le patron se reprend,
/// le code non.
struct ConfigJSONDiffTests {

    private func diff(_ a: String, _ b: String) -> [ConfigKeyDiff] {
        guard let ta = ConfigJSONTree.parse(a), let tb = ConfigJSONTree.parse(b) else {
            Issue.record("fixtures non parsables"); return []
        }
        return ConfigJSONDiff.compare(ta, tb)
    }

    @Test func threeFamiliesInFileOrderNotAlphabetical() {
        // Ordre de A d'abord (Zoom, Shared, OnlyA), puis les absents de A
        // dans l'ordre de B (Alpha, OnlyB) — jamais alphabétique : Zoom
        // passe avant Shared, Alpha avant OnlyB (spec §5.2 : « les clés
        // dans l'ordre du fichier et non dans l'ordre alphabétique »).
        let diffs = diff(#"{"Zoom": 1, "Shared": "a", "OnlyA": true}"#,
                         #"{"Alpha": 2, "Shared": "b", "OnlyB": 3}"#)
        #expect(diffs.map(\.kind) == [.onlyInA, .valueDiffers, .onlyInA, .onlyInB, .onlyInB])
        #expect(diffs.map(\.path) == ["Zoom", "Shared", "OnlyA", "Alpha", "OnlyB"])
    }

    @Test func nestedPathsAreFlattenedWithDots() {
        let diffs = diff(#"{"Controls": {"ToggleKey": "K", "Deep": {"X": 1}}}"#,
                         #"{"Controls": {"ToggleKey": "L", "Deep": {"X": 1}}}"#)
        #expect(diffs.count == 1)
        #expect(diffs[0].path == "Controls.ToggleKey")
        #expect(diffs[0].kind == .valueDiffers)
        #expect(diffs[0].valueA == #""K""#)
        #expect(diffs[0].valueB == #""L""#)
    }

    @Test func identicalTreesGiveNoDiff() {
        #expect(diff(#"{"A": 1, "B": {"C": [1, 2]}}"#, #"{"B": {"C": [1, 2]}, "A": 1}"#).isEmpty)
    }

    @Test func arraysCompareWholeWithInlineRendering() {
        // Un tableau ne se compare pas élément par élément (spec §5.3) :
        // c'est la valeur entière qui diffère, rendue inline.
        let diffs = diff(#"{"Hotkeys": ["F1", "F2"]}"#, #"{"Hotkeys": ["F5"]}"#)
        #expect(diffs.count == 1)
        #expect(diffs[0].valueA == #"["F1","F2"]"#)
        #expect(diffs[0].valueB == #"["F5"]"#)
    }

    @Test func scalarAgainstObjectIsOneValueDiffers() {
        let diffs = diff(#"{"S": {"A": 1}}"#, #"{"S": "plain"}"#)
        #expect(diffs.count == 1)
        #expect(diffs[0].kind == .valueDiffers)
        #expect(diffs[0].valueA == #"{"A":1}"#)
    }

    @Test func missingBranchCountsAllItsKeysAsOnlyIn() {
        // Un sous-objet entier absent de B : chaque feuille est nommée —
        // c'est ce qui rend la divergence *lisible*, chemin par chemin.
        let diffs = diff(#"{"Controls": {"X": 1, "Y": 2}}"#, "{}")
        #expect(diffs.map(\.path) == ["Controls.X", "Controls.Y"])
        #expect(diffs.allSatisfy { $0.kind == .onlyInA })
    }

    @Test func numbersCompareByTextNotByValue() {
        // 1.0 et 1 sont le même nombre mais deux littéraux : le diff les
        // montre. Faux positif acceptable — le littéral est ce que l'auteur
        // écrit, et écrire « identique » sur un texte différent est le
        // silence qu'on refuse partout ailleurs.
        let diffs = diff(#"{"D": 1.0}"#, #"{"D": 1}"#)
        #expect(diffs.count == 1 && diffs[0].kind == .valueDiffers)
    }
}
