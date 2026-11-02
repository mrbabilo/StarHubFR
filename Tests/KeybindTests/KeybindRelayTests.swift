import Testing
import Foundation
@testable import StarHubTHCore

/// Les touches qu'un mod **rejoue** pour d'autres mods (Taum's Inventory
/// Hotkeys, décompilé le 2026-11-02) : `Tabs[].Keybinds` porte les touches
/// des mods ciblés, que le mod simule. Ce ne sont pas ses liaisons : hors
/// collisions, et un bouton qu'aucun mod actif ne lie ne déclenche rien.
struct KeybindRelayTests {
    private func tab(_ keys: String) -> ConfigJSONTree.Value {
        .object(ConfigJSONTree.Object([("Name", .string("t")), ("Keybinds", .string(keys))]))
    }
    private func mod(_ id: String, _ uid: String, active: Bool = true,
                     _ pairs: [(String, ConfigJSONTree.Value)]) -> KeybindScanner.ModScan {
        .init(id: id, name: id, isActive: active, tree: .object(ConfigJSONTree.Object(pairs)), uniqueId: uid)
    }
    private let contexts = KeybindContexts(rules: [
        "Taum.InventoryHotkeys": [.init(keyPaths: ["Tabs.[].Keybinds"], emitted: true)],
    ])

    private func setup(targetActive: Bool) -> [KeybindScanner.ModScan] {
        [mod("Taum", "taum.inventoryhotkeys",
             [("Tabs", .array([tab("NumPad3"), tab("End"), tab("F6")]))]),
         mod("Ultra", "x.ultra", active: targetActive, [("ToggleKey", .string("NumPad3"))]),
         mod("Save", "x.save", [("SaveKey", .string("F6"))])]
    }

    @Test func emittedKeysAreNotCollisions() {
        let r = KeybindScanner.report(mods: setup(targetActive: true), contexts: contexts)
        #expect(r.collisions.isEmpty)
        #expect(r.gameConflicts.isEmpty)
        #expect(r.catalogModsIgnored.isEmpty)
        #expect(r.activeUses.values.allSatisfy { $0.allSatisfy { $0.modID != "Taum" } })
    }

    @Test func withoutTheRuleTheyStillCollide() {
        let r = KeybindScanner.report(mods: setup(targetActive: true))
        #expect(r.collisions.count == 2)
    }

    /// Un bouton dont la touche n'est liée par aucun mod **actif** : mort.
    @Test func aRelayWithoutAnActiveTargetIsDead() {
        let mods = setup(targetActive: false)
        let r = KeybindScanner.report(mods: mods, contexts: contexts)
        let relays = KeybindScanner.relays(mods: mods, contexts: contexts, activeUses: r.activeUses)
        #expect(relays.emittingMods == ["Taum"])
        #expect(relays.dead.map(\.combo.display) == ["End", "NumPad3"])
        #expect(relays.dead.allSatisfy { $0.modName == "Taum" && $0.keyPath.last == "Keybinds" })
    }

    @Test func aPausedRelayModEmitsNothing() {
        var mods = setup(targetActive: false)
        mods[0] = mod("Taum", "taum.inventoryhotkeys", active: false, [("Tabs", .array([tab("End")]))])
        let r = KeybindScanner.report(mods: mods, contexts: contexts)
        let relays = KeybindScanner.relays(mods: mods, contexts: contexts, activeUses: r.activeUses)
        #expect(relays.emittingMods.isEmpty)
        #expect(relays.dead.isEmpty)
    }
}
