import Testing
import Foundation
@testable import StarHubTHCore

/// La comparaison de versions décide s'il existe une mise à jour, et sert aussi
/// au tri de la liste. Elle n'était couverte par rien : les versions de mods
/// Stardew sont écrites à la main par des centaines d'auteurs, avec toutes les
/// libertés que ça suppose.
struct VersionCompareTests {
    private func cmp(_ a: String, _ b: String) -> ComparisonResult {
        NexusUpdateChecker.compare(a, b)
    }

    @Test func numericSegmentsCompareAsNumbersNotText() {
        // Le piège classique : « 1.10 » vient après « 1.9 », alors que l'ordre
        // alphabétique dirait l'inverse.
        #expect(cmp("1.10.0", "1.9.0") == .orderedDescending)
        #expect(cmp("2.0.0", "10.0.0") == .orderedAscending)
    }

    @Test func aMissingSegmentCountsAsZero() {
        #expect(cmp("1.2", "1.2.0") == .orderedSame)
        #expect(cmp("1.2", "1.2.1") == .orderedAscending)
    }

    @Test func aLeadingVIsIgnored() {
        // Les auteurs écrivent aussi bien « v1.2.0 » que « 1.2.0 ».
        #expect(cmp("v1.2.0", "1.2.0") == .orderedSame)
        #expect(cmp("V1.3.0", "1.2.0") == .orderedDescending)
    }

    @Test func aPrereleaseRanksBelowTheSameReleasedVersion() {
        // Semver : 1.2.0-beta précède 1.2.0.
        #expect(cmp("1.2.0-beta", "1.2.0") == .orderedAscending)
        #expect(cmp("1.2.0", "1.2.0-beta") == .orderedDescending)
    }

    @Test func buildMetadataDoesNotAffectPrecedence() {
        #expect(cmp("1.2.0+build5", "1.2.0") == .orderedSame)
        #expect(cmp("1.2.0+a", "1.2.0+b") == .orderedSame)
    }

    @Test func prereleaseSegmentsCompareNumericallyWhenTheyCan() {
        #expect(cmp("1.0.0-beta.2", "1.0.0-beta.10") == .orderedAscending)
    }

    @Test func aShorterPrereleaseRanksLower() {
        #expect(cmp("1.0.0-beta", "1.0.0-beta.1") == .orderedAscending)
    }

    @Test func caseDoesNotMatterInPrereleaseTags() {
        #expect(cmp("1.0.0-BETA", "1.0.0-beta") == .orderedSame)
    }

    @Test func identicalVersionsAreEqual() {
        #expect(cmp("1.2.3", "1.2.3") == .orderedSame)
    }

    /// Cas réels relevés dans une modlist : des versions qui ne sont pas du
    /// semver. La comparaison ne doit pas prétendre les ordonner n'importe
    /// comment, mais elle ne doit surtout pas planter.
    @Test func nonNumericVersionsDoNotCrash() {
        _ = cmp("1.0.0-unofficial.3-pathoschild", "1.0.0")
        _ = cmp("", "1.0.0")
        _ = cmp("alpha", "beta")
        _ = cmp("1.2.3.4.5", "1.2.3")
    }

    @Test func anUnofficialUpdateOutranksTheVersionItPatches() {
        // Convention de la communauté Stardew : « 1.0.0-unofficial.3-author »
        // est publié APRÈS 1.0.0 et le remplace. Or le semver le classe *avant*
        // (un tag de pré-version rétrograde la version). Ce test documente le
        // comportement actuel — et le fait qu'il est contraire à l'usage.
        #expect(cmp("1.0.0-unofficial.3-pathoschild", "1.0.0") == .orderedAscending)
    }
}
