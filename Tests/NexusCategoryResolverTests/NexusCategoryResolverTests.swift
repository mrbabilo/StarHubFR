import Testing
import Foundation
@testable import StarHubTHCore

/// La précédence de la catégorie affichée pour un mod, extraite du
/// ViewModel (2026-09-11) : l'override utilisateur gagne, sinon la catégorie
/// API par identifiant Nexus **effectif** (override d'identifiant ou
/// manifeste), sinon — pour un en-tête de pack — la catégorie dominante de
/// ses enfants, sinon rien.
struct NexusCategoryResolverTests {

    /// Catégories Nexus valides de la table : 15 et 16.
    ///
    /// ⚠️ `nexusId` et non `uniqueId` : la catégorie API est indexée par
    /// l'identifiant **Nexus** (celui du manifeste, que `effectiveId` lit),
    /// pas par l'`UniqueID` du mod — 58 identifiants Nexus du parc sont
    /// partagés par plusieurs dossiers, les deux clés ne sont pas
    /// interchangeables.
    private func mod(_ folder: String, nexusId: String = "",
                     group: Bool = false, children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: folder + ".uid", name: folder, folderName: folder,
                version: "", author: "", description: "", nexusUrl: "",
                nexusModId: nexusId, isEnabled: true, dependencies: [],
                children: children, isGroup: group)
    }

    private func resolve(_ m: ModItem,
                         custom: [String: Int] = [:],
                         api: [String: Int] = [:],
                         customIds: [String: String] = [:]) -> NexusCategory? {
        NexusCategoryResolver.resolveCategory(
            for: m, customCategories: custom,
            categoriesByNexusId: api, customModIds: customIds)
    }

    // MARK: - La précédence

    /// L'override utilisateur gagne, même quand l'API connaît le mod.
    @Test func customOverrideWinsOverEverything() {
        let category = resolve(mod("Alpha", nexusId: "a.mod"),
                               custom: ["Alpha": 15], api: ["a.mod": 16])
        #expect(category?.id == 15)
    }

    /// Sans override, l'API parle — par l'identifiant **effectif** : celui du
    /// manifeste, ou celui saisi à la main pour un mod qui n'en déclare pas.
    @Test func apiCategoryKeyedByEffectiveId() {
        let byManifest = resolve(mod("Beta", nexusId: "b.mod"), api: ["b.mod": 16])
        #expect(byManifest?.id == 16)

        let byManualId = resolve(mod("Gamma", nexusId: "c.mod"),
                                 api: ["191": 15], customIds: ["Gamma": "191"])
        #expect(byManualId?.id == 15)
    }

    /// Sans override, sans id effectif et sans enfants : rien — un mod sans
    /// page n'a pas de catégorie API à porter.
    @Test func unknownEverythingIsNil() {
        #expect(resolve(mod("Delta")) == nil)
        #expect(resolve(mod("Epsilon", nexusId: "e.mod")) == nil)
    }

    // MARK: - Le dominant des packs

    /// Un en-tête de pack prend la catégorie **la plus fréquente** de ses
    /// enfants — l'en-tête est ce qu'on active, pas ses enfants pris un à un.
    @Test func packHeaderTakesDominantChildCategory() {
        let pack = mod("Pack", group: true, children: [
            mod("c1", nexusId: "c1.mod"), mod("c2", nexusId: "c2.mod"),
            mod("c3", nexusId: "c3.mod"),
        ])
        let category = resolve(pack, api: ["c1.mod": 15, "c2.mod": 15, "c3.mod": 16])
        #expect(category?.id == 15)
    }

    /// Ex æquo de fréquence : l'identifiant de catégorie **le plus bas**
    /// gagne — un ordre stable, sans dépendre d'un tri non garanti.
    @Test func dominantTieResolvesToLowerCategoryId() {
        let pack = mod("Pack", group: true, children: [
            mod("c1", nexusId: "c1.mod"), mod("c2", nexusId: "c2.mod"),
            mod("c3", nexusId: "c3.mod"), mod("c4", nexusId: "c4.mod"),
        ])
        let category = resolve(pack, api: ["c1.mod": 16, "c2.mod": 16,
                                           "c3.mod": 15, "c4.mod": 15])
        #expect(category?.id == 15)
    }

    /// Un pack dont **aucun** enfant n'a de catégorie reste sans catégorie —
    /// inventer un dominant ferait apparaître une étiquette que rien ne
    /// justifie.
    @Test func packWithoutAnyKnownChildCategoryIsUnknown() {
        let pack = mod("Pack", group: true, children: [
            mod("c1", nexusId: "c1.mod"), mod("c2", nexusId: "c2.mod"),
        ])
        #expect(resolve(pack) == nil)
    }

    /// Le dominant n'exige pas de majorité : **un seul** enfant connu suffit
    /// à donner sa catégorie au pack, les inconnus ne votent pas.
    @Test func aSingleKnownChildIsEnoughToNameThePack() {
        let pack = mod("Pack", group: true, children: [
            mod("c1", nexusId: "c1.mod"), mod("c2", nexusId: "c2.mod"),
            mod("c3", nexusId: "c3.mod"),
        ])
        #expect(resolve(pack, api: ["c1.mod": 15])?.id == 15)
    }

    /// L'override d'un **enfant** compte dans le dominant — le resolver de
    /// l'enfant applique la même précédence, où que l'enfant soit affiché.
    @Test func childCustomOverrideCountsWithinThePack() {
        let pack = mod("Pack", group: true, children: [
            mod("c1", nexusId: "c1.mod"), mod("c2", nexusId: "c2.mod"),
        ])
        let category = resolve(pack, custom: ["c1": 15],
                               api: ["c1.mod": 16, "c2.mod": 16])
        #expect(category?.id == 15)
    }

    /// Un pack dont l'en-tête porte un id effectif ne descend **pas** dans
    /// ses enfants : la catégorie API de l'en-tête prime sur le dominant.
    @Test func packHeaderOwnIdBeatsDominant() {
        let pack = mod("Pack", nexusId: "pack.mod", group: true, children: [
            mod("c1", nexusId: "c1.mod"), mod("c2", nexusId: "c2.mod"),
        ])
        let category = resolve(pack, api: ["pack.mod": 15, "c1.mod": 16, "c2.mod": 16])
        #expect(category?.id == 15)
    }

    /// Un pack sans id propre mais dont l'identifiant a été saisi à la main
    /// ne descend pas non plus — l'identifiant effectif est la même porte
    /// que pour un mod simple.
    @Test func packHeaderManualIdBeatsDominant() {
        let pack = mod("Pack", group: true, children: [
            mod("c1", nexusId: "c1.mod"), mod("c2", nexusId: "c2.mod"),
        ])
        let category = resolve(pack, api: ["191": 15, "c1.mod": 16, "c2.mod": 16],
                               customIds: ["Pack": "191"])
        #expect(category?.id == 15)
    }
}
