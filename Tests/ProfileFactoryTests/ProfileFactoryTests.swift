import Foundation
import Testing
@testable import StarHubTHCore

/// Un mod actif minimal, pour les instantanés.
private func makeMod(_ uniqueId: String, name: String = "Un mod", nexusModId: String = "") -> ModItem {
    ModItem(uniqueId: uniqueId,
            name: name,
            folderName: uniqueId,
            version: "1.0.0",
            author: "Auteur",
            description: "",
            nexusUrl: "",
            nexusModId: nexusModId,
            isEnabled: true,
            dependencies: [],
            children: nil,
            isGroup: false,
            installedFileDate: nil)
}

@Suite struct ProfileFactoryTests {

    // MARK: - B3-T1 · profil vide ou instantané

    /// Le défaut demandé par l'auteur : créer un profil **vide**, pas une copie
    /// de ce qui tourne. La page l'annonçait déjà (« démarre sans mod actif »)
    /// alors que le code capturait les mods actifs.
    @Test func anEmptyProfileStartsWithNoMods() {
        let made = ProfileFactory.make(name: "Multi", seed: .empty,
                                       enabledMods: [makeMod("a.mod"), makeMod("b.mod")])

        #expect(made.profile.name == "Multi")
        #expect(made.profile.enabledModIds.isEmpty)
    }

    /// Un profil vide ne devient **pas** actif à la création.
    ///
    /// Le profil actif est réécrit depuis le disque à chaque scan
    /// (`syncActiveProfileIds`) : actif à la création, il serait rempli des
    /// mods en cours quelques secondes plus tard, et « vide » n'aurait duré
    /// que le temps de l'alerte.
    @Test func anEmptyProfileIsNotActivatedOnCreation() {
        let made = ProfileFactory.make(name: "Multi", seed: .empty, enabledMods: [makeMod("a.mod")])

        #expect(!made.activate)
    }

    /// L'autre choix reste offert : capturer ce qui tourne.
    @Test func aSnapshotProfileKeepsTheModsCurrentlyEnabled() {
        let made = ProfileFactory.make(name: "Solo",
                                       seed: .currentlyEnabledMods,
                                       enabledMods: [makeMod("a.mod"), makeMod("b.mod")])

        #expect(made.profile.enabledModIds == ["a.mod", "b.mod"])
    }

    /// Celui-là peut devenir actif sans rien déplacer : son contenu est
    /// exactement l'état du disque au moment de la création.
    @Test func aSnapshotProfileIsActivatedOnCreation() {
        let made = ProfileFactory.make(name: "Solo",
                                       seed: .currentlyEnabledMods,
                                       enabledMods: [makeMod("a.mod")])

        #expect(made.activate)
    }

    /// L'instantané retient le nom et l'identifiant Nexus de chaque mod.
    /// Sans eux, un mod désinstallé plus tard n'est plus qu'un identifiant nu :
    /// impossible de le nommer, encore moins de le retrouver.
    @Test func aSnapshotRemembersWhatItKnowsOfEachMod() {
        let made = ProfileFactory.make(name: "Solo",
                                       seed: .currentlyEnabledMods,
                                       enabledMods: [makeMod("a.mod", name: "A Mod", nexusModId: "42")])

        #expect(made.profile.modMetadata["a.mod"] == ProfileModMetadata(name: "A Mod", nexusModId: "42"))
    }

    /// Un profil vide n'a rien à retenir.
    @Test func anEmptyProfileRemembersNothing() {
        let made = ProfileFactory.make(name: "Multi", seed: .empty,
                                       enabledMods: [makeMod("a.mod", name: "A Mod")])

        #expect(made.profile.modMetadata.isEmpty)
    }

    // MARK: - B3-T3 · duplication

    @Test func aDuplicateCarriesTheSameMods() {
        let source = ModProfile(name: "Solo", enabledModIds: ["a.mod", "b.mod"])

        let copy = ProfileFactory.duplicate(source, nameFormat: "%@ (copie)")

        #expect(copy.enabledModIds == ["a.mod", "b.mod"])
        #expect(copy.name == "Solo (copie)")
    }

