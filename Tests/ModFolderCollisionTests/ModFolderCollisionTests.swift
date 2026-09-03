import Testing
import Foundation
@testable import StarHubTHCore

/// Deux mods peuvent réclamer le **même nom logique de dossier** : `X` actif et
/// `.X` en pause sont deux dossiers distincts sur le disque, mais
/// `ModItem.folderName` retire le point de tête, donc les deux portent la même
/// clé.
///
/// Ce n'est pas une hypothèse : sur le parc de l'auteur, `[CP] Seaside Sounds`
/// (`witchtopia.SeasideSounds`, actif) et `.[CP] Seaside Sounds`
/// (`Liana.SeasideSounds`, en pause) sont deux mods différents, d'auteurs
/// différents. 1 074 noms logiques pour 1 075 dossiers.
///
/// Ce que ça coûte à la bascule : `toggleMod` met de côté ce qu'il trouve à
/// destination, en supposant qu'un résidu de bascule plantée. Sur cette
/// collision, c'est un **autre mod, installé et actif**, qui se ferait
/// déplacer.
struct ModFolderCollisionTests {

    @Test func aDestinationHoldingAnotherModIsNotAStaleDuplicate() {
        // Le cas réel, et le seul qui doive faire refuser la bascule.
        #expect(!ModFolderCollision.isStaleDuplicate(
            destinationUniqueId: "witchtopia.SeasideSounds",
            toggling: "Liana.SeasideSounds"))
    }

    @Test func aDestinationHoldingTheSameModIsAStaleDuplicate() {
        // Une bascule plantée laisse un résidu du **même** mod : le mettre de
        // côté puis écrire par-dessus est le comportement voulu, et il reste.
        #expect(ModFolderCollision.isStaleDuplicate(
            destinationUniqueId: "Liana.SeasideSounds",
            toggling: "Liana.SeasideSounds"))
    }

    @Test func identityIgnoresCaseLikeSmapiDoes() {
        // SMAPI compare les `UniqueID` sans regarder la casse ; un manifeste
        // réédité avec une majuscule différente ne fait pas un autre mod.
        #expect(ModFolderCollision.isStaleDuplicate(
            destinationUniqueId: "liana.seasidesounds",
            toggling: "Liana.SeasideSounds"))
    }

    @Test func anUnreadableDestinationCountsAsStale() {
        // Un dossier à moitié écrit par une bascule plantée n'a pas de
        // manifeste lisible. Refuser là-dessus bloquerait la réparation d'un
        // état que ce mécanisme existe justement pour réparer.
        #expect(ModFolderCollision.isStaleDuplicate(destinationUniqueId: nil,
                                                    toggling: "Liana.SeasideSounds"))
        #expect(ModFolderCollision.isStaleDuplicate(destinationUniqueId: "  ",
                                                    toggling: "Liana.SeasideSounds"))
    }

    @Test func aModWithoutIdentityNeverAuthorisesADisplacement() {
        // Sans identité du côté qu'on bascule, on ne peut rien comparer — et
        // ce qu'on ne sait pas ne justifie pas de déplacer le dossier d'autrui.
        #expect(!ModFolderCollision.isStaleDuplicate(destinationUniqueId: "someone.else",
                                                     toggling: ""))
    }

    // MARK: - Le relevé des collisions

    private func claim(_ folder: String, _ uid: String) -> ModFolderCollision.Claim {
        .init(folderName: folder, uniqueId: uid)
    }

    @Test func collisionsNameTheFolderAndItsClaimants() {
        let found = ModFolderCollision.collisions([
            claim("[CP] Seaside Sounds", "witchtopia.SeasideSounds"),
            claim("[CP] Seaside Sounds", "Liana.SeasideSounds"),
            claim("Automate", "Pathoschild.Automate"),
        ])
        #expect(found.count == 1)
        #expect(found.first?.folderName == "[CP] Seaside Sounds")
        // Triés : deux affichages successifs ne doivent pas permuter la liste.
        #expect(found.first?.uniqueIds == ["Liana.SeasideSounds", "witchtopia.SeasideSounds"])
    }

    @Test func oneModListedTwiceIsNotACollision() {
        // La même entrée vue deux fois — un scan concurrent, un pack déplié en
        // double — n'oppose pas deux mods : c'est une seule identité.
        #expect(ModFolderCollision.collisions([
            claim("Automate", "Pathoschild.Automate"),
            claim("Automate", "pathoschild.automate"),
        ]).isEmpty)
    }

    @Test func aClaimWithoutIdentityIsIgnored() {
        // 111 mods du parc n'ont pas d'`UniqueID` : ils ne peuvent pas
        // témoigner d'une collision d'identité.
        #expect(ModFolderCollision.collisions([
            claim("Truc", ""), claim("Truc", ""),
        ]).isEmpty)
    }
}
