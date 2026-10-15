import Foundation
import Testing
@testable import StarHubTHCore

/// `apply` : gardes, sauvegarde d'abord, un fichier à la fois. Montage :
/// `KeybindPlanFixture`. Annulation : `KeybindPlanServiceUndoTests`.
@MainActor
@Suite struct KeybindPlanServiceTests {

    @Test func applyWritesLoserRescansAndBacksUp() async throws {
        let f = try KeybindPlanFixture.conflictPair()
        defer { f.cleanUp() }
        let swimBefore = try f.text("Swim")
        let plan = try f.readyPlan()
        let move = try #require(plan.moves.first)
        #expect(plan.moves.count == 1 && move.modID == "MailboxMenu")

        try await f.apply()

        let result = try #require(f.applied())
        #expect(result.written == 1)
        #expect(result.skipped.isEmpty)
        #expect(try f.value("MailboxMenu", "MenuKey") == move.to.display)
        #expect(try f.text("MailboxMenu").contains("\"Other\": 3"))
        #expect(try f.text("Swim") == swimBefore)
        #expect(f.box.rescans == 1)
        // Le lot ne contient que le mod touché, jamais tout le parc.
        let backups = f.backups.loadBackups()
        #expect(backups.count == 1)
        #expect(backups.first?.folderName == result.backupId)
        #expect(backups.first?.items.map(\.modFolderName) == ["MailboxMenu"])
    }

    @Test func gameRunningRefusesApplyButKeepsThePlan() async throws {
        let f = try KeybindPlanFixture.conflictPair()
        defer { f.cleanUp() }
        let before = try f.text("MailboxMenu")
        let plan = try f.readyPlan()
        f.box.running = true

        try await f.apply()

        #expect(f.service.refusal == .gameRunning)
        #expect(f.service.state == .ready(plan))
        #expect(try f.text("MailboxMenu") == before)
        #expect(f.backups.loadBackups().isEmpty)
        #expect(f.box.rescans == 0)
        // Jeu fermé : le même plan s'applique sans recalcul.
        f.box.running = false
        try await f.apply()
        #expect(f.service.refusal == nil)
        #expect(f.applied()?.written == 1)
    }

