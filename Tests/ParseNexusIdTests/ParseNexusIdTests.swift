import Testing
import Foundation
@testable import StarHubTHCore

/// Locks the contract of `ModManifest.parseNexusId(fromUpdateKeys:)`, the
/// shared helper used by both `ZipModInfo.init` (zip analysis) and
/// `StarHubTHViewModel.parseModFolder` (live mod scan). Before this helper
/// existed the same parsing was duplicated in both places; these tests
/// guarantee future changes only need to be made once.
struct ParseNexusIdTests {

    // MARK: identifiant d'une ligne de mise à jour

    @Test func theMetadataIdWinsWhenSmapiKnowsTheMod() {
        #expect(ModManifest.resolveNexusId(metadataNexusID: 1915,
                                           updateKeys: ["Nexus:9999"]) == "1915")
    }

    @Test func theDeclaredKeyAnswersWhenSmapiHasNoMetadataId() {
        // Le cas mesuré : 15 des 23 mises à jour du parc réel n'ont **aucun**
        // `metadata.nexusID` dans la réponse smapi.io — elle ne le connaît que
        // pour les mods de sa liste de compatibilité — alors que toutes
        // déclarent un `Nexus:<id>`. Sans ce repli, l'identifiant retombait sur
        // l'`UniqueID`, non numérique, et le bouton de téléchargement
        // disparaissait de la ligne.
        #expect(ModManifest.resolveNexusId(metadataNexusID: nil,
                                           updateKeys: ["Nexus:41318"]) == "41318")
    }

    @Test func aModWithNoNexusKeyResolvesToNothing() {
        // GitHub ou CurseForge seuls : il n'y a pas de page Nexus, donc rien à
        // proposer au téléchargement. `nil`, pas une chaîne vide — l'appelant
        // choisit sa sentinelle.
        #expect(ModManifest.resolveNexusId(metadataNexusID: nil,
                                           updateKeys: ["GitHub:Pathoschild/SMAPI"]) == nil)
        #expect(ModManifest.resolveNexusId(metadataNexusID: nil, updateKeys: nil) == nil)
    }

    @Test func aNonPositiveMetadataIdFallsBackToTheKey() {
        // `0` ne mène qu'à un 404 : il ne doit pas l'emporter sur une clé saine.
        #expect(ModManifest.resolveNexusId(metadataNexusID: 0,
                                           updateKeys: ["Nexus:41318"]) == "41318")
    }

    @Test func parsesPlainNexusKey() {
        let r = ModManifest.parseNexusId(fromUpdateKeys: ["nexus:191"])
        #expect(r?.id == "191")
        #expect(r?.url == "https://www.nexusmods.com/stardewvalley/mods/191")
    }

    @Test func ignoresCaseAndWhitespace() {
        let r = ModManifest.parseNexusId(fromUpdateKeys: ["  Nexus:   240  "])
        #expect(r?.id == "240")
    }

    @Test func dropsVariantSuffix() {
        // Multi-mod pack convention — `Nexus:<id>@<variant>`. The helper must
        // collapse all variants onto the same canonical id.
        let r = ModManifest.parseNexusId(fromUpdateKeys: ["Nexus:23169@SwimItems"])
        #expect(r?.id == "23169")
    }

    @Test func returnsFirstValidKeyWhenManyPresent() {
        let keys = ["github:foo", "nexus:notanumber", "nexus:100", "nexus:200"]
        let r = ModManifest.parseNexusId(fromUpdateKeys: keys)
        #expect(r?.id == "100")
    }

    @Test func rejectsZeroAndNegativeIds() {
        #expect(ModManifest.parseNexusId(fromUpdateKeys: ["nexus:0"]) == nil)
        #expect(ModManifest.parseNexusId(fromUpdateKeys: ["nexus:-5"]) == nil)
    }

    @Test func returnsNilForEmptyOrNullInput() {
        #expect(ModManifest.parseNexusId(fromUpdateKeys: nil) == nil)
        #expect(ModManifest.parseNexusId(fromUpdateKeys: []) == nil)
        #expect(ModManifest.parseNexusId(fromUpdateKeys: ["github:foo"]) == nil)
    }
}
