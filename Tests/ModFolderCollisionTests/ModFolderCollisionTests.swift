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

    private func claim(_ folder: String, _ uid: String,
                       physical: String? = nil) -> ModFolderCollision.Claim {
        .init(folderName: folder, uniqueId: uid, physicalFolderName: physical ?? folder)
    }

    @Test func collisionsNameTheFolderAndItsClaimants() {
        let found = ModFolderCollision.collisions([
            claim("[CP] Seaside Sounds", "witchtopia.SeasideSounds"),
            claim("[CP] Seaside Sounds", "Liana.SeasideSounds",
                  physical: ".[CP] Seaside Sounds"),
            claim("Automate", "Pathoschild.Automate"),
        ])
        #expect(found.count == 1)
        #expect(found.first?.folderName == "[CP] Seaside Sounds")
        // Triés : deux affichages successifs ne doivent pas permuter la liste.
        #expect(found.first?.uniqueIds == ["Liana.SeasideSounds", "witchtopia.SeasideSounds"])
        // Les deux dossiers réels, triés : c'est ce qu'on montrera dans le
        // Finder, côte à côte.
        #expect(found.first?.physicalFolderNames
                == [".[CP] Seaside Sounds", "[CP] Seaside Sounds"])
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

/// La ligne d'alerte que la collision produit (X13).
struct FolderCollisionIssueTests {
    private let collision = ModFolderCollision.Collision(
        folderName: "[CP] Seaside Sounds",
        uniqueIds: ["Liana.SeasideSounds", "witchtopia.SeasideSounds"],
        physicalFolderNames: [".[CP] Seaside Sounds", "[CP] Seaside Sounds"])

    private func issues(_ collisions: [ModFolderCollision.Collision])
        -> [HealthIssue] {
        HealthIssueResolver.folderCollisionIssues(
            collisions, modsPath: "/Jeu/Mods",
            title: { "Deux mods réclament le dossier « \($0.folderName) »" },
            detail: { $0.uniqueIds.joined(separator: " · ") })
    }

    @Test func aCollisionBecomesAWarningNamingBothMods() {
        let found = issues([collision])
        #expect(found.count == 1)
        // Le jeu tourne — l'un des deux est en pause : ce n'est pas critique.
        // Mais ça cache un mod, donc pas une simple information non plus.
        #expect(found.first?.severity == .warning)
        #expect(found.first?.source == .folderCollision)
        #expect(found.first?.title.contains("[CP] Seaside Sounds") == true)
        #expect(found.first?.detail == "Liana.SeasideSounds · witchtopia.SeasideSounds")
    }

    @Test func theLineShowsBothFoldersAndOffersToRenameOne() {
        // Le premier bouton désigne les DEUX dossiers — « Voir la fiche »
        // prendrait le nom logique, c'est-à-dire la clé ambiguë elle-même.
        // Le second (X60) est le seul geste qui supprime la **cause** : tant
        // que les deux mods partagent ce nom, ils partagent tout ce que l'app
        // indexe dessus, et un profil ne peut pas échanger leurs états.
        #expect(issues([collision]).first?.actions
                == [.revealInFinder(paths: ["/Jeu/Mods/.[CP] Seaside Sounds",
                                            "/Jeu/Mods/[CP] Seaside Sounds"]),
                    .renameFolder(folderName: "[CP] Seaside Sounds")])
    }

    @Test func theIdentityFollowsTheDisputedFolderNotTheDisplayedNames() {
        // Elle doit survivre à un manifeste renommé entre deux scans, sinon la
        // ligne saute sous les doigts.
        let renamed = ModFolderCollision.Collision(
            folderName: "[CP] Seaside Sounds",
            uniqueIds: ["Liana.SeasideSounds", "autre.identite"],
            physicalFolderNames: collision.physicalFolderNames)
        #expect(issues([collision]).first?.id == issues([renamed]).first?.id)
    }

    @Test func aCollisionWithoutKnownFoldersStillOffersTheRename() {
        // Rien à **montrer** : mieux vaut pas de bouton Finder qu'un bouton qui
        // ouvre le dossier des mods au hasard. Mais le nom disputé, lui, est
        // connu — et c'est tout ce que le renommage demande.
        let unknown = ModFolderCollision.Collision(folderName: "X",
                                                   uniqueIds: ["a", "b"],
                                                   physicalFolderNames: [])
        #expect(issues([unknown]).first?.actions == [.renameFolder(folderName: "X")])
    }

    @Test func aPackComponentCollisionDoesNotOfferARenameThatCannotComplete() {
        // X72 — la feuille cherche ses prétendants dans `vm.mods`, qui ne
        // porte que les entrées de tête : un nom de composant
        // (`Pack/Composant`) n'y a aucun prétendant, la feuille s'ouvrirait
        // sur « le nom est vide » et le bouton resterait désactivé pour
        // toujours. L'offre est morte **par construction** : elle ne se fait
        // pas. Tranché par l'auteur le 2026-09-05 — retirer l'action plutôt
        // que donner un chemin de renommage aux composants (zéro occurrence
        // sur le parc ; la ligne et la révélation Finder restent).
        let component = ModFolderCollision.Collision(
            folderName: "Pack/Composant", uniqueIds: ["a.x", "b.x"],
            physicalFolderNames: ["Pack/Composant", ".Pack/Composant"])
        #expect(issues([component]).first?.actions
                == [.revealInFinder(paths: ["/Jeu/Mods/Pack/Composant",
                                            "/Jeu/Mods/.Pack/Composant"])])
    }

    // MARK: - Le dossier mis de côté

    /// Un résidu écarté doit être **préfixé d'un point** : sans lui, SMAPI
    /// continue de charger un dossier qui n'est plus censé compter — et il
    /// déclare le même `UniqueID` que celui qui vient de prendre sa place.
    @Test func theSetAsideFolderIsDotPrefixed() {
        let aside = ModFolderCollision.asideName(for: "[CP] Seaside Sounds")
        #expect(aside.hasPrefix(".[CP] Seaside Sounds"))
    }

    /// Un résidu déjà en pause ne gagne pas un second point.
    @Test func anAlreadyPausedResidueKeepsASingleDot() {
        let aside = ModFolderCollision.asideName(for: ".[CP] Seaside Sounds")
        #expect(aside.hasPrefix(".[CP] Seaside Sounds"))
        #expect(!aside.hasPrefix("..") )
    }

    /// Le suffixe rend le nom unique : deux résidus écartés coup sur coup ne
    /// doivent pas se percuter.
    @Test func twoSetAsidesNeverCollide() {
        #expect(ModFolderCollision.asideName(for: "X") != ModFolderCollision.asideName(for: "X"))
    }

    /// Le nom d'origine reste lisible dans le résidu : c'est ce qui permet à
    /// un humain de comprendre ce qu'il a sous les yeux dans `Mods/`.
    @Test func theOriginalNameStaysReadable() {
        #expect(ModFolderCollision.asideName(for: "MonMod").contains("MonMod"))
        #expect(ModFolderCollision.asideName(for: "MonMod").contains(".stale_"))
    }

    @Test func noCollisionYieldsNoLine() {
        #expect(issues([]).isEmpty)
    }
}
