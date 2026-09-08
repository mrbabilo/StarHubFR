import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct KeyRenameMatcherTests {

    @Test func pureRenameIsMatchedByValue() {
        let pairs = KeyRenameMatcher.pairsByValue(
            old: ["old.key": "Same text"],
            new: ["new.key": "Same text"])
        #expect(pairs == [RenamePair(oldKey: "old.key", newKey: "new.key")])
    }

    @Test func valueMatchIsOneToOneAndDeterministic() {
        // Deux candidates de même valeur qu'une disparue : une seule paire,
        // la première par ordre trié — jamais deux.
        let pairs = KeyRenameMatcher.pairsByValue(
            old: ["gone": "Text"],
            new: ["aaa": "Text", "zzz": "Text"])
        #expect(pairs.count == 1)
        #expect(pairs.first?.newKey == "aaa")
    }

    @Test func differentValuesDoNotPair() {
        let pairs = KeyRenameMatcher.pairsByValue(
            old: ["gone": "Old"], new: ["new": "New"])
        #expect(pairs.isEmpty)
    }

    @Test func snakeCaseCamelCaseAndDashesNormalizeTogether() {
        let pairs = KeyRenameMatcher.pairsBySimilarity(
            removed: ["EnableBetaFeatures"], added: ["enable_beta_features"])
        #expect(pairs.count == 1)
    }

    @Test func tooDifferentNamesDoNotPair() {
        let pairs = KeyRenameMatcher.pairsBySimilarity(
            removed: ["Alpha"], added: ["OmegaConfigurationPanel"])
        #expect(pairs.isEmpty)
    }

    @Test func similarityIsOneToOne() {
        let pairs = KeyRenameMatcher.pairsBySimilarity(
            removed: ["beta_feature", "beta_feature_extra"],
            added: ["beta.feature", "beta.feature.extra"])
        #expect(pairs.count == 2)
        #expect(pairs.contains(RenamePair(oldKey: "beta_feature", newKey: "beta.feature")))
        #expect(pairs.contains(RenamePair(oldKey: "beta_feature_extra", newKey: "beta.feature.extra")))
    }

    @Test func neighbourCaseThatMustNotMerge() {
        // Deux clés réellement distinctes mais proches : une seule peut
        // s'apparier, l'autre reste seule — jamais de fusion inventée.
        let pairs = KeyRenameMatcher.pairsBySimilarity(
            removed: ["color"], added: ["colour", "colour2"])
        #expect(pairs.count == 1)
    }

    @Test func lengthDiffAtBoundStillPairs() {
        // Écart de longueurs EXACTEMENT à la borne (2) : distance 2 ≤ 2,
        // la paire doit exister — le pré-filtre n'écarte qu'au-DELA de la
        // borne, jamais à elle.
        let pairs = KeyRenameMatcher.pairsBySimilarity(
            removed: ["abcd"], added: ["abcdef"])
        #expect(pairs.count == 1)
    }

    @Test func lengthDiffBeyondBoundCannotPair() {
        // Écart de longueurs au-delà de la borne : la distance majore
        // l'écart, le calcul ne peut pas passer — le pré-filtre saute
        // sans Levenshtein, le résultat est le même.
        let pairs = KeyRenameMatcher.pairsBySimilarity(
            removed: ["ab"], added: ["abcdefgh"])
        #expect(pairs.isEmpty)
    }

    @Test func prefilterUsesNormalizedLengths() {
        // La normalisation insère des espaces (camelCase → mots joints) :
        // le pré-filtre juge sur les longueurs NORMALISÉES, sinon il
        // écarterait des paires que le calcul accepterait.
        let pairs = KeyRenameMatcher.pairsBySimilarity(
            removed: ["EnableBetaFeatures"], added: ["enable_beta_feature"])
        #expect(pairs.count == 1)
    }
}
