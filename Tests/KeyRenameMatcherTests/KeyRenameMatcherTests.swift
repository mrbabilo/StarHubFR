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
}
