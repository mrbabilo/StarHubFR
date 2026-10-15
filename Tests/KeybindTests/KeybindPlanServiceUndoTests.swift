import Foundation
import Testing
@testable import StarHubTHCore

/// `undo` : ne rend que le `config.json` écrit par le plan, et seulement s'il
/// porte encore ce que le plan a écrit. Montage : `KeybindPlanFixture`.
@MainActor
@Suite struct KeybindPlanServiceUndoTests {

    @Test func undoRestoresBytes() async throws {
        let f = try KeybindPlanFixture.conflictPair()
        defer { f.cleanUp() }
        let before = try f.text("MailboxMenu")
        let i18n = f.config("MailboxMenu").deletingLastPathComponent().appendingPathComponent("i18n")
        try FileManager.default.createDirectory(at: i18n, withIntermediateDirectories: true)
        try Data(#"{"title": "avant"}"#.utf8).write(to: i18n.appendingPathComponent("fr.json"))
        _ = try f.readyPlan()
        try await f.apply()
        #expect(try f.text("MailboxMenu") != before)
        #expect(f.service.canUndo)
        // Traduction retouchée après le plan : l'annulation n'y touche pas.
        try Data(#"{"title": "après"}"#.utf8).write(to: i18n.appendingPathComponent("fr.json"))

        await f.undo()

        #expect(f.service.state == .undone(.init(restored: 1, skipped: [])))
        #expect(try f.text("MailboxMenu") == before)
        #expect(try String(contentsOf: i18n.appendingPathComponent("fr.json"), encoding: .utf8)
                == #"{"title": "après"}"#)
        #expect(f.box.rescans == 2)
        // La restauration pose son propre filet : le lot du plan n'est plus
        // le dernier, et il n'y a plus rien à annuler.
        #expect(!f.service.canUndo)
        await f.undo()
        #expect(f.service.state == .failed(.nothingToUndo))
        #expect(f.box.rescans == 2)
    }

    @Test func undoRefusedWhenAnotherBackupCameAfter() async throws {
        let f = try KeybindPlanFixture.conflictPair()
        defer { f.cleanUp() }
        _ = try f.readyPlan()
        try await f.apply()
        let applied = try f.text("MailboxMenu")
        _ = try f.backups.createBackup(gameDir: f.game.path, mods: f.mods, onlyEnabled: false)

        await f.undo()

        #expect(f.service.state == .failed(.notLatestBackup))
        #expect(try f.text("MailboxMenu") == applied)
        #expect(f.box.rescans == 1)
    }

    @Test func gameRunningRefusesUndoButKeepsIt() async throws {
        let f = try KeybindPlanFixture.conflictPair()
        defer { f.cleanUp() }
        let before = try f.text("MailboxMenu")
        _ = try f.readyPlan()
        try await f.apply()
        f.box.running = true

        await f.undo()

        #expect(f.service.refusal == .gameRunning)
        #expect(f.applied() != nil)
        #expect(f.service.canUndo)
        f.box.running = false
        await f.undo()
        #expect(try f.text("MailboxMenu") == before)
    }

    @Test func undoKeepsAnEditMadeAfterThePlan() async throws {
        let f = try KeybindPlanFixture.twoConflicts()
        defer { f.cleanUp() }
        let lookupBefore = try f.text("LookupInfo")
        _ = try f.readyPlan()
        try await f.apply()
        // Édition après le plan, avec le filet de l'éditeur : le lot du jour
        // protège déjà config.json, aucun nouveau lot — celui du plan reste
        // le dernier.
        let edited = #"{"MenuKey": "F9"}"#
        try Data(edited.utf8).write(to: f.config("MailboxMenu"))
        let newLot = try f.backups.backUpConfigOncePerDay(for: KeybindPlanFixture.mod("MailboxMenu"),
                                                          gameDir: f.game.path)
        try #require(!newLot && f.service.canUndo)

        await f.undo()

        #expect(f.service.state == .undone(.init(
            restored: 1, skipped: [PlanSkip(folderName: "MailboxMenu", reason: .changedSinceApply)])))
        #expect(try f.text("MailboxMenu") == edited)
        #expect(try f.text("LookupInfo") == lookupBefore)
    }

    @Test func skippedModIsLeftUntouchedByUndo() async throws {
        let f = try KeybindPlanFixture.twoConflicts()
        defer { f.cleanUp() }
        let report = try f.report()
        let lookupBefore = try f.text("LookupInfo")
        _ = try f.readyPlan()
        try Data("{ \"MenuKey\": ".utf8).write(to: f.config("MailboxMenu"))
        try await f.apply(report: report)
        #expect(f.applied()?.skipped.map(\.folderName) == ["MailboxMenu"])
        // Le mod sauté est réparé à la main après le plan.
        let repaired = #"{"MenuKey": "H", "Fixed": true}"#
        try Data(repaired.utf8).write(to: f.config("MailboxMenu"))

        await f.undo()

        #expect(f.service.state == .undone(.init(restored: 1, skipped: [])))
        #expect(try f.text("MailboxMenu") == repaired)
        #expect(try f.text("LookupInfo") == lookupBefore)
    }
}
