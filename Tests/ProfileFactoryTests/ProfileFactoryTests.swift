import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct ProfileFactoryTests {

    // MARK: - B3-T1 · profil vide ou instantané

    /// Le défaut demandé par l'auteur : créer un profil **vide**, pas une copie
    /// de ce qui tourne. La page l'annonçait déjà (« démarre sans mod actif »)
    /// alors que le code capturait les mods actifs.
    @Test func anEmptyProfileStartsWithNoMods() {
        let made = ProfileFactory.make(name: "Multi", seed: .empty, enabledUniqueIds: ["a.mod", "b.mod"])

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
        let made = ProfileFactory.make(name: "Multi", seed: .empty, enabledUniqueIds: ["a.mod"])

        #expect(!made.activate)
    }

    /// L'autre choix reste offert : capturer ce qui tourne.
    @Test func aSnapshotProfileKeepsTheModsCurrentlyEnabled() {
        let made = ProfileFactory.make(name: "Solo",
                                       seed: .currentlyEnabledMods,
                                       enabledUniqueIds: ["a.mod", "b.mod"])

        #expect(made.profile.enabledModIds == ["a.mod", "b.mod"])
    }

    /// Celui-là peut devenir actif sans rien déplacer : son contenu est
    /// exactement l'état du disque au moment de la création.
    @Test func aSnapshotProfileIsActivatedOnCreation() {
        let made = ProfileFactory.make(name: "Solo",
                                       seed: .currentlyEnabledMods,
                                       enabledUniqueIds: ["a.mod"])

        #expect(made.activate)
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
    @Test func aDuplicateHasItsOwnIdentity() {
        let source = ModProfile(name: "Solo", enabledModIds: ["a.mod"])

        let copy = ProfileFactory.duplicate(source, nameFormat: "%@ (copie)")

        #expect(copy.id != source.id)
    }
}
