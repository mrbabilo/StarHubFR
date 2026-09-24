import Testing
import Foundation
@testable import StarHubTHCore

/// C4-T13 — la vue « tous les raccourcis ».
struct KeybindOverviewTests {
    private func tree(_ pairs: [(String, ConfigJSONTree.Value)]) -> ConfigJSONTree.Value {
        .object(ConfigJSONTree.Object(pairs))
    }
    private func mod(_ id: String, _ name: String, active: Bool = true,
                     _ pairs: [(String, ConfigJSONTree.Value)]) -> KeybindScanner.ModScan {
        .init(id: id, name: name, isActive: active, tree: tree(pairs))
    }

    /// Le parc réel : 108 liés + 68 à `None` sur 48 mods. Les liés doivent
    /// égaler `keybindCount` — le chiffre que l'en-tête annonce déjà.
    @Test func listsBoundAndUnassignedSettingsOfActiveModsOnly() {
        let r = KeybindScanner.report(mods: [
            mod("a", "Alpha", [("OpenMenuKey", .string("F7")), ("FreezeTimeKey", .string("None")),
                               ("Volume", .number("50"))]),
            mod("b", "Beta", active: false, [("OpenMenuKey", .string("F9"))]),
        ])
        #expect(r.settings.map(\.keyPath) == [["FreezeTimeKey"], ["OpenMenuKey"]])
        #expect(r.settings.filter { !$0.isUnassigned }.count == r.keybindCount)
        #expect(r.settings.first { $0.keyPath == ["FreezeTimeKey"] }?.isUnassigned == true)
        #expect(r.settings.first { $0.keyPath == ["OpenMenuKey"] }?.combos.map(\.display) == ["F7"])
    }

    /// Même périmètre que `problemCount` : collision entre mods actifs et
    /// contrôle du jeu, oui ; co-déclenchement (sous-ensemble), non.
    @Test func conflictMarkMatchesProvenProblemsOnly() {
        let r = KeybindScanner.report(mods: [
            mod("a", "Alpha", [("Hotkey", .string("F8")), ("OtherKey", .string("F10")),
                               ("WalkKey", .string("W"))]),
            mod("b", "Beta", [("Shortcut", .string("F8")),
                              ("ComboKey", .string("LeftControl + F10"))]),
        ])
        func conflict(_ id: String, _ key: String) -> Bool? {
            r.settings.first { $0.modID == id && $0.keyPath == [key] }?.hasConflict
        }
        #expect(conflict("a", "Hotkey") == true)
        #expect(conflict("b", "Shortcut") == true)
        #expect(conflict("a", "WalkKey") == true)       // moveUpButton
        #expect(conflict("a", "OtherKey") == false)     // sous-ensemble seulement
        #expect(conflict("b", "ComboKey") == false)
        #expect(!r.subsetOverlaps.isEmpty)
    }

    /// Identité `(modID, keyPath)` : un chemin joint confondrait ces deux
    /// réglages, et deux homonymes (Swim installé deux fois) aussi.
    @Test func identityKeepsPathSegmentsAndHomonymsApart() {
        let dotted = KeybindScanner.SettingBinding(modID: "a", modName: "Swim", keyPath: ["a.b"],
                                                   combos: [], hasConflict: false)
        let nested = KeybindScanner.SettingBinding(modID: "a", modName: "Swim", keyPath: ["a", "b"],
                                                   combos: [], hasConflict: false)
        let twin = KeybindScanner.SettingBinding(modID: "a2", modName: "Swim", keyPath: ["a.b"],
                                                 combos: [], hasConflict: false)
        #expect(Set([dotted.id, nested.id, twin.id]).count == 3)
    }

    @Test func filterThenSearchOnNamePathAndKeys() {
        let r = KeybindScanner.report(mods: [
            mod("a", "Élan", [("OpenMenuKey", .string("F7")), ("FreezeTimeKey", .string("None"))]),
            mod("b", "Beta", [("Shortcut", .string("F7"))]),
        ])
        let s = r.settings
        #expect(KeybindScanner.overview(s, filter: .all, query: "").count == 3)
        #expect(KeybindScanner.overview(s, filter: .bound, query: "").count == 2)
        #expect(KeybindScanner.overview(s, filter: .unassigned, query: "").map(\.keyPath) == [["FreezeTimeKey"]])
        #expect(KeybindScanner.overview(s, filter: .conflicts, query: "").map(\.modID).sorted() == ["a", "b"])
        #expect(KeybindScanner.overview(s, filter: .all, query: "elan").count == 2)     // accent, casse
        #expect(KeybindScanner.overview(s, filter: .all, query: "freeze").count == 1)   // chemin
        #expect(KeybindScanner.overview(s, filter: .all, query: " f7 ").count == 2)     // touche
        #expect(KeybindScanner.overview(s, filter: .unassigned, query: "f7").isEmpty)
    }
}
