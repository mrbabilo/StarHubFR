import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct ModFolderRenameTests {

    // MARK: - Ce qu'un nouveau nom doit valoir

    /// Le cas qui motive la fonctionnalité : donner un nom distinct à l'un des
    /// deux prétendants d'une collision.
    @Test func aFreeNameIsAccepted() {
        #expect(ModFolderRename.validate("[CP] Seaside Sounds (Liana)",
                                         renaming: "[CP] Seaside Sounds",
                                         existing: ["[CP] Seaside Sounds"]) == .ok)
    }

    /// Un nom déjà pris recréerait exactement la collision qu'on répare.
    @Test func aTakenNameIsRefused() {
        #expect(ModFolderRename.validate("Automate",
                                         renaming: "Seaside",
                                         existing: ["Automate", "Seaside"]) == .alreadyTaken)
    }

    /// ⚠️ Le disque de macOS est **insensible à la casse** par défaut :
    /// renommer « Seaside » en « seaside » ne libère rien et n'ouvre aucune
    /// place. Le refus doit donc l'être aussi.
    @Test func aNameTakenInAnotherCaseIsRefused() {
        #expect(ModFolderRename.validate("automate",
                                         renaming: "Seaside",
                                         existing: ["Automate"]) == .alreadyTaken)
    }

    /// Le point de tête est la **marque de pause**, pas une lettre du nom :
    /// l'accepter ferait croire qu'on peut mettre un mod en pause en le
    /// renommant, et le nom logique porte alors un point que tous les magasins
    /// refusent.
    @Test func aLeadingDotIsRefused() {
        #expect(ModFolderRename.validate(".Seaside", renaming: "Autre", existing: [])
                == .leadingDot)
    }

    /// Une barre oblique ferait un composant de pack — le nom logique d'un
    /// composant est `Pack/Composant`, et en fabriquer un depuis ce champ
    /// déplacerait le mod dans un autre dossier.
    @Test func aPathSeparatorIsRefused() {
        #expect(ModFolderRename.validate("Pack/Enfant", renaming: "Autre", existing: [])
                == .invalidCharacter)
        // Le deux-points est le séparateur historique du Finder : il apparaît
        // comme une barre oblique à l'écran.
        #expect(ModFolderRename.validate("A:B", renaming: "Autre", existing: [])
                == .invalidCharacter)
    }

    /// Un nom vide, ou fait de blancs, n'est pas un nom.
    @Test func anEmptyNameIsRefused() {
        #expect(ModFolderRename.validate("   ", renaming: "Autre", existing: []) == .empty)
        #expect(ModFolderRename.validate("", renaming: "Autre", existing: []) == .empty)
    }

    /// Le même nom qu'avant : rien à faire, et surtout pas douze migrations de
    /// magasins pour un renommage qui n'en est pas un.
    @Test func theSameNameIsRefused() {
        #expect(ModFolderRename.validate("Seaside", renaming: "Seaside", existing: ["Seaside"])
                == .unchanged)
    }

    /// Les blancs de bord sont retirés avant tout jugement : un nom qui ne
    /// diffère que par eux est le même nom.
    @Test func surroundingWhitespaceIsIgnored() {
        #expect(ModFolderRename.validate("  Seaside  ", renaming: "Seaside", existing: [])
                == .unchanged)
        #expect(ModFolderRename.sanitized("  Nouveau  ") == "Nouveau")
    }

    // MARK: - La migration des clés

    /// Le cas ordinaire : le mod renommé emporte sa clé.
    @Test func aKeyFollowsTheRenamedFolder() {
        var store = ["Seaside": 42, "Autre": 7]
        ModFolderRename.migrate(&store, from: "Seaside", to: "Nouveau",
                                shared: false)

        #expect(store == ["Nouveau": 42, "Autre": 7])
    }

    /// **Le cas d'une collision, pour une préférence.** La clé décrivait
    /// *deux* mods : celui qui reste la réclame encore. On la **copie** au lieu
    /// de la déplacer — sinon le mod resté en place perdrait son favori pour
    /// avoir laissé son voisin se renommer.
    @Test func aSharedPreferenceIsCopiedNotMoved() {
        var store = ["Seaside": 42]
        ModFolderRename.migrate(&store, from: "Seaside", to: "Seaside (Liana)",
                                shared: true)

        #expect(store == ["Seaside": 42, "Seaside (Liana)": 42])
    }

    /// Un pack emporte ses composants — leur nom logique est le chemin relatif
    /// sous lui. Même règle que `ModRemovalPurge`, et le même voisin à
    /// épargner : renommer `Pack` ne touche pas `PackDeLuxe`.
    @Test func componentsFollowTheirPackWithoutTouchingItsNeighbour() {
        var store = ["Pack": 1, "Pack/Un": 2, "Pack/Deux": 3, "PackDeLuxe": 4]
        ModFolderRename.migrate(&store, from: "Pack", to: "MonPack",
                                shared: false)

        #expect(store == ["MonPack": 1, "MonPack/Un": 2, "MonPack/Deux": 3, "PackDeLuxe": 4])
    }

    /// Un magasin qui ne connaît pas ce mod n'est pas touché — l'appelant ne
    /// réécrit alors rien sur le disque.
    @Test func anUnrelatedStoreIsLeftAlone() {
        var store = ["Autre": 1]
        let changed = ModFolderRename.migrate(&store, from: "Seaside", to: "Nouveau",
                                              shared: false)

        #expect(!changed)
        #expect(store == ["Autre": 1])
    }

    /// Même règle pour un ensemble : les favoris et le drapeau « sa config
    /// suit le profil » n'ont pas de valeur, juste une appartenance.
    @Test func aSetMigratesTheSameWay() {
        var favorites: Set<String> = ["Seaside", "Pack/Un", "Autre"]
        ModFolderRename.migrate(&favorites, from: "Pack", to: "MonPack",
                                shared: false)

        #expect(favorites == ["Seaside", "MonPack/Un", "Autre"])
    }

    /// Copier dans un ensemble garde bien les deux appartenances.
    @Test func aSharedSetMembershipIsCopied() {
        var favorites: Set<String> = ["Seaside"]
        ModFolderRename.migrate(&favorites, from: "Seaside", to: "Seaside (Liana)",
                                shared: true)

        #expect(favorites == ["Seaside", "Seaside (Liana)"])
    }

    // MARK: - Les noms physiques

    /// Le renommage préserve l'état : un mod en pause reste en pause, et son
    /// point de tête suit.
    @Test func aPausedModKeepsItsDot() {
        #expect(ModFolderRename.physicalName("Nouveau", pausedLike: ".Ancien") == ".Nouveau")
        #expect(ModFolderRename.physicalName("Nouveau", pausedLike: "Ancien") == "Nouveau")
    }

    /// **Et le cas qui ne se copie pas.** L'identifiant Nexus saisi à la main,
    /// la ligne de registre : ce ne sont pas des préférences, ce sont des
    /// **affirmations sur un mod**. Rien ne dit lequel des deux prétendants
    /// elles décrivaient. Les copier ferait affirmer au mod renommé un
    /// identifiant que personne n'a saisi pour lui — et il irait chercher ses
    /// mises à jour sur la page d'un autre. On les laisse où elles sont ; le
    /// mod renommé les réapprend de son propre manifeste au prochain scan.
    @Test func aSharedAssertionIsLeftBehindEntirely() {
        var store = ["Seaside": "12345"]
        let changed = ModFolderRename.migrate(&store, from: "Seaside", to: "Seaside (Liana)",
                                              shared: true, policy: .leaveBehind)

        #expect(!changed)
        #expect(store == ["Seaside": "12345"])
    }

    /// Hors collision, la politique ne s'applique pas : la clé décrit ce mod-là
    /// et le suit, affirmation ou préférence.
    @Test func anUnsharedAssertionStillFollowsItsMod() {
        var store = ["Seaside": "12345"]
        ModFolderRename.migrate(&store, from: "Seaside", to: "Nouveau",
                                shared: false, policy: .leaveBehind)

        #expect(store == ["Nouveau": "12345"])
    }
}
