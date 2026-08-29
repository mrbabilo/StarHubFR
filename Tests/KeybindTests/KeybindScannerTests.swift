import Testing
import Foundation
@testable import StarHubTHCore

struct KeybindScannerTests {
    private func tree(_ pairs: [String: ConfigJSONTree.Value]) -> ConfigJSONTree.Value {
        .object(ConfigJSONTree.Object(pairs.map { ($0.key, $0.value) }))
    }
    private var mod1: KeybindScanner.ModScan {
        .init(id: "a.Mod1", name: "Mod 1", isActive: true,
              tree: tree(["Hotkey": .string("LeftControl + F8"), "Volume": .number("50")]))
    }

    // — Heuristique
    @Test func r1NameHintWithValidValue() {
        let d = KeybindScanner.classify(leaf: .init(keyPath: ["Menu", "Hotkey"], value: .string("F8")))
        guard case .keybind(let combos) = d else { Issue.record("attendu keybind"); return }
        #expect(combos == [KeybindCombo(buttons: ["F8"])!])
    }

    @Test func r1NameHintWithGarbageIsUnrecognizedNotSilent() {
        let d = KeybindScanner.classify(leaf: .init(keyPath: ["openKey"], value: .string("ctrl+H")))
        guard case .unrecognized = d else { Issue.record("attendu unrecognized"); return }
    }

    @Test func r2DistinctiveValueWithoutName() {
        let d = KeybindScanner.classify(leaf: .init(keyPath: ["Display", "Chose"], value: .string("MouseLeft")))
        guard case .keybind = d else { Issue.record("attendu keybind"); return }
    }

    @Test func r2SingleLetterAndNoneAreNotDistinctive() {
        if case .keybind = KeybindScanner.classify(leaf: .init(keyPath: ["Lettre"], value: .string("K"))) {
            Issue.record("une lettre seule sans indice de nom n'est pas un raccourci")
        }
        if case .keybind = KeybindScanner.classify(leaf: .init(keyPath: ["Truc"], value: .string("None"))) {
            Issue.record("None sans indice de nom n'est pas un raccourci")
        }
    }

    @Test func r3IntNeedsNameHint() {
        if case .keybind = KeybindScanner.classify(leaf: .init(keyPath: ["Nombre"], value: .number("119"))) {
            Issue.record("un entier sans indice de nom n'est pas un raccourci")
        }
        guard case .keybind = KeybindScanner.classify(leaf: .init(keyPath: ["menuKeybind"], value: .number("119"))) else {
            Issue.record("un entier hinté doit être un raccourci"); return
        }
    }

    // — Scanner
    @Test func exactComboCollisionIsReported() {
        let a = mod1
        let b = KeybindScanner.ModScan(id: "b.Mod2", name: "Mod 2", isActive: true,
                                       tree: tree(["Shortcut": .string("F8 + LeftControl")]))
        let r = KeybindScanner.report(mods: [a, b])
        #expect(r.collisions.count == 1)
        #expect(r.collisions[0].combo.buttons == ["F8", "LeftControl"])
        #expect(r.collisions[0].uses.map(\.modID).sorted() == ["a.Mod1", "b.Mod2"])
    }

    @Test func sharedModifierAloneIsNotACollision_counterExampleMCM() {
        let b = KeybindScanner.ModScan(id: "b.Mod2", name: "Mod 2", isActive: true,
                                       tree: tree(["Shortcut": .string("LeftControl + H")]))
        let r = KeybindScanner.report(mods: [mod1, b])
        #expect(r.collisions.isEmpty)
    }

    @Test func secondComboInAListCounts() {
        let b = KeybindScanner.ModScan(id: "b.Mod2", name: "Mod 2", isActive: true,
                                       tree: tree(["Hotkey": .string("J, LeftControl + F8")]))
        #expect(KeybindScanner.report(mods: [mod1, b]).collisions.count == 1)
    }

    @Test func pausedModsAreExcludedAndCounted() {
        let paused = KeybindScanner.ModScan(id: "p.Mod", name: "Pause", isActive: false,
                                            tree: tree(["Hotkey": .string("LeftControl + F8")]))
        let r = KeybindScanner.report(mods: [mod1, paused])
        #expect(r.collisions.isEmpty)
        #expect(r.pausedIgnored == 1)
    }

    @Test func noneNeverCollides() {
        let b = KeybindScanner.ModScan(id: "b.Mod2", name: "Mod 2", isActive: true,
                                       tree: tree(["Hotkey": .string("None")]))
        #expect(KeybindScanner.report(mods: [mod1, b]).collisions.isEmpty)
    }

