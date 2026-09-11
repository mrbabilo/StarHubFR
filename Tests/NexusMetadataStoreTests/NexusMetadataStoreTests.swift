import Foundation
import Testing
@testable import StarHubTHCore

/// Le store des métadonnées Nexus écrites par l'utilisateur (REFACTORING
/// §6) : persistance JSON dans une suite jetable, trim de l'identifiant,
/// migration de renommage et purge de suppression.
@Suite struct NexusMetadataStoreTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "NexusMetadataStoreTests-\(UUID().uuidString)")!
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        NexusMetadataStore(defaults: defaults).setCustomCategory(42, for: "SomeMod")
        NexusMetadataStore(defaults: defaults).setCustomModId("  1234  ", for: "SomeMod")

        // Une nouvelle instance relit les préférences : c'est le contrat de
        // survie au lancement.
        let reloaded = NexusMetadataStore(defaults: defaults)
        #expect(reloaded.customCategories["SomeMod"] == 42)
        #expect(reloaded.customModIds["SomeMod"] == "1234")
    }

    /// Le trim de l'identifiant fait partie de la règle : blanc = retirer,
    /// pas stocker des espaces.
    @Test func setCustomModIdTrimsAndRemovesOnBlank() {
        let defaults = makeDefaults()
        let store = NexusMetadataStore(defaults: defaults)
        store.setCustomModId("  1234  ", for: "Mod")
        #expect(store.customModIds["Mod"] == "1234")
        store.setCustomModId("   ", for: "Mod")
        #expect(store.customModIds["Mod"] == nil)
    }

    /// Épingler puis révoquer une catégorie : le retrait revient à
    /// l'automatique.
    @Test func setThenRemoveCustomCategory() {
        let defaults = makeDefaults()
        let store = NexusMetadataStore(defaults: defaults)
        store.setCustomCategory(7, for: "Mod")
        #expect(store.customCategories["Mod"] == 7)
        store.setCustomCategory(nil, for: "Mod")
        #expect(store.customCategories["Mod"] == nil)
    }

    /// Le plan d'apprentissage fusionne d'un bloc sans écraser les autres
    /// identifiants déjà présents.
    @Test func mergeCustomModIdsKeepsExisting() {
        let defaults = makeDefaults()
        let store = NexusMetadataStore(defaults: defaults)
        store.setCustomModId("1", for: "Already")
        store.mergeCustomModIds(["Learned": "2"])
        #expect(store.customModIds["Already"] == "1")
        #expect(store.customModIds["Learned"] == "2")
    }

    /// Un mod supprimé n'y laisse aucune trace, et la suppression d'une
    /// entrée inexistante ne réécrit pas pour rien (retour explicite).
    @Test func purgeRemovesBothMaps() {
        let defaults = makeDefaults()
        let store = NexusMetadataStore(defaults: defaults)
        store.setCustomCategory(7, for: "Gone")
        store.setCustomModId("1", for: "Gone")
        let purged = store.purgeMod(folderName: "Gone")
        #expect(purged)
        #expect(store.customCategories["Gone"] == nil)
        #expect(store.customModIds["Gone"] == nil)

        let second = store.purgeMod(folderName: "Gone")
        #expect(!second)
    }

    /// Le renommage suit les deux tables d'un coup (modIds en policy
    /// leaveBehind, catégories en suivi simple) — le contrat exact des deux
    /// appels d'origine.
    @Test func migrateFolderNameFollowsBothTables() {
        let defaults = makeDefaults()
        let store = NexusMetadataStore(defaults: defaults)
        store.setCustomModId("1", for: "Old")
        store.setCustomCategory(7, for: "Old")
        store.migrateFolderName(from: "Old", to: "New", shared: false)
        #expect(store.customModIds["New"] == "1")
        #expect(store.customCategories["New"] == 7)
        #expect(store.customModIds["Old"] == nil)
    }

    /// Le crochet d'invalidation, sur **les cinq** mutations.
    ///
    /// Depuis le passage à `@Observable`, ce crochet n'est plus un confort :
    /// c'est l'unique chemin par lequel le ViewModel apprend qu'il doit purger
    /// son cache de catégories et publier la révision qui rafraîchit la liste.
    /// Une mutation qui l'oublierait laisserait une catégorie épinglée
    /// invisible à l'écran — sans erreur ni plantage. Chaque mutation est donc
    /// vérifiée nommément, pas une seule en échantillon.
    @Test func everyMutationFiresTheInvalidationHook() {
        let defaults = makeDefaults()
        let store = NexusMetadataStore(defaults: defaults)
        var fired = 0
        store.setOnInvalidate { fired += 1 }

        store.setCustomCategory(42, for: "Mod")
        #expect(fired == 1, "setCustomCategory")
        store.setCustomModId("1234", for: "Mod")
        #expect(fired == 2, "setCustomModId")
        store.mergeCustomModIds(["Autre": "99"])
        #expect(fired == 3, "mergeCustomModIds")
        store.migrateFolderName(from: "Mod", to: "Renomme", shared: false)
        #expect(fired > 3, "migrateFolderName")

        let beforePurge = fired
        #expect(store.purgeMod(folderName: "Renomme"))
        #expect(fired > beforePurge, "purgeMod")
    }

    /// Poser le crochet ne doit pas le déclencher, et le retirer doit le taire :
    /// sinon le VM purgerait son cache au montage, à chaque lancement.
    @Test func settingTheHookIsSilentAndClearingItStops() {
        let defaults = makeDefaults()
        let store = NexusMetadataStore(defaults: defaults)
        var fired = 0
        store.setOnInvalidate { fired += 1 }
        #expect(fired == 0)

        store.setCustomCategory(1, for: "Mod")
        #expect(fired == 1)

        store.setOnInvalidate(nil)
        store.setCustomCategory(2, for: "Mod")
        #expect(fired == 1, "le crochet retiré ne doit plus être appelé")
    }
}
