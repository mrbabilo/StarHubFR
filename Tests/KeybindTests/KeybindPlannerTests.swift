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
    @Test func familyFullFallsBackToChordOnlyWhenCapable() throws {
        // 10 mods info sur 10 chiffres pleins + 1 en conflit : repli corde
        // pour le réglage qui la supporte, sinon non déplacé.
        var mods = (0...9).map { scan("Info\($0)", [("MenuKey", "D\($0)")]) }
        mods.append(scan("InfoX", [("ListKey", "D0")]))
        let r = report(mods)
        let families = Dictionary(uniqueKeysWithValues: mods.map { ($0.id, KeybindFamily.info) })
        let capable = KeybindPlanner.plan(report: r, families: families,
                                          mode: .conflictsOnly, chordCapable: ["InfoX/ListKey"])
        #expect(capable.moves.contains { $0.modID == "InfoX" && $0.to.buttons.count == 2 })
        let incapable = KeybindPlanner.plan(report: r, families: families,
                                            mode: .conflictsOnly, chordCapable: [])
        #expect(incapable.unmovable.contains { $0.modID == "InfoX" && $0.reason == .singleButtonFieldFull })
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
}