    @Test func gameControlConflictOnlyForSingleButtonCombos() {
        // W est moveUp par défaut (relevé tâche 0) — à bouton unique ça conflit…
        let w = KeybindScanner.ModScan(id: "w.Mod", name: "W Mod", isActive: true,
                                       tree: tree(["Hotkey": .string("W")]))
        #expect(KeybindScanner.report(mods: [w]).gameConflicts.isEmpty == false)
        // …avec modificateur, non (même logique exact-combo).
        let cw = KeybindScanner.ModScan(id: "cw.Mod", name: "CW", isActive: true,
                                        tree: tree(["Hotkey": .string("LeftShift + W")]))
        #expect(KeybindScanner.report(mods: [cw]).gameConflicts.isEmpty)
    }

    @Test func sameModDoesNotCollideWithItself() {
        let both = KeybindScanner.ModScan(id: "a.Mod1", name: "Mod 1", isActive: true,
                                          tree: tree(["Hotkey": .string("LeftControl + F8"),
                                                      "Other": .string("F8+LeftControl")]))
        #expect(KeybindScanner.report(mods: [both]).collisions.isEmpty)
    }

    @Test func reportIsDeterministicAndCounts() {
        let r1 = KeybindScanner.report(mods: [mod1])
        let r2 = KeybindScanner.report(mods: [mod1])
        #expect(r1 == r2)
        #expect(r1.scannedMods == 1)
        #expect(r1.keybindCount == 1)
    }

    // — Heuristique durcie (règle gelée, constat 2026-08-28)
    @Test func numericOriginIsNeverR2() {
        // Entier JSON, chaîne numérique, tableau d'entiers : jamais sans nom.
        if case .keybind = KeybindScanner.classify(leaf: .init(keyPath: ["Delai"], value: .number("100"))) {
            Issue.record("100 → NumPad4 : fantôme mesuré à 72 % de FP")
        }
        if case .keybind = KeybindScanner.classify(leaf: .init(keyPath: ["Quantite"], value: .string("50"))) {
            Issue.record("chaîne numérique : origine numérique quand même")
        }
        if case .keybind = KeybindScanner.classify(leaf: .init(keyPath: ["Liste"], value: .array([.number("20"), .number("100")]))) {
            Issue.record("tableau d'entiers : origine numérique quand même")
        }
        // Le cas réel mesuré : liste de CHAÎNES numériques (CollectionsMod).
        if case .keybind = KeybindScanner.classify(leaf: .init(keyPath: ["excludedWeaponIDs"], value: .array([.string("49"), .string("66")]))) {
            Issue.record("liste de chaînes numériques : origine numérique quand même (fantôme B mesuré)")
        }
    }

    @Test func hintedGarbageWithoutTokenIsNotKeybind() {
        // « Rusty Key » avec valeur "true" : nommé, illisible, sans jeton → rien.
        if case .unrecognized = KeybindScanner.classify(leaf: .init(keyPath: ["Rusty", "Key"], value: .string("true"))) {
            Issue.record("sans jeton reconnaissable, pas de unrecognized (90 % FP mesurés)")
        }
    }

    @Test func repeatedComboInOneValueYieldsOneUse() {
        // « F8, F8 » : le parseur rend deux combos identiques. Sans
        // déduplication, le même usage entre deux fois dans le seau et la
        // vue reçoit deux lignes de même identité (ForEach id: \.self).
        let a = KeybindScanner.ModScan(id: "a.Mod1", name: "Mod 1", isActive: true,
                                       tree: tree(["Hotkey": .string("F8, F8")]))
        let b = KeybindScanner.ModScan(id: "b.Mod2", name: "Mod 2", isActive: true,
                                       tree: tree(["Hotkey": .string("F8")]))
        let report = KeybindScanner.report(mods: [a, b])
        #expect(report.collisions.count == 1)
        #expect(report.collisions.first?.uses.count == 2)
        // Même dédup côté contrôles du jeu (F8 n'y est pas : on prend W).
        let w = KeybindScanner.ModScan(id: "c.Mod3", name: "Mod 3", isActive: true,
                                       tree: tree(["Hotkey": .string("W, W")]))
        let up = KeybindScanner.report(mods: [w]).gameConflicts
            .first { $0.control.name == "moveUpButton" }
        #expect(up?.uses.count == 1)
    }
}
