import Testing
import Foundation
@testable import StarHubTHCore

/// L'état de la vitrine : ce que les sections ont rendu, ce qui est encore en
/// vol, et la dernière panne.
///
/// La règle qui vaut l'extraction est le **compteur de requêtes en vol** : le
/// voyant ne s'éteint qu'au retour de la *dernière* réponse, pas de la
/// première. Il vivait en deux copies verbatim dans le ViewModel — un
/// compteur et son drapeau, dupliqués, c'est la forme exacte des divergences
/// que ce dépôt a déjà payées.
@Suite struct DiscoveryStoreTests {

    /// Deux vraies catégories du jeu — les fabriquer à la main inventerait
    /// une forme que `NexusCategory.all` ne produit pas.
    private func category(_ index: Int) -> NexusCategory { NexusCategory.all[index] }

    // MARK: - Le compteur de requêtes en vol

    @Test func theSpinnerLightsOnTheFirstFetch() {
        let s = DiscoveryStore()
        #expect(s.loading == false)
        s.beginFetch()
        #expect(s.loading)
    }

    @Test func theSpinnerStaysOnUntilTheLastAnswerComesBack() {
        let s = DiscoveryStore()
        s.beginFetch(); s.beginFetch()
        s.finishFetch()
        #expect(s.loading)      // il en reste une en vol
        s.finishFetch()
        #expect(s.loading == false)
    }

    /// Le `max(0, …)` du ViewModel défendait contre un rappel en trop —
    /// rien ne l'épinglait. Un compteur passé sous zéro laisserait le voyant
    /// allumé au prochain chargement, une requête durant.
    @Test func aSpuriousAnswerDoesNotPushTheCounterNegative() {
        let s = DiscoveryStore()
        s.beginFetch()
        s.finishFetch()
        s.finishFetch()         // rappel en trop
        #expect(s.loading == false)
        s.beginFetch()
        #expect(s.loading)
        s.finishFetch()
        #expect(s.loading == false)
    }

    // MARK: - Une réponse d'une catégorie qu'on a quittée

    @Test func ananswerForTheCurrentCategoryIsStillWanted() {
        let s = DiscoveryStore()
        _ = s.setCategory(category(1))
        #expect(s.isStillWanted(category: category(1)))
    }

    @Test func ananswerForACategoryWeLeftIsNotWanted() {
        // La réponse arrive après que l'utilisateur a changé de catégorie :
        // l'afficher montrerait des mods d'une catégorie qu'on vient de
        // quitter.
        let s = DiscoveryStore()
        _ = s.setCategory(category(2))
        #expect(s.isStillWanted(category: category(1)) == false)
    }

    @Test func theAllCategoriesViewIsItsOwnIdentity_notAWildcard() {
        let s = DiscoveryStore()
        #expect(s.isStillWanted(category: nil))
        #expect(s.isStillWanted(category: category(1)) == false)
        _ = s.setCategory(category(1))
        #expect(s.isStillWanted(category: nil) == false)
    }

    // MARK: - La panne affichée

    /// Sans cette remise à zéro, un bandeau d'erreur restait en haut de
    /// l'onglet pour toujours — y compris après un chargement réussi.
    @Test func startingALoadClearsThePreviousFailure() {
        let s = DiscoveryStore()
        s.recordFailure(.noApiKey)
        #expect(s.lastError != nil)
        s.startLoad()
        #expect(s.lastError == nil)
    }

    // MARK: - Changer de catégorie

    @Test func settingTheSameCategoryAgainChangesNothing() {
        // La garde d'idempotence : sans elle, rouvrir le même filtre
        // relancerait trois requêtes pour rien.
        let s = DiscoveryStore()
        #expect(s.setCategory(category(1)) == true)
        #expect(s.setCategory(category(1)) == false)
        #expect(s.setCategory(nil) == true)
    }
}
