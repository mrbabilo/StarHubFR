import Foundation
import Testing
@testable import StarHubTHCore

/// Le service écrit de vrais `config.json` : tout vit dans un dossier
/// temporaire (faux `Mods/`, sauvegardes, magasin des familles) — jamais le
/// vrai Application Support ni le vrai parc.
@MainActor
@Suite struct KeybindPlanServiceTests {
    final class Box: @unchecked Sendable {
        var running = false
        var rescans = 0
    }

    private struct Fixture {
        let base: URL
        let game: URL
        let backups: ModConfigBackupManager
        let families: KeybindFamilyStore
        let mods: [ModItem]
        let box: Box
        let service: KeybindPlanService

        func config(_ folder: String) -> URL {
            game.appendingPathComponent("Mods/\(folder)/config.json")
        }
        func text(_ folder: String) throws -> String {
            try String(contentsOf: config(folder), encoding: .utf8)
        }
        /// Le rapport tel que le scanner le rendrait sur le disque actuel.
        func report() throws -> KeybindScanner.KeybindReport {
            let scans = try mods.map { mod -> KeybindScanner.ModScan in
                let tree = ConfigJSONTree.parse(try text(mod.folderName)) ?? .object(ConfigJSONTree.Object([]))
                return .init(id: mod.folderName, name: mod.name, isActive: true, tree: tree)
            }
            return KeybindScanner.report(mods: scans, contexts: .empty,
                                         gameControls: [.init(name: "action", buttons: ["E"])],
                                         gamepadOff: true)
        }
        func cleanUp() {
            // Un dossier 0555 empêcherait la suppression de son contenu.
            if let walker = FileManager.default.enumerator(atPath: base.path) {
                for case let relative as String in walker {
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: 0o755],
                        ofItemAtPath: base.appendingPathComponent(relative).path)
                }
            }
            try? FileManager.default.removeItem(at: base)
        }
    }

    /// `configs` : dossier → (famille corrigée, texte de `config.json`).
    /// Les familles passent par le magasin : le test ne dépend pas des
    /// listes de mots-clés de la déduction.
    private func fixture(_ configs: [(String, KeybindFamily, String)],
                         backupsBase: URL? = nil) throws -> Fixture {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeybindPlanServiceTests-\(UUID().uuidString)", isDirectory: true)
        let game = base.appendingPathComponent("Game", isDirectory: true)
        let support = base.appendingPathComponent("Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        var mods: [ModItem] = []
        let families = KeybindFamilyStore(directory: support)
        for (folder, family, text) in configs {
            let dir = game.appendingPathComponent("Mods/\(folder)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: dir.appendingPathComponent("config.json"))
            mods.append(ModItem(uniqueId: "test.\(folder)", name: folder, folderName: folder,
                                version: "1.0.0", author: "", description: "", nexusUrl: "",
                                nexusModId: "", isEnabled: true, dependencies: [],
                                hasConfigFile: true))
            families.set(family, for: folder)
        }
        let backups = ModConfigBackupManager(
            backupsBasePath: backupsBase ?? base.appendingPathComponent("Backups", isDirectory: true))
        let box = Box()
        let service = KeybindPlanService(backupManager: backups, isGameRunning: { box.running })
        return Fixture(base: base, game: game, backups: backups, families: families,
                       mods: mods, box: box, service: service)
    }

    /// Swim (action) et MailboxMenu (info) sur H : l'info cède.
    private func conflictPair() throws -> Fixture {
        try fixture([("Swim", .action, "{\n  \"DiveKey\": \"H\"\n}"),
                     ("MailboxMenu", .info, "{\n  \"MenuKey\": \"H\",\n  \"Other\": 3\n}")])
    }

    private func readyPlan(_ f: Fixture) throws -> KeybindPlan {
        f.service.compute(report: try f.report(), mods: f.mods, familyStore: f.families, mode: .conflictsOnly)
        guard case .ready(let plan) = f.service.state else {
            Issue.record("état attendu .ready, obtenu \(f.service.state)")
            throw CancellationError()
        }
        return plan
    }

    private func value(_ f: Fixture, _ folder: String, _ key: String) throws -> String? {
        guard case .object(let object) = try #require(ConfigJSONTree.parse(try f.text(folder))),
              case .string(let raw)? = object.members[key] else { return nil }
        return raw
    }

    @Test func applyWritesLoserRescansAndBacksUp() async throws {
        let f = try conflictPair()
        defer { f.cleanUp() }
        let swimBefore = try f.text("Swim")
        let plan = try readyPlan(f)
        let move = try #require(plan.moves.first)
        #expect(plan.moves.count == 1 && move.modID == "MailboxMenu")

        await f.service.apply(report: try f.report(), gameDir: f.game.path, mods: f.mods,
                              rescan: { f.box.rescans += 1 })

        guard case .applied(let result) = f.service.state else {
            Issue.record("état attendu .applied, obtenu \(f.service.state)"); return
        }
        #expect(result.written == 1)
        #expect(result.skipped.isEmpty)
        #expect(try value(f, "MailboxMenu", "MenuKey") == move.to.display)
        #expect(try f.text("MailboxMenu").contains("\"Other\": 3"))
        #expect(try f.text("Swim") == swimBefore)
        #expect(f.box.rescans == 1)
        // Le lot ne contient que le mod touché, jamais tout le parc.
        let backups = f.backups.loadBackups()
        #expect(backups.count == 1)
        #expect(backups.first?.folderName == result.backupId)
        #expect(backups.first?.items.map(\.modFolderName) == ["MailboxMenu"])
    }

    @Test func gameRunningRefusesApply() async throws {
        let f = try conflictPair()
        defer { f.cleanUp() }
        let before = try f.text("MailboxMenu")
        _ = try readyPlan(f)
        f.box.running = true

        await f.service.apply(report: try f.report(), gameDir: f.game.path, mods: f.mods,
                              rescan: { f.box.rescans += 1 })

        guard case .failed = f.service.state else {
            Issue.record("état attendu .failed, obtenu \(f.service.state)"); return
        }
        #expect(try f.text("MailboxMenu") == before)
        #expect(f.backups.loadBackups().isEmpty)
        #expect(f.box.rescans == 0)
    }

    @Test func unreadableFileIsSkippedAndNamed() async throws {
        // Deux conflits indépendants : MailboxMenu et LookupInfo perdent.
        let f = try fixture([("Swim", .action, #"{"DiveKey": "H"}"#),
                             ("MailboxMenu", .info, #"{"MenuKey": "H"}"#),
                             ("Fishing", .action, #"{"CastKey": "J"}"#),
                             ("LookupInfo", .info, #"{"LookupKey": "J"}"#)])
        defer { f.cleanUp() }
        let report = try f.report()
        let plan = try readyPlan(f)
        #expect(Set(plan.moves.map(\.modID)) == ["MailboxMenu", "LookupInfo"])
        let lookupMove = try #require(plan.moves.first { $0.modID == "LookupInfo" })
        // Corrompu entre le calcul et l'application.
        try Data("{ \"MenuKey\": ".utf8).write(to: f.config("MailboxMenu"))

        await f.service.apply(report: report, gameDir: f.game.path, mods: f.mods,
                              rescan: { f.box.rescans += 1 })

        guard case .applied(let result) = f.service.state else {
            Issue.record("état attendu .applied, obtenu \(f.service.state)"); return
        }
        #expect(result.written == 1)
        #expect(result.skipped.count == 1)
        #expect(result.skipped.first?.contains("MailboxMenu") == true)
        #expect(try f.text("MailboxMenu") == "{ \"MenuKey\": ")
        #expect(try value(f, "LookupInfo", "LookupKey") == lookupMove.to.display)
        #expect(f.box.rescans == 1)
    }

    @Test func stalePlanRefusesApply() async throws {
        let f = try conflictPair()
        defer { f.cleanUp() }
        let before = try f.text("MailboxMenu")
        _ = try readyPlan(f)
        // Le parc a bougé entre le calcul et l'application.
        try Data(#"{"DiveKey": "K"}"#.utf8).write(to: f.config("Swim"))

        await f.service.apply(report: try f.report(), gameDir: f.game.path, mods: f.mods,
                              rescan: { f.box.rescans += 1 })

        #expect(f.service.state == .failed("plan périmé, recalculer"))
        #expect(try f.text("MailboxMenu") == before)
        #expect(f.backups.loadBackups().isEmpty)
        #expect(f.box.rescans == 0)
    }

    @Test func undoRestoresBytes() async throws {
        let f = try conflictPair()
        defer { f.cleanUp() }
        let before = try f.text("MailboxMenu")
        let i18n = f.config("MailboxMenu").deletingLastPathComponent().appendingPathComponent("i18n")
        try FileManager.default.createDirectory(at: i18n, withIntermediateDirectories: true)
        try Data(#"{"title": "avant"}"#.utf8).write(to: i18n.appendingPathComponent("fr.json"))
        _ = try readyPlan(f)
        await f.service.apply(report: try f.report(), gameDir: f.game.path, mods: f.mods,
                              rescan: { f.box.rescans += 1 })
        #expect(try f.text("MailboxMenu") != before)
        // Traduction retouchée après le plan : l'annulation n'y touche pas.
        try Data(#"{"title": "après"}"#.utf8).write(to: i18n.appendingPathComponent("fr.json"))

        await f.service.undo(gameDir: f.game.path, mods: f.mods, rescan: { f.box.rescans += 1 })

        #expect(try f.text("MailboxMenu") == before)
        #expect(try String(contentsOf: i18n.appendingPathComponent("fr.json"), encoding: .utf8)
                == #"{"title": "après"}"#)
        #expect(f.box.rescans == 2)
        guard case .idle = f.service.state else {
            Issue.record("état attendu .idle après annulation, obtenu \(f.service.state)"); return
        }
        // La restauration pose son propre filet : le lot du plan n'est plus
        // le dernier, une seconde annulation est refusée.
        await f.service.undo(gameDir: f.game.path, mods: f.mods, rescan: { f.box.rescans += 1 })
        guard case .failed = f.service.state else {
            Issue.record("seconde annulation attendue en échec, obtenu \(f.service.state)"); return
        }
        #expect(f.box.rescans == 2)
    }

    @Test func undoRefusedWhenAnotherBackupCameAfter() async throws {
        let f = try conflictPair()
        defer { f.cleanUp() }
        _ = try readyPlan(f)
        await f.service.apply(report: try f.report(), gameDir: f.game.path, mods: f.mods,
                              rescan: { f.box.rescans += 1 })
        let applied = try f.text("MailboxMenu")
        _ = try f.backups.createBackup(gameDir: f.game.path, mods: f.mods, onlyEnabled: false)

        await f.service.undo(gameDir: f.game.path, mods: f.mods, rescan: { f.box.rescans += 1 })

        guard case .failed = f.service.state else {
            Issue.record("état attendu .failed, obtenu \(f.service.state)"); return
        }
        #expect(try f.text("MailboxMenu") == applied)
        #expect(f.box.rescans == 1)
    }

    @Test func backupFailureWritesNothing() async throws {
        // Le dossier des sauvegardes est un fichier : la création du lot échoue.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeybindPlanServiceTests-blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let f = try fixture([("Swim", .action, #"{"DiveKey": "H"}"#),
                             ("MailboxMenu", .info, #"{"MenuKey": "H"}"#)],
                            backupsBase: blocker)
        defer { f.cleanUp() }
        let before = try f.text("MailboxMenu")
        _ = try readyPlan(f)

        await f.service.apply(report: try f.report(), gameDir: f.game.path, mods: f.mods,
                              rescan: { f.box.rescans += 1 })

        guard case .failed = f.service.state else {
            Issue.record("état attendu .failed, obtenu \(f.service.state)"); return
        }
        #expect(try f.text("MailboxMenu") == before)
        #expect(f.box.rescans == 0)
    }

    @Test func readOnlyModFolderIsChmodedThenWritten() async throws {
        let f = try conflictPair()
        defer { f.cleanUp() }
        let plan = try readyPlan(f)
        let move = try #require(plan.moves.first)
        let folder = f.config("MailboxMenu").deletingLastPathComponent().path
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)

        await f.service.apply(report: try f.report(), gameDir: f.game.path, mods: f.mods,
                              rescan: { f.box.rescans += 1 })

        guard case .applied(let result) = f.service.state else {
            Issue.record("état attendu .applied, obtenu \(f.service.state)"); return
        }
        #expect(result.written == 1)
        #expect(result.skipped.isEmpty)
        #expect(try value(f, "MailboxMenu", "MenuKey") == move.to.display)
    }

    @Test func pausedModIsSkippedAndNamed() async throws {
        let f = try conflictPair()
        defer { f.cleanUp() }
        let report = try f.report()
        _ = try readyPlan(f)
        // Mis en pause entre le calcul et l'application : le dossier porte un point.
        let mods = Dictionary(uniqueKeysWithValues: f.mods.map { ($0.folderName, $0) })
        var mailbox = try #require(mods["MailboxMenu"])
        mailbox.isEnabled = false
        try FileManager.default.moveItem(at: f.game.appendingPathComponent("Mods/MailboxMenu"),
                                         to: f.game.appendingPathComponent("Mods/.MailboxMenu"))
        let before = try String(contentsOf: f.game.appendingPathComponent("Mods/.MailboxMenu/config.json"),
                                encoding: .utf8)

        await f.service.apply(report: report, gameDir: f.game.path,
                              mods: [try #require(mods["Swim"]), mailbox],
                              rescan: { f.box.rescans += 1 })

        guard case .applied(let result) = f.service.state else {
            Issue.record("état attendu .applied, obtenu \(f.service.state)"); return
        }
        #expect(result.written == 0)
        #expect(result.skipped.first?.contains("MailboxMenu") == true)
        #expect(try String(contentsOf: f.game.appendingPathComponent("Mods/.MailboxMenu/config.json"),
                           encoding: .utf8) == before)
    }
}
