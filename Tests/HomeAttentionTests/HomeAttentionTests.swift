import Testing
@testable import StarHubTHCore

struct HomeAttentionTests {

    // MARK: - Les quatre compteurs

    @Test func allFourCountersAreAlwaysRendered() {
        // Un zéro affiché est une information : « aucune mise à jour » se lit,
        // « rien » ne se lit pas. Les quatre sortent, quels que soient les
        // chiffres.
        let counters = HomeAttention.counters(updates: 0, alerts: 0, quarantined: 0, mods: 0)
        #expect(counters.count == 4)
        #expect(counters.map(\.kind) == [.updates, .alerts, .quarantine, .library])
    }

    @Test func aZeroCountIsCalmNotAttention() {
        let counters = HomeAttention.counters(updates: 0, alerts: 0, quarantined: 0, mods: 966)
        #expect(counters.allSatisfy { $0.level == .calm })
    }

    @Test func eachProblemCounterRaisesAttentionOnItsOwn() {
        #expect(HomeAttention.counters(updates: 12, alerts: 0, quarantined: 0, mods: 966)
            .first { $0.kind == .updates }?.level == .attention)
        #expect(HomeAttention.counters(updates: 0, alerts: 3, quarantined: 0, mods: 966)
            .first { $0.kind == .alerts }?.level == .attention)
        #expect(HomeAttention.counters(updates: 0, alerts: 0, quarantined: 1, mods: 966)
            .first { $0.kind == .quarantine }?.level == .attention)
    }

    @Test func theLibraryCountNeverRaisesAttention() {
        // Le parc est un **constat**, pas une alerte : 966 mods n'est pas un
        // problème, et 0 mod non plus — c'est une bibliothèque vide, pas une
        // panne. Le teindre en orange crierait pour rien.
        for count in [0, 1, 966, 10_000] {
            #expect(HomeAttention.counters(updates: 0, alerts: 0, quarantined: 0, mods: count)
                .first { $0.kind == .library }?.level == .calm)
        }
    }

    @Test func aCounterCarriesItsDestinationTab() {
        // Le compteur porte l'onglet où il mène : la vue ne doit pas
        // ré-associer à la main ce que le modèle sait déjà.
        let counters = HomeAttention.counters(updates: 1, alerts: 1, quarantined: 1, mods: 1)
        #expect(counters.first { $0.kind == .updates }?.tab == "Updates")
        #expect(counters.first { $0.kind == .alerts }?.tab == "SystemAlerts")
        #expect(counters.first { $0.kind == .quarantine }?.tab == "Quarantine")
        #expect(counters.first { $0.kind == .library }?.tab == "Mods")
    }

    // MARK: - L'état de lancement

    @Test func noGameFolderOutranksEverythingElse() {
        // Sans dossier de jeu, installer SMAPI n'a nulle part où écrire :
        // l'action qui lève l'état est de choisir le dossier, pas d'installer.
        #expect(HomeLaunchState.resolve(gameDirIsEmpty: true, smapiInstalled: false,
                                        profileIsVanilla: false) == .needsGameFolder)
        #expect(HomeLaunchState.resolve(gameDirIsEmpty: true, smapiInstalled: true,
                                        profileIsVanilla: false) == .needsGameFolder)
    }

    @Test func missingSmapiIsItsOwnState() {
        #expect(HomeLaunchState.resolve(gameDirIsEmpty: false, smapiInstalled: false,
                                        profileIsVanilla: false) == .needsSmapi)
    }

    @Test func theVanillaProfileDoesNotDemandSmapi() {
        // Exiger SMAPI interdirait de jouer à un mode qui n'en veut pas.
        //
        // ⚠ Ce que ce modèle encode est le mode **demandé**, pas celui qui
        // partira : `launchGame()` ne lance vraiment le binaire vanilla que si
        // `StardewValley-original` existe dans le dossier du jeu — sinon il
        // retombe sur la branche SMAPI (StarHubTHViewModel.swift:3460).
        // L'accueil actuel affiche déjà le profil sans vérifier ce fichier :
        // on reproduit l'existant, on ne l'aggrave pas. Réconcilier les deux
        // demanderait d'exposer l'existence du binaire au ViewModel — une
        // capacité nouvelle, hors périmètre de la phase 1.
        #expect(HomeLaunchState.resolve(gameDirIsEmpty: false, smapiInstalled: false,
                                        profileIsVanilla: true) == .ready(mode: .vanilla))
    }

    @Test func everythingInPlaceIsReady() {
        #expect(HomeLaunchState.resolve(gameDirIsEmpty: false, smapiInstalled: true,
                                        profileIsVanilla: false) == .ready(mode: .smapi))
    }
}