    @Test func stalePlanRefusesApply() async throws {
        let f = try KeybindPlanFixture.conflictPair()
        defer { f.cleanUp() }
        let before = try f.text("MailboxMenu")
        _ = try f.readyPlan()
        // Le parc a bougé entre le calcul et l'application.
        try Data(#"{"DiveKey": "K"}"#.utf8).write(to: f.config("Swim"))

        try await f.apply()

        #expect(f.service.state == .failed(.stalePlan))
        #expect(try f.text("MailboxMenu") == before)
        #expect(f.backups.loadBackups().isEmpty)
        #expect(f.box.rescans == 0)
    }

    @Test func backupFailureWritesNothing() async throws {
        // Le dossier des sauvegardes est un fichier : la création du lot échoue.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeybindPlanServiceTests-blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let f = try KeybindPlanFixture([("Swim", .action, #"{"DiveKey": "H"}"#),
                                        ("MailboxMenu", .info, #"{"MenuKey": "H"}"#)],
                                       backupsBase: blocker)
        defer { f.cleanUp() }
        let before = try f.text("MailboxMenu")
        _ = try f.readyPlan()

        try await f.apply()

        guard case .failed(.backupFailed) = f.service.state else {
            Issue.record("état attendu .failed(.backupFailed), obtenu \(f.service.state)"); return
        }
        #expect(try f.text("MailboxMenu") == before)
        #expect(f.box.rescans == 0)
    }

    @Test func corruptedFileIsSkippedAndNamed() async throws {
        let f = try KeybindPlanFixture.twoConflicts()
        defer { f.cleanUp() }
        let report = try f.report()
        let plan = try f.readyPlan()
        #expect(Set(plan.moves.map(\.modID)) == ["MailboxMenu", "LookupInfo"])
        let lookupMove = try #require(plan.moves.first { $0.modID == "LookupInfo" })
        // Corrompu entre le calcul et l'application.
        try Data("{ \"MenuKey\": ".utf8).write(to: f.config("MailboxMenu"))

        try await f.apply(report: report)

        let result = try #require(f.applied())
        #expect(result.written == 1)
        #expect(result.skipped == [PlanSkip(folderName: "MailboxMenu",
                                            reason: .writerFailed(.unreadable, keyPath: ["MenuKey"]))])
        #expect(try f.text("MailboxMenu") == "{ \"MenuKey\": ")
        #expect(try f.value("LookupInfo", "LookupKey") == lookupMove.to.display)
        #expect(f.box.rescans == 1)
    }

    @Test func nonUTF8FileIsUnreadableAndSkipped() async throws {
        let f = try KeybindPlanFixture.twoConflicts()
        defer { f.cleanUp() }
        let report = try f.report()
        _ = try f.readyPlan()
        let bytes = Data([0x7B, 0xFF, 0xFE, 0x7D])
        try bytes.write(to: f.config("MailboxMenu"))

        try await f.apply(report: report)

        let result = try #require(f.applied())
        #expect(result.skipped == [PlanSkip(folderName: "MailboxMenu", reason: .unreadable)])
        #expect(result.written == 1)
        #expect(try Data(contentsOf: f.config("MailboxMenu")) == bytes)
    }

    @Test func missingModIsSkippedAndNamed() async throws {
        let f = try KeybindPlanFixture.twoConflicts()
        defer { f.cleanUp() }
        _ = try f.readyPlan()
        let before = try f.text("LookupInfo")

        try await f.apply(mods: f.mods.filter { $0.folderName != "LookupInfo" })

        let result = try #require(f.applied())
        #expect(result.skipped == [PlanSkip(folderName: "LookupInfo", reason: .modNotFound)])
        #expect(result.written == 1)
        #expect(try f.text("LookupInfo") == before)
        #expect(f.backups.loadBackups().first?.items.map(\.modFolderName) == ["MailboxMenu"])
    }

    @Test func excludedMoveLeavesItsFileUntouched() async throws {
        let f = try KeybindPlanFixture.twoConflicts()
        defer { f.cleanUp() }
        let plan = try f.readyPlan()
        let excluded = try #require(plan.moves.first { $0.modID == "LookupInfo" })
        let before = try f.text("LookupInfo")

        try await f.apply(excluding: [excluded.id])

        let result = try #require(f.applied())
        #expect(result.written == 1 && result.skipped.isEmpty)
        #expect(try f.text("LookupInfo") == before)
        #expect(try f.text("MailboxMenu") != #"{"MenuKey": "H"}"#)
        #expect(f.backups.loadBackups().first?.items.map(\.modFolderName) == ["MailboxMenu"])
    }

    @Test func symlinkedModFolderWithoutBackupCopyIsNeverWritten() async throws {
        let f = try KeybindPlanFixture.twoConflicts()
        defer { f.cleanUp() }
        // LookupInfo vit ailleurs, `Mods/LookupInfo` n'est qu'un lien.
        let real = f.base.appendingPathComponent("Elsewhere/LookupInfo", isDirectory: true)
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let link = f.game.appendingPathComponent("Mods/LookupInfo")
        try FileManager.default.moveItem(at: link, to: real)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let before = try Data(contentsOf: real.appendingPathComponent("config.json"))
        _ = try f.readyPlan()

        try await f.apply()

        let result = try #require(f.applied())
        #expect(result.skipped == [PlanSkip(folderName: "LookupInfo", reason: .noBackupCopy)])
        #expect(result.written == 1)
        #expect(try Data(contentsOf: real.appendingPathComponent("config.json")) == before)
    }

    @Test func readOnlyModFolderIsOpenedWrittenThenRestored() async throws {
        let f = try KeybindPlanFixture.conflictPair()
        defer { f.cleanUp() }
        let move = try #require(try f.readyPlan().moves.first)
        let folder = f.config("MailboxMenu").deletingLastPathComponent().path
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)

        try await f.apply()

        let result = try #require(f.applied())
        #expect(result.written == 1 && result.skipped.isEmpty)
        #expect(try f.value("MailboxMenu", "MenuKey") == move.to.display)
        // Le mod reste comme son auteur l'a empaqueté.
        let mode = try FileManager.default.attributesOfItem(atPath: folder)[.posixPermissions] as? NSNumber
        #expect(mode?.uint16Value == 0o555)
    }

    @Test func pausedModIsSkippedAndNamed() async throws {
        let f = try KeybindPlanFixture.conflictPair()
        defer { f.cleanUp() }
        let report = try f.report()
        _ = try f.readyPlan()
        // Mis en pause entre le calcul et l'application : le dossier porte un point.
        try FileManager.default.moveItem(at: f.game.appendingPathComponent("Mods/MailboxMenu"),
                                         to: f.game.appendingPathComponent("Mods/.MailboxMenu"))
        let paused = f.game.appendingPathComponent("Mods/.MailboxMenu/config.json")
        let before = try String(contentsOf: paused, encoding: .utf8)

        try await f.apply(report: report, mods: [KeybindPlanFixture.mod("Swim"),
                                                 KeybindPlanFixture.mod("MailboxMenu", enabled: false)])

        let result = try #require(f.applied())
        #expect(result.written == 0)
        #expect(result.skipped == [PlanSkip(folderName: "MailboxMenu", reason: .paused)])
        #expect(try String(contentsOf: paused, encoding: .utf8) == before)
    }

    @Test func severalMovesOnOneSettingApplyOnTheEvolvingText() async throws {
        // MailboxMenu perd H contre Swim et J contre Fishing : deux
        // déplacements sur le même réglage, écrits l'un après l'autre.
        let f = try KeybindPlanFixture([("Swim", .action, #"{"DiveKey": "H"}"#),
                                        ("Fishing", .action, #"{"CastKey": "J"}"#),
                                        ("MailboxMenu", .info, #"{"MenuKey": "H, J"}"#)])
        defer { f.cleanUp() }
        let moves = try f.readyPlan().moves.filter { $0.modID == "MailboxMenu" }
        try #require(moves.count == 2 && Set(moves.map(\.keyPath)) == [["MenuKey"]])

        try await f.apply()

        #expect(f.applied()?.written == 1)
        let alternatives = try #require(try f.value("MailboxMenu", "MenuKey"))
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(Set(alternatives) == Set(moves.map(\.to.display)))
    }

    @Test func oneFailingMoveLeavesTheWholeFileIntact() async throws {
        // Deux réglages perdants dans le même fichier ; le second (ordre du
        // plan : ListKey puis MenuKey) n'a plus son alternative à l'application.
        let f = try KeybindPlanFixture([("Swim", .action, #"{"DiveKey": "H"}"#),
                                        ("Fishing", .action, #"{"CastKey": "J"}"#),
                                        ("MailboxMenu", .info, #"{"ListKey": "J", "MenuKey": "H"}"#)])
        defer { f.cleanUp() }
        let report = try f.report()
        let plan = try f.readyPlan()
        try #require(plan.moves.filter { $0.modID == "MailboxMenu" }.map(\.keyPath) == [["ListKey"], ["MenuKey"]])
        let changed = #"{"ListKey": "J", "MenuKey": "K"}"#
        try Data(changed.utf8).write(to: f.config("MailboxMenu"))

        try await f.apply(report: report)

        let result = try #require(f.applied())
        #expect(result.written == 0)
        #expect(result.skipped == [PlanSkip(folderName: "MailboxMenu",
                                            reason: .writerFailed(.alternativeMissing, keyPath: ["MenuKey"]))])
        #expect(try f.text("MailboxMenu") == changed)
    }

    // MARK: - Revue finale

    @Test func storedCorrectionBeatsTheGuess() async throws {
        // Deux mods devinés info : à égalité, le plus petit modID garde
        // (ZooInfo céderait). AlbumMenu corrigé en « rare » : c'est lui qui cède.
        let f = try KeybindPlanFixture([("AlbumMenu", .rare, #"{"MenuKey": "H"}"#),
                                        ("ZooInfo", .info, #"{"InfoKey": "H"}"#)])
        defer { f.cleanUp() }
        f.families.set(nil, for: "ZooInfo")
        let guessed = KeybindPlanService.guessedFamilies(try f.report())
        try #require(guessed["AlbumMenu"] == .info && guessed["ZooInfo"] == .info)

        let plan = try f.readyPlan()

        #expect(plan.moves.map(\.modID) == ["AlbumMenu"])
        #expect(plan.moves.first?.family == .rare)
    }

    @Test func secondApplyKeepsTheVerdict() async throws {
        // Double clic : le second « Appliquer » arrive sur `.applied` — il
        // ne doit ni remplacer le verdict par « aucun plan » ni réécrire.
        let f = try KeybindPlanFixture.conflictPair()
        defer { f.cleanUp() }
        _ = try f.readyPlan()
        try await f.apply()
        let first = try #require(f.applied())

        try await f.apply()

        #expect(f.service.state == .applied(first))
        #expect(f.service.refusal == nil)
        #expect(f.box.rescans == 1)
        #expect(f.backups.loadBackups().count == 1)
    }

    @Test func listElementsLendTheirSettingNameToTheGuess() throws {
        // `DumpKeys: [F5, F6]` s'aplatit en `DumpKeys.[0…1]` : la déduction
        // doit lire « DumpKeys » (rare), pas « [0] ».
        let f = try KeybindPlanFixture([("Gizmo", .action, #"{"DumpKeys": ["F5", "F6"]}"#)])
        defer { f.cleanUp() }
        #expect(KeybindPlanService.guessedFamilies(try f.report())["Gizmo"] == .rare)
    }
}