    /// Une copie est un **autre** profil : partager l'identifiant ferait
    /// renommer, supprimer ou activer les deux d'un seul geste.
    /// La copie emporte aussi ce que le profil savait de ses mods — sinon
    /// dupliquer un profil lui ferait perdre la mémoire de ses mods absents.
    @Test func aDuplicateCarriesTheRememberedMetadata() {
        var source = ModProfile(name: "Solo", enabledModIds: ["a.mod"])
        source.modMetadata = ["a.mod": ProfileModMetadata(name: "A Mod", nexusModId: "42")]

        let copy = ProfileFactory.duplicate(source, nameFormat: "%@ (copie)")

        #expect(copy.modMetadata == source.modMetadata)
    }

    @Test func aDuplicateHasItsOwnIdentity() {
        let source = ModProfile(name: "Solo", enabledModIds: ["a.mod"])

        let copy = ProfileFactory.duplicate(source, nameFormat: "%@ (copie)")

        #expect(copy.id != source.id)
    }
}

/// La métadonnée d'un lot de mods entrant dans un profil **par leurs
/// identifiants** — le cas des imports de favoris et de mods à écarter.
///
/// La boucle vivait en **deux exemplaires** dans le ViewModel, identiques au
/// nom de la résolution près. Elle n'est pas décorative : `modMetadata` est la
/// seule source qui permette encore de **nommer** un mod du profil une fois
/// qu'il aura été désinstallé.
struct ProfileFactoryMetadataForIdsTests {

    private func mod(_ uniqueId: String, _ name: String, nexusModId: String = "") -> ModItem {
        makeMod(uniqueId, name: name, nexusModId: nexusModId)
    }

    @Test func anIdIsResolvedToItsModsNameAndNexusId() {
        let result = ProfileFactory.metadata(forIds: ["SVE.Mod"],
                                             in: [mod("SVE.Mod", "SVE", nexusModId: "3753")])
        #expect(result["SVE.Mod"]?.name == "SVE")
        #expect(result["SVE.Mod"]?.nexusModId == "3753")
    }

    @Test func theLookupIgnoresCaseOnBothSides() {
        // Les `UniqueID` des manifestes ne s'accordent pas sur la casse, et
        // une résolution stricte perdrait la métadonnée sans rien dire — le
        // diagnostic de profil se dégraderait des mois plus tard.
        let result = ProfileFactory.metadata(forIds: ["sve.mod"],
                                             in: [mod("SVE.Mod", "SVE")])
        #expect(result["sve.mod"]?.name == "SVE")
    }

    @Test func theKeyIsTheIdAsAsked() {
        // La clé doit correspondre à ce qui entre dans `enabledModIds`, sinon
        // la métadonnée n'est jamais retrouvée.
        let result = ProfileFactory.metadata(forIds: ["sve.mod"], in: [mod("SVE.Mod", "SVE")])
        #expect(Array(result.keys) == ["sve.mod"])
    }

    @Test func anIdWithoutAnInstalledModIsSkipped() {
        // Rien à en dire : inventer une métadonnée vide ferait afficher un mod
        // sans nom là où l'absence est l'information.
        #expect(ProfileFactory.metadata(forIds: ["Absent"], in: [mod("SVE.Mod", "SVE")]).isEmpty)
    }

    @Test func aComponentOfAPackIsFoundThroughTheFlattenedList() {
        // Les composants d'un pack vivent sous leur en-tête : ne regarder que
        // le premier niveau les manquerait tous.
        let child = mod("Pack.Child", "Composant")
        let pack = ModItem(uniqueId: "Pack", name: "Pack", folderName: "Pack",
                           version: "1.0.0", author: "Auteur", description: "",
                           nexusUrl: "", nexusModId: "", isEnabled: true,
                           dependencies: [], children: [child], isGroup: true,
                           installedFileDate: nil)
        let result = ProfileFactory.metadata(forIds: ["Pack.Child"], in: [pack])
        #expect(result["Pack.Child"]?.name == "Composant")
    }

    @Test func theFirstOfTwoModsSharingAnIdWins() {
        // Deux dossiers peuvent porter le même `UniqueID` — un mod actif et sa
        // copie en pause, cas réel du parc. Le choix doit être déterministe.
        let result = ProfileFactory.metadata(forIds: ["Dup"],
                                             in: [mod("Dup", "Premier"), mod("Dup", "Second")])
        #expect(result["Dup"]?.name == "Premier")
    }
}
