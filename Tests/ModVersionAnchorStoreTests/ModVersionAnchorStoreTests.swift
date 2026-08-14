import Testing
import Foundation
@testable import StarHubTHCore

/// Le magasin est la mémoire des affirmations. Les tests injectent un domaine
/// `UserDefaults` dédié : toucher au domaine standard ferait écrire ces tests
/// dans les préférences réelles de l'utilisateur.
struct ModVersionAnchorStoreTests {

    private func freshDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func anchor(_ uid: String, _ v: String) -> ModVersionAnchor {
        ModVersionAnchor(uniqueId: uid, anchoredVersion: v,
                         origin: .install, anchoredAt: Date(timeIntervalSince1970: 42))
    }

    @Test func anAnchorSurvivesANewStoreOnTheSameDefaults() {
        let defaults = freshDefaults()
        ModVersionAnchorStore(defaults: defaults).put(anchor("a", "1.0"))
        // Un magasin neuf : c'est ce que fait un redémarrage de l'app.
        let reread = ModVersionAnchorStore(defaults: defaults).anchor(for: "a")
        #expect(reread?.anchoredVersion == "1.0")
    }

    @Test func puttingTwiceKeepsOnlyTheLatest() {
        let store = ModVersionAnchorStore(defaults: freshDefaults())
        store.put(anchor("a", "1.0"))
        store.put(anchor("a", "2.0"))
        #expect(store.all().count == 1)
        #expect(store.anchor(for: "a")?.anchoredVersion == "2.0")
    }

    @Test func anUnknownUniqueIdHasNoAnchor() {
        #expect(ModVersionAnchorStore(defaults: freshDefaults()).anchor(for: "nope") == nil)
    }

    @Test func removingDropsTheAnchor() {
        let store = ModVersionAnchorStore(defaults: freshDefaults())
        store.put(anchor("a", "1.0"))
        store.remove(uniqueId: "a")
        #expect(store.anchor(for: "a") == nil)
    }

    @Test func pruningDropsAnchorsForModsNoLongerInstalled() {
        // Un mod supprimé ne doit pas laisser son affirmation derrière lui :
        // réinstallé plus tard, il hériterait d'une version qu'il n'a pas.
        let store = ModVersionAnchorStore(defaults: freshDefaults())
        store.put(anchor("a", "1.0"))
        store.put(anchor("b", "1.0"))
        store.pruneAnchors(keeping: ["a"])
        #expect(Set(store.all().keys) == ["a"])
    }

    @Test func aCorruptPayloadYieldsAnEmptyStoreRatherThanACrash() {
        let defaults = freshDefaults()
        defaults.set(Data("pas du json".utf8), forKey: "modVersionAnchors")
        #expect(ModVersionAnchorStore(defaults: defaults).all().isEmpty)
    }

    @Test func migrationStripsNexusVersionFromEveryRegistryRecord() {
        // Le champ qui confondait « ce que Nexus a » et « ce qui est
        // installé ». On le retire sans toucher au reste de l'enregistrement.
        let defaults = freshDefaults()
        let legacy = """
        {"Mod A":{"version":"1.0","installedAt":700000000,"nexusVersion":"2.0"},
         "Mod B":{"version":"3.0","installedAt":700000001}}
        """
        defaults.set(Data(legacy.utf8), forKey: "installedModRegistry")

        let outcome = ModVersionAnchorStore.migrateAwayFromNexusVersion(defaults: defaults)

        // La liste nomme les dossiers, pas seulement leur nombre : c'est elle
        // qui protège leur date d'installation au premier scan suivant.
        #expect(outcome == .stripped(["Mod A"]))
        let raw = defaults.data(forKey: "installedModRegistry")!
        let json = try! JSONSerialization.jsonObject(with: raw) as! [String: [String: Any]]
        #expect(json["Mod A"]?["nexusVersion"] == nil)
        #expect(json["Mod A"]?["version"] as? String == "1.0")
        #expect(json["Mod B"]?["version"] as? String == "3.0")
    }

    @Test func migrationOnAnAbsentRegistryDoesNothing() {
        #expect(ModVersionAnchorStore.migrateAwayFromNexusVersion(defaults: freshDefaults()) == .nothingToDo)
    }

    @Test func migrationOnAnUnreadableRegistryReturnsUnreadable() {
        let defaults = freshDefaults()
        defaults.set(Data("pas du json".utf8), forKey: "installedModRegistry")
        #expect(ModVersionAnchorStore.migrateAwayFromNexusVersion(defaults: defaults) == .registryUnreadable)
    }

    @Test func migrationOnARegistryWithoutNexusVersionReturnsNothingToDo() {
        let defaults = freshDefaults()
        let legacy = """
        {"Mod A":{"version":"1.0","installedAt":700000000},
         "Mod B":{"version":"3.0","installedAt":700000001}}
        """
        defaults.set(Data(legacy.utf8), forKey: "installedModRegistry")
        #expect(ModVersionAnchorStore.migrateAwayFromNexusVersion(defaults: defaults) == .nothingToDo)
    }
}
