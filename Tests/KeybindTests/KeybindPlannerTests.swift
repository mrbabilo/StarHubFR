import Testing
@testable import StarHubTHCore

struct KeybindPlannerTests {
    private func tree(_ pairs: [(String, String)]) -> ConfigJSONTree.Value {
        .object(ConfigJSONTree.Object(pairs.map { ($0.0, .string($0.1)) }))
    }
    private func scan(_ id: String, _ pairs: [(String, String)]) -> KeybindScanner.ModScan {
        .init(id: id, name: id, isActive: true, tree: tree(pairs))
    }
    private func report(_ mods: [KeybindScanner.ModScan]) -> KeybindScanner.KeybindReport {
        KeybindScanner.report(mods: mods, contexts: .empty,
                              gameControls: [.init(name: "action", buttons: ["E"])], gamepadOff: true)
    }

    @Test func infoLosesAgainstActionAndLandsOnADigit() throws {
        let r = report([scan("Swim", [("DiveKey", "H")]), scan("MailboxMenu", [("MenuKey", "H")])])
        let plan = KeybindPlanner.plan(report: r, families: ["Swim": .action, "MailboxMenu": .info],
                                       mode: .conflictsOnly, chordCapable: [])
        #expect(plan.moves.count == 1)
        let move = try #require(plan.moves.first)
        #expect(move.modID == "MailboxMenu")
        #expect(move.to.buttons.first?.hasPrefix("D") == true)   // chiffre, famille info
    }
    @Test func bothActionMeansDeterministicLoserNotCrash() throws {
        let r = report([scan("Alpha", [("UseKey", "H")]), scan("Beta", [("CastKey", "H")])])
        let plan = KeybindPlanner.plan(report: r, families: ["Alpha": .action, "Beta": .action],
                                       mode: .conflictsOnly, chordCapable: [])
        #expect(plan.moves.map(\.modID) == ["Beta"])   // lexicographiquement plus grand cède
    }
    @Test func unknownFamilyIsNeverMoved() throws {
        let r = report([scan("Swim", [("DiveKey", "H")]), scan("Mystery", [("MainKey", "H")])])
        let plan = KeybindPlanner.plan(report: r, families: ["Swim": .action],
                                       mode: .conflictsOnly, chordCapable: [])
        #expect(plan.moves.isEmpty)
        #expect(plan.unmovable.contains { $0.modID == "Mystery" && $0.reason == .noFamily })
    }
    @Test func authorBlockStaysIntact() throws {
        // Sorcery perdrait (info contre action) : seul le bloc le retient.
        let r = report([scan("Sorcery", [("Slot1", "D1"), ("Slot2", "D2"), ("Slot3", "D3")]),
                        scan("MailboxMenu", [("MenuKey", "D1")])])
        let plan = KeybindPlanner.plan(report: r, families: ["Sorcery": .info, "MailboxMenu": .action],
                                       mode: .conflictsOnly, chordCapable: [])
        #expect(!plan.moves.contains { $0.modID == "Sorcery" })
        #expect(plan.unmovable.contains { $0.modID == "Sorcery" && $0.reason == .authorBlock })
    }
    @Test func mnemonicPrefersModInitial() throws {
        // Un mod d'action posé sur une touche F n'est pas dans sa famille :
        // en rangement complet, il vise l'initiale de son nom (G), pas celle
        // du réglage (O).
        let r = report([scan("Gallery", [("OpenKey", "F5")])])
        let full = KeybindPlanner.plan(report: r, families: ["Gallery": .action],
                                       mode: .fullLayout, chordCapable: [])
        #expect(full.moves.contains { $0.modID == "Gallery" && $0.to.buttons == ["G"] })
        // Déjà dans sa famille : rien ne bouge.
        let settled = KeybindPlanner.plan(report: report([scan("Gallery", [("OpenKey", "K")])]),
                                          families: ["Gallery": .action], mode: .fullLayout, chordCapable: [])
        #expect(settled.moves.isEmpty)
    }
    @Test func familyFullOfSingleKeyHoldersProposesNoChord() throws {
        // 10 mods info sur les 10 chiffres + InfoX battu sur D0 : chaque base
        // de corde est tenue seule par un autre mod — `Ctrl + D0` ferait
        // aussi tirer D0 (SMAPI lit D0 dans Ctrl + D0), un co-déclenchement
        // que le rescan ne compterait pas comme conflit (R20). Non déplacé.
        var mods = (0...9).map { scan("Info\($0)", [("MenuKey", "D\($0)")]) }
        mods.append(scan("InfoX", [("ListKey", "D0")]))
        let r = report(mods)
        let families = Dictionary(uniqueKeysWithValues: mods.map { ($0.id, KeybindFamily.info) })
        let capable = KeybindPlanner.plan(report: r, families: families,
                                          mode: .conflictsOnly, chordCapable: ["InfoX/ListKey"])
        #expect(!capable.moves.contains { $0.modID == "InfoX" })
        #expect(capable.unmovable.contains { $0.modID == "InfoX" && $0.reason == .familyFull })
        let incapable = KeybindPlanner.plan(report: r, families: families,
                                            mode: .conflictsOnly, chordCapable: [])
        #expect(incapable.unmovable.contains { $0.modID == "InfoX" && $0.reason == .singleButtonFieldFull })
    }
    @Test func chordFallbackOnlyOnABaseNoOtherSettingHolds() throws {
        // InfoX « D0, D1 » battu sur D0 par Swim ; D2–D9 tenus seuls par
        // d'autres. Seule base libre : D1, que seul InfoX tient — la corde
        // va sur Ctrl + D1, jamais sur Ctrl + D0 (D0 reste à Swim).
        var mods = (2...9).map { scan("Info\($0)", [("MenuKey", "D\($0)")]) }
        mods.append(scan("Swim", [("DiveKey", "D0")]))
        mods.append(scan("InfoX", [("ListKey", "D0, D1")]))
        var families = Dictionary(uniqueKeysWithValues: mods.map { ($0.id, KeybindFamily.info) })
        families["Swim"] = .action
        let plan = KeybindPlanner.plan(report: report(mods), families: families,
                                       mode: .conflictsOnly, chordCapable: ["InfoX/ListKey"])
        let move = try #require(plan.moves.first { $0.modID == "InfoX" })
        #expect(move.from == KeybindCombo(buttons: ["D0"]))
        #expect(move.to == KeybindCombo(buttons: ["LeftControl", "D1"]))
    }
    @Test func chordBaseProposedAloneEarlierInThePlanIsNotFree() throws {
        // D0–D8 tenus ; InfoA (battu sur D5) prend D9, seul chiffre libre.
        // InfoB (battu sur D6) : famille pleine, et Ctrl + D9 ferait tirer
        // le D9 que le plan vient de donner à InfoA — non déplacé.
        var mods = (0...8).map { scan("Info\($0)", [("MenuKey", "D\($0)")]) }
        mods.append(scan("InfoA", [("ListKey", "D5")]))
        mods.append(scan("InfoB", [("ListKey", "D6")]))
        let families = Dictionary(uniqueKeysWithValues: mods.map { ($0.id, KeybindFamily.info) })
        let plan = KeybindPlanner.plan(report: report(mods), families: families, mode: .conflictsOnly,
                                       chordCapable: ["InfoA/ListKey", "InfoB/ListKey"])
        #expect(plan.moves.first { $0.modID == "InfoA" }?.to == KeybindCombo(buttons: ["D9"]))
        #expect(!plan.moves.contains { $0.modID == "InfoB" })
        #expect(plan.unmovable.contains { $0.modID == "InfoB" && $0.reason == .familyFull })
    }
    @Test func planNeverProposesTheSameComboTwiceAndIsDeterministic() throws {
        let r = report([scan("MenuA", [("MenuKey", "H")]), scan("MenuB", [("ListKey", "H")]),
                        scan("MenuC", [("MapKey", "H")])])
        let families: [String: KeybindFamily] = ["MenuA": .info, "MenuB": .info, "MenuC": .info]
        let one = KeybindPlanner.plan(report: r, families: families, mode: .conflictsOnly, chordCapable: [])
        let two = KeybindPlanner.plan(report: r, families: families, mode: .conflictsOnly, chordCapable: [])
        #expect(one == two)
        #expect(Set(one.moves.map(\.to)).count == one.moves.count)
    }
    @Test func gameControlKeysAreNeverProposed() throws {
        let r = report([scan("Swim", [("DiveKey", "H")]), scan("Mail", [("MenuKey", "H")])])
        let plan = KeybindPlanner.plan(report: r, families: ["Swim": .action, "Mail": .info],
                                       mode: .fullLayout, chordCapable: [])
        #expect(!plan.moves.contains { $0.to.buttons == ["E"] })   // E = contrôle du jeu de la fixture
    }
    @Test func familyPoolsAreCompleteAndRareLandsOnAnFKey() throws {
        // Un nom mal orthographié ferait échouer `KeybindCombo(buttons:)` en
        // silence et rétrécirait une famille : les trois pools sont entiers.
        #expect(KeybindPlanner.letters.compactMap { KeybindCombo(buttons: [$0]) }.count == 26)
        #expect(KeybindPlanner.digits.compactMap { KeybindCombo(buttons: [$0]) }.count == 10)
        #expect(KeybindPlanner.functionKeys.compactMap { KeybindCombo(buttons: [$0]) }.count == 12)
        let r = report([scan("Swim", [("DiveKey", "H")]), scan("DebugTool", [("DumpKey", "H")])])
        let plan = KeybindPlanner.plan(report: r, families: ["Swim": .action, "DebugTool": .rare],
                                       mode: .conflictsOnly, chordCapable: [])
        #expect(plan.moves.map(\.to.buttons) == [["F1"]])
        #expect(plan.moves.first?.reason == .conflictLoser(against: "Swim"))
    }
    @Test func listElementsAreNotAnAuthorBlock() throws {
        // `Keys: [A, B, C]` s'aplatit en `Keys.[0…2]` : une liste, pas un bloc.
        let tree = ConfigJSONTree.Value.object(ConfigJSONTree.Object([
            ("Keys", .array([.string("H"), .string("J"), .string("K")])),
        ]))
        let r = KeybindScanner.report(
            mods: [.init(id: "MenuList", name: "MenuList", isActive: true, tree: tree), scan("Swim", [("DiveKey", "H")])],
            contexts: .empty, gameControls: [.init(name: "action", buttons: ["E"])], gamepadOff: true)
        let plan = KeybindPlanner.plan(report: r, families: ["Swim": .action, "MenuList": .info],
                                       mode: .conflictsOnly, chordCapable: [])
        #expect(!plan.unmovable.contains { $0.reason == .authorBlock })
        #expect(plan.moves.contains { $0.modID == "MenuList" && $0.from.buttons == ["H"] })
    }
    @Test func gameControlKeyIsSkippedEvenWhenMnemonic() throws {
        // Eagle cède à Alpha ; son initiale E est un contrôle du jeu de la
        // fixture : le plan passe à l'initiale du réglage (C).
        let r = report([scan("Alpha", [("UseKey", "H")]), scan("Eagle", [("CastKey", "H")])])
        let plan = KeybindPlanner.plan(report: r, families: ["Alpha": .action, "Eagle": .action],
                                       mode: .conflictsOnly, chordCapable: [])
        #expect(plan.moves.map(\.to.buttons) == [["C"]])
    }

