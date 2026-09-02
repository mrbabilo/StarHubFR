import Testing
import Foundation
@testable import StarHubTHCore

/// Retrouver le mod visé par une demande de mise au point. Deux origines aux
/// requêtes, et elles ne parlent pas la même langue : la recherche guidée tient
/// un **nom de dossier** de premier niveau, le journal de SMAPI un **nom
/// affiché** de composant. Un seul résolveur pour les deux.
struct ModFocusResolverTests {
    private func mod(_ name: String, folder: String? = nil,
                     children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: "id.\(name)", name: name, folderName: folder ?? name,
                version: "1.0", author: "", description: "", nexusUrl: "",
                nexusModId: "", isEnabled: true, dependencies: [],
                children: children, isGroup: children != nil)
    }

    @Test func aFolderNameWinsOverANamePartiallyMatchingIt() {
        // Le dossier « SVE » existe ; un autre mod s'appelle « SVE Patches ».
        // La recherche guidée passe le dossier : c'est lui qu'il faut ouvrir.
        let mods = [mod("Stardew Valley Expanded", folder: "SVE"),
                    mod("SVE Patches", folder: "SVEPatches")]
        #expect(ModFocusResolver.resolve("SVE", in: mods)?.folderName == "SVE")
    }

    @Test func aPackIsFoundByItsFolderName() {
        // Le cas qui cassait en silence : un pack de premier niveau n'existe
        // pas dans la liste aplatie, où l'ancienne résolution cherchait seule.
        let pack = mod("Ridgeside Village", folder: "RidgesideVillage",
                       children: [mod("RSV Core"), mod("RSV Extras")])
        #expect(ModFocusResolver.resolve("RidgesideVillage", in: [pack])?.folderName
                == "RidgesideVillage")
    }

    @Test func anExactNameWinsOverALongerOneContainingIt() {
        let mods = [mod("Content Patcher Animations"), mod("Content Patcher")]
        #expect(ModFocusResolver.resolve("Content Patcher", in: mods)?.name
                == "Content Patcher")
    }

    @Test func aLoggedNameStillMatchesPartially() {
        // Ce que faisait déjà le saut depuis une ligne de log : SMAPI affiche
        // un nom qui n'est pas toujours celui du manifeste.
        let mods = [mod("Automate")]
        #expect(ModFocusResolver.resolve("automate", in: mods)?.name == "Automate")
    }

    @Test func aChildOfAPackIsFoundByItsOwnName() {
        // SMAPI nomme le composant, pas le pack qui le contient.
        let pack = mod("Ridgeside Village", folder: "RidgesideVillage",
                       children: [mod("RSV Core"), mod("RSV Extras")])
        #expect(ModFocusResolver.resolve("RSV Core", in: [pack])?.name == "RSV Core")
    }

    @Test func aPartialMatchReachesAPackByItsName() {
        // Changement de portée assumé : la résolution précédente ne regardait
        // que les composants, jamais les packs. « Ridgeside » ne trouvait rien.
        let pack = mod("Ridgeside Village", folder: "RidgesideVillage",
                       children: [mod("RSV Core"), mod("RSV Extras")])
        #expect(ModFocusResolver.resolve("Ridgeside", in: [pack])?.folderName
                == "RidgesideVillage")
    }

    @Test func aComponentWinsOverItsPackOnAPartialMatch() {
        // Quand les deux correspondent partiellement, c'est le composant :
        // le journal de SMAPI nomme celui qui a parlé, pas son emballage.
        let pack = mod("RSV", folder: "RidgesideVillage",
                       children: [mod("RSV Core"), mod("RSV Extras")])
        #expect(ModFocusResolver.resolve("RSV C", in: [pack])?.name == "RSV Core")
    }

    @Test func anEmptyQueryMatchesNothing() {
        // `contains("")` est vrai partout : sans cette garde, une demande vide
        // ouvrait la fiche du premier mod venu.
        #expect(ModFocusResolver.resolve("", in: [mod("Automate")]) == nil)
        #expect(ModFocusResolver.resolve("   ", in: [mod("Automate")]) == nil)
    }

    @Test func anUnknownModResolvesToNothing() {
        #expect(ModFocusResolver.resolve("Jamais installé", in: [mod("Automate")]) == nil)
    }

    @Test func aChildFolderNameResolvesToItsComponent() {
        // H-T6c : un conflit du journal porte un `folderName` produit par
        // `conflictFolderNames`, qui cherche dans `flattenedMods` — donc
        // parfois le dossier d'un ENFANT de pack. Le chercher uniquement parmi
        // les dossiers de premier niveau ne le trouvait jamais, et le bouton
        // « Ouvrir la fiche du mod » d'une ligne de conflit ne faisait rien.
        let pack = mod("RSV", folder: "RidgesideVillage",
                       children: [mod("RSV Core", folder: "[CP] RSV Core")])
        #expect(ModFocusResolver.resolve("[CP] RSV Core", in: [pack])?.name == "RSV Core")
    }

    @Test func aTopLevelFolderStillWinsOverAChildFolderOfTheSameName() {
        // Contre-épreuve du passage ci-dessus : la priorité au premier niveau
        // ne bouge pas. Un pack mis en pause par la recherche guidée doit
        // rester le pack, jamais son composant homonyme.
        let target = mod("Le bon", folder: "Ambigu")
        let pack = mod("Pack", folder: "Emballage",
                       children: [mod("Le mauvais", folder: "Ambigu")])
        #expect(ModFocusResolver.resolve("Ambigu", in: [target, pack])?.name == "Le bon")
    }
}
