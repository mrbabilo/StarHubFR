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
}