    // MARK: - Ronde de correction 1

    private func report(_ mods: [KeybindScanner.ModScan], contexts: KeybindContexts) -> KeybindScanner.KeybindReport {
        KeybindScanner.report(mods: mods, contexts: contexts,
                              gameControls: [.init(name: "action", buttons: ["E"])], gamepadOff: true)
    }

    @Test func eachLosingAlternativeGetsItsOwnMove() throws {
        // « H, J » perd sur H (Swim) et sur J (Jump) : deux déplacements,
        // deux cibles distinctes, aucun conflit résiduel muet.
        let r = report([scan("Swim", [("DiveKey", "H")]), scan("Jump", [("JumpKey", "J")]),
                        scan("MenuMod", [("MenuKey", "H, J")])])
        let plan = KeybindPlanner.plan(report: r, families: ["Swim": .action, "Jump": .action, "MenuMod": .info],
                                       mode: .conflictsOnly, chordCapable: [])
        let moves = plan.moves.filter { $0.modID == "MenuMod" }
        #expect(Set(moves.map(\.from.buttons)) == [["H"], ["J"]])
        #expect(Set(moves.map(\.to)).count == 2)
        #expect(Set(moves.map(\.id)).count == 2)
        #expect(plan.unmovable.isEmpty)
    }
    @Test func neverLandsOnItsOwnOtherAlternative() throws {
        // Kite « H, K » battu sur H : K (son initiale) est déjà son autre
        // alternative — « K, K » serait une suppression déguisée.
        let r = report([scan("Alpha", [("UseKey", "H")]), scan("Kite", [("FlyKey", "H, K")])])
        let plan = KeybindPlanner.plan(report: r, families: ["Alpha": .action, "Kite": .action],
                                       mode: .conflictsOnly, chordCapable: [])
        let move = try #require(plan.moves.first { $0.modID == "Kite" })
        #expect(move.from.buttons == ["H"])
        #expect(move.to.buttons != ["K"])
        #expect(move.to.buttons != ["H"])
    }
    @Test func fullLayoutNeverMovesASettingOntoItself() throws {
        // Chiffres pleins, InfoX déjà sur une corde de sa famille : rien de
        // mieux à proposer — pas de déplacement vers lui-même ni d'une corde
        // vers une autre.
        var mods = (0...9).map { scan("Info\($0)", [("MenuKey", "D\($0)")]) }
        mods.append(scan("InfoX", [("ListKey", "LeftControl + D0")]))
        let families = Dictionary(uniqueKeysWithValues: mods.map { ($0.id, KeybindFamily.info) })
        let plan = KeybindPlanner.plan(report: report(mods), families: families,
                                       mode: .fullLayout, chordCapable: ["InfoX/ListKey"])
        #expect(!plan.moves.contains { $0.from == $0.to })
        #expect(!plan.moves.contains { $0.modID == "InfoX" })
    }
    @Test func remapModIsNeverMoved() throws {
        let remap = KeybindScanner.ModScan(id: "GCSR", name: "GCSR", isActive: true,
                                           tree: tree([("SwapKey", "H")]),
                                           uniqueId: "fawazt.GlobalConfigSettingsRewrite")
        let r = report([scan("Swim", [("DiveKey", "H")]), remap])
        let plan = KeybindPlanner.plan(report: r, families: ["Swim": .action, "GCSR": .info],
                                       mode: .conflictsOnly, chordCapable: [])
        #expect(plan.moves.isEmpty)
        #expect(plan.unmovable.contains { $0.modID == "GCSR" && $0.reason == .remapMod })
    }
    @Test func declaredHeldSettingIsNeverMoved() throws {
        let contexts = KeybindContexts(rules: ["Tip": [.init(keyPaths: ["ShowKey"], held: true)]])
        let r = report([scan("Swim", [("DiveKey", "H")]), scan("Tip", [("ShowKey", "H")])], contexts: contexts)
        let plan = KeybindPlanner.plan(report: r, families: ["Swim": .action, "Tip": .info],
                                       mode: .conflictsOnly, chordCapable: [])
        #expect(plan.moves.isEmpty)
        #expect(plan.unmovable.contains { $0.modID == "Tip" && $0.reason == .heldModifier })
    }
    @Test func requiresChordedSettingIsNeverMoved() throws {
        // SpellKey n'agit qu'en maintenant CastKey : sa combinaison jugée
        // porte LeftAlt, absent du champ — `from` ne serait pas ce qu'il contient.
        let contexts = KeybindContexts(rules: ["Wiz": [.init(keyPaths: ["SpellKey"], requires: "CastKey")]])
        let r = report([scan("Wiz", [("CastKey", "LeftAlt"), ("SpellKey", "H")])], contexts: contexts)
        let plan = KeybindPlanner.plan(report: r, families: ["Wiz": .action],
                                       mode: .fullLayout, chordCapable: [])
        #expect(!plan.moves.contains { $0.keyPath == ["SpellKey"] })
        #expect(plan.unmovable.contains { $0.keyPath == ["SpellKey"] && $0.reason == .heldModifier })
    }
    @Test func inertSettingIsNeverMoved() throws {
        let contexts = KeybindContexts(rules: ["Mail": [.init(keyPaths: ["MenuKey"], enabledBy: "MenuOnMailbox")]])
        let r = report([scan("Mail", [("MenuKey", "F5"), ("MenuOnMailbox", "false")])], contexts: contexts)
        let plan = KeybindPlanner.plan(report: r, families: ["Mail": .action],
                                       mode: .fullLayout, chordCapable: [])
        #expect(plan.moves.isEmpty)
        #expect(plan.unmovable.contains { $0.modID == "Mail" && $0.reason == .inert })
    }
    @Test func contextResolvedSettingIsNeverMoved() throws {
        let contexts = KeybindContexts(rules: ["Cal": [.init(keyPaths: ["OpenKey"], context: .ownMenu)]])
        let r = report([scan("Cal", [("OpenKey", "F5")])], contexts: contexts)
        let plan = KeybindPlanner.plan(report: r, families: ["Cal": .action],
                                       mode: .fullLayout, chordCapable: [])
        #expect(plan.moves.isEmpty)
        #expect(plan.unmovable.contains { $0.modID == "Cal" && $0.reason == .contextResolved })
    }
}
