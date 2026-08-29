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

    // — R4 : le catalogue (constat utilisateur, tâche 6, ModShortcutReferenceHub)
    private let letterTokens = (0..<26).map { String(UnicodeScalar(65 + $0)!) }
    private let digitTokens = (0..<10).map { "D\($0)" }
    private let fnTokens = (1...12).map { "F\($0)" }
    private var catalogTokens: [String] { letterTokens + digitTokens + fnTokens }

    private func shortcutsCatalog(_ tokens: some Collection<String>) -> ConfigJSONTree.Value {
        .array(tokens.map { .object(ConfigJSONTree.Object([("KeyCombo", .string($0))])) })
    }

    @Test func catalogFormIsExcludedButNeighborFieldSurvives() {
        // 42 KeyCombo distincts sous Shortcuts.[].KeyCombo (mesure réelle) +
        // un OpenMenuKey isolé, forme distincte à 1 combo : il reste une
        // liaison et doit collisionner avec Swim.
        let hub = KeybindScanner.ModScan(
            id: "z.Hub", name: "ModShortcutReferenceHub", isActive: true,
            tree: tree(["Shortcuts": shortcutsCatalog(catalogTokens.prefix(42)),
                        "OpenMenuKey": .string("K")]))
        let swim = KeybindScanner.ModScan(id: "s.Swim", name: "Swim", isActive: true,
                                          tree: tree(["DiveKey": .string("K")]))
        let r = KeybindScanner.report(mods: [hub, swim])
        #expect(r.collisions.count == 1)
        #expect(r.collisions.first?.combo.buttons == ["K"])
        #expect(r.collisions.first?.uses.map(\.modID).sorted() == ["s.Swim", "z.Hub"])
        #expect(r.catalogModsIgnored == ["ModShortcutReferenceHub"])
    }

    @Test func catalogThresholdIsEightStaysNineFalls() {
        let eight = KeybindScanner.ModScan(
            id: "e.Mod", name: "Eight", isActive: true,
            tree: tree(["Shortcuts": shortcutsCatalog(catalogTokens.prefix(8))]))
        let nine = KeybindScanner.ModScan(
            id: "n.Mod", name: "Nine", isActive: true,
            tree: tree(["Shortcuts": shortcutsCatalog(catalogTokens.prefix(9))]))
        let other = KeybindScanner.ModScan(id: "o.Mod", name: "Other", isActive: true,
                                           tree: tree(["Hotkey": .string("A")]))
        let atEight = KeybindScanner.report(mods: [eight, other])
        #expect(atEight.collisions.contains { $0.combo.buttons == ["A"] })
        #expect(atEight.catalogModsIgnored.isEmpty)

        let atNine = KeybindScanner.report(mods: [nine, other])
        #expect(!atNine.collisions.contains { $0.combo.buttons == ["A"] })
        #expect(atNine.catalogModsIgnored == ["Nine"])
    }

    @Test func twoModsWithFewDistinctKeysEachNeverTriggerTheCatalogRule() {
        // La règle compte par mod, pas en cumulant deux mods sous la même
        // forme de chemin : 5 + 5 ne doit jamais valoir 10 > 8.
        let modX = KeybindScanner.ModScan(
            id: "x.Mod", name: "ModX", isActive: true,
            tree: tree(["Shortcuts": shortcutsCatalog(Array(catalogTokens.prefix(5)))]))
        let modY = KeybindScanner.ModScan(
            id: "y.Mod", name: "ModY", isActive: true,
            tree: tree(["Shortcuts": shortcutsCatalog(Array(catalogTokens[5..<10]))]))
        let other = KeybindScanner.ModScan(id: "o.Mod", name: "Other", isActive: true,
                                           tree: tree(["Hotkey": .string(catalogTokens[0])]))
        let r = KeybindScanner.report(mods: [modX, modY, other])
        #expect(r.catalogModsIgnored.isEmpty)
        #expect(r.collisions.contains { $0.combo.buttons == [catalogTokens[0]] })
    }

    // — Ronde de correction 1 sur R4

    @Test func repeatedIdenticalComboUnderAShapeNeverTriggersTheCatalogRule() {
        // Constat 4a : occurrences ≠ valeurs distinctes. 12 fois la même
        // lettre sous une forme ne vaut qu'un seul combo distinct, loin du
        // seuil.
        let items = (0..<12).map { _ in
            ConfigJSONTree.Value.object(ConfigJSONTree.Object([("KeyCombo", .string("A"))]))
        }
        let mod = KeybindScanner.ModScan(id: "m.Mod", name: "Mod", isActive: true,
                                         tree: tree(["Shortcuts": .array(items)]))
        let other = KeybindScanner.ModScan(id: "o.Mod", name: "Other", isActive: true,
                                           tree: tree(["Hotkey": .string("A")]))
        let r = KeybindScanner.report(mods: [mod, other])
        #expect(r.catalogModsIgnored.isEmpty)
        #expect(r.collisions.contains { $0.combo.buttons == ["A"] })
    }

    @Test func differentTrailingFieldsUnderTheSameArrayNeverCumulate() {
        // Constat 4b : Shortcuts.[].KeyCombo et Shortcuts.[].AltCombo sont
        // deux formes distinctes — leurs combos ne se cumulent jamais dans
        // un même compte.
        let items = (0..<5).map { i in
            ConfigJSONTree.Value.object(ConfigJSONTree.Object([
                ("KeyCombo", .string(catalogTokens[i])),
                ("AltCombo", .string(catalogTokens[i + 5])),
            ]))
        }
        let mod = KeybindScanner.ModScan(id: "m.Mod", name: "Mod", isActive: true,
                                         tree: tree(["Shortcuts": .array(items)]))
        let other = KeybindScanner.ModScan(id: "o.Mod", name: "Other", isActive: true,
                                           tree: tree(["Hotkey": .string(catalogTokens[0])]))
        let r = KeybindScanner.report(mods: [mod, other])
        #expect(r.catalogModsIgnored.isEmpty)
        #expect(r.collisions.contains { $0.combo.buttons == [catalogTokens[0]] })
    }

    @Test func unrecognizedLeavesUnderACatalogShapeAreExcludedToo() {
        // Constat 3 : une entrée du catalogue qui ne parse pas ne doit pas
        // polluer « non reconnus » — le mod est déjà déclaré écarté sous
        // cette forme.
        var items: [ConfigJSONTree.Value] = catalogTokens.prefix(9).map {
            .object(ConfigJSONTree.Object([("KeyCombo", .string($0))]))
        }
        items.append(.object(ConfigJSONTree.Object([("KeyCombo", .string("ctrl+H"))])))
        let mod = KeybindScanner.ModScan(id: "m.Mod", name: "Mod", isActive: true,
                                         tree: tree(["Shortcuts": .array(items)]))
        let r = KeybindScanner.report(mods: [mod])
        #expect(r.unrecognized.isEmpty)
        #expect(r.catalogModsIgnored == ["Mod"])
    }

    @Test func catalogModsIgnoredKeepsBothHomonymsSeparate() {
        // Constat 2 : deux mods de même nom (le parc réel a Swim installé
        // deux fois), tous deux catalogues sous leur propre id, doivent
        // apparaître deux fois — dédupliquer sur le nom en effacerait un.
        let a = KeybindScanner.ModScan(
            id: "a.Swim", name: "Swim", isActive: true,
            tree: tree(["Shortcuts": shortcutsCatalog(catalogTokens.prefix(9))]))
        let b = KeybindScanner.ModScan(
            id: "b.Swim", name: "Swim", isActive: true,
            tree: tree(["Shortcuts": shortcutsCatalog(catalogTokens[9..<18])]))
        let r = KeybindScanner.report(mods: [a, b])
        #expect(r.catalogModsIgnored == ["Swim", "Swim"])
    }

    // — Défaut 2 : un mod par ligne, chemins réunis (regroupement, en Core)
    @Test func groupedUsesMergesSameModDistinctPathsButKeepsDistinctModsSeparate() {
        let uses = [
            KeybindScanner.ModUse(modID: "a.Hub", modName: "Hub",
                                  keyPath: ["Shortcuts", "[7]", "KeyCombo"]),
            KeybindScanner.ModUse(modID: "b.Swim", modName: "Swim", keyPath: ["DiveKey"]),
            KeybindScanner.ModUse(modID: "a.Hub", modName: "Hub", keyPath: ["OpenMenuKey"]),
        ]
        let grouped = KeybindScanner.groupedUses(uses)
        #expect(grouped.count == 2)
        #expect(grouped[0].modID == "a.Hub")
        #expect(grouped[0].keyPaths == [["Shortcuts", "[7]", "KeyCombo"], ["OpenMenuKey"]])
        #expect(grouped[1].modID == "b.Swim")
        #expect(grouped[1].keyPaths == [["DiveKey"]])
    }
}
