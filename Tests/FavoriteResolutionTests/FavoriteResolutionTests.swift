import Testing
import Foundation
@testable import StarHubTHCore

struct FavoriteResolutionTests {
    private func mod(_ folder: String, id: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: id, name: folder, folderName: folder, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [], languages: [])
    }

    private func pack(_ folder: String, children: [ModItem]) -> ModItem {
        var group = mod(folder, id: "")
        group.children = children
        group.isGroup = true
        return group
    }

    @Test func aFavouriteModContributesItsOwnIdentifier() {
        let result = FavoriteResolution.profileIds(
            favorites: ["SpaceCore"], in: [mod("SpaceCore", id: "spacechase0.SpaceCore")])
        #expect(result.ids == ["spacechase0.SpaceCore"])
        #expect(result.unresolved.isEmpty)
    }

    /// Un pack n'a pas d'identifiant à lui : ce sont ses composants qui entrent
    /// dans le profil, comme quand la bissection traduit des dossiers actifs.
    @Test func aFavouritePackContributesEveryComponent() {
        let sve = pack("SVE", children: [mod("SVE/Core", id: "FlashShifter.SVE"),
                                         mod("SVE/Extra", id: "FlashShifter.SVEExtra")])
        let result = FavoriteResolution.profileIds(favorites: ["SVE"], in: [sve])
        #expect(result.ids == ["FlashShifter.SVE", "FlashShifter.SVEExtra"])
        #expect(result.unresolved.isEmpty)
    }

    /// Marquer un favori puis désinstaller le mod : l'import doit le dire, et
    /// non prétendre avoir tout pris.
    @Test func aFavouriteThatIsNoLongerInstalledIsReported() {
        let result = FavoriteResolution.profileIds(
            favorites: ["Gone", "SpaceCore"], in: [mod("SpaceCore", id: "spacechase0.SpaceCore")])
        #expect(result.ids == ["spacechase0.SpaceCore"])
        #expect(result.unresolved == ["Gone"])
    }

    /// Un manifeste sans `UniqueID` ne peut pas entrer dans un profil, qui ne
    /// connaît que ça. `applyEnabledFolders` l'écarte en silence ; ici il est
    /// nommé.
    @Test func aModWithoutAnIdentifierIsReportedRatherThanDropped() {
        let result = FavoriteResolution.profileIds(favorites: ["Nameless"],
                                                   in: [mod("Nameless", id: "")])
        #expect(result.ids.isEmpty)
        #expect(result.unresolved == ["Nameless"])
    }

    /// Un pack dont aucun composant n'a d'identifiant n'apporte rien non plus.
    @Test func aPackWithNoUsableComponentIsReported() {
        let empty = pack("Broken", children: [mod("Broken/A", id: ""), mod("Broken/B", id: "")])
        let result = FavoriteResolution.profileIds(favorites: ["Broken"], in: [empty])
        #expect(result.ids.isEmpty)
        #expect(result.unresolved == ["Broken"])
    }

    /// Un pack partiellement identifié apporte ce qu'il peut, sans être
    /// signalé : le favori a bien contribué.
    @Test func aPartlyIdentifiedPackContributesWhatItCan() {
        let half = pack("Half", children: [mod("Half/A", id: "author.A"), mod("Half/B", id: "")])
        let result = FavoriteResolution.profileIds(favorites: ["Half"], in: [half])
        #expect(result.ids == ["author.A"])
        #expect(result.unresolved.isEmpty)
    }

    /// Le profil contient déjà le mod : l'import ne doit pas le dupliquer.
    /// Deux identifiants de même identité dans `enabledModIds`, c'est la classe
    /// de défaut qui a déjà coûté des lignes fantômes à un `ForEach`.
    @Test func aModAlreadyInTheProfileIsNotAddedTwice() {
        let result = FavoriteResolution.profileIds(
            favorites: ["SpaceCore"], in: [mod("SpaceCore", id: "spacechase0.SpaceCore")],
            existing: ["spacechase0.SpaceCore"])
        #expect(result.ids.isEmpty)
        #expect(result.unresolved.isEmpty)
    }

    /// La comparaison ignore la casse, comme `addModToProfile`.
    @Test func deduplicationIgnoresCase() {
        let result = FavoriteResolution.profileIds(
            favorites: ["SpaceCore"], in: [mod("SpaceCore", id: "spacechase0.SpaceCore")],
            existing: ["SPACECHASE0.SPACECORE"])
        #expect(result.ids.isEmpty)
    }

    /// Deux favoris portant le même identifiant — 58 identifiants Nexus du
    /// parc réel sont portés par plusieurs dossiers — ne l'ajoutent qu'une fois.
    @Test func twoFavouritesSharingAnIdentifierContributeItOnce() {
        let mods = [mod("CopyA", id: "shared.Id"), mod("CopyB", id: "shared.Id")]
        let result = FavoriteResolution.profileIds(favorites: ["CopyA", "CopyB"], in: mods)
        #expect(result.ids == ["shared.Id"])
    }

    /// L'ordre d'un `Set` n'est pas un contrat : deux imports du même jeu de
    /// favoris doivent donner le même profil.
    @Test func theResultIsOrderedByFavouriteName() {
        let mods = [mod("Zulu", id: "z.Id"), mod("Alpha", id: "a.Id"), mod("Mike", id: "m.Id")]
        let result = FavoriteResolution.profileIds(favorites: ["Zulu", "Alpha", "Mike"], in: mods)
        #expect(result.ids == ["a.Id", "m.Id", "z.Id"])
    }

    @Test func noFavouritesResolvesToNothingAtAll() {
        let result = FavoriteResolution.profileIds(favorites: [], in: [mod("A", id: "a")])
        #expect(result.ids.isEmpty)
        #expect(result.unresolved.isEmpty)
    }

    /// Un mod en pause reste favori : la clé est le nom **logique**, celui qui
    /// ne porte pas le point du dossier mis de côté.
    @Test func aPausedModIsStillResolvable() {
        let result = FavoriteResolution.profileIds(
            favorites: ["Sleeping"], in: [mod("Sleeping", id: "some.Id", enabled: false)])
        #expect(result.ids == ["some.Id"])
    }
}
