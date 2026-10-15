import Foundation
import Testing
@testable import StarHubTHCore

/// Le service écrit de vrais `config.json` : tout vit dans un dossier
/// temporaire (faux `Mods/`, sauvegardes, magasin des familles) — jamais le
/// vrai Application Support ni le vrai parc.
@MainActor
struct KeybindPlanFixture {
    final class Box: @unchecked Sendable {
        var running = false
        var rescans = 0
    }

    let base: URL
    let game: URL
    let backups: ModConfigBackupManager
    let families: KeybindFamilyStore
    let mods: [ModItem]
    let box: Box
    let service: KeybindPlanService

    /// `configs` : dossier → (famille corrigée, texte de `config.json`).
    /// Les familles passent par le magasin : le test ne dépend pas des
    /// listes de mots-clés de la déduction.
    init(_ configs: [(String, KeybindFamily, String)], backupsBase: URL? = nil) throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeybindPlanServiceTests-\(UUID().uuidString)", isDirectory: true)
        game = base.appendingPathComponent("Game", isDirectory: true)
        let support = base.appendingPathComponent("Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        var mods: [ModItem] = []
        families = KeybindFamilyStore(directory: support)
        for (folder, family, text) in configs {
            let dir = game.appendingPathComponent("Mods/\(folder)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: dir.appendingPathComponent("config.json"))
            mods.append(Self.mod(folder))
            families.set(family, for: folder)
        }
        self.mods = mods
        backups = ModConfigBackupManager(
            backupsBasePath: backupsBase ?? base.appendingPathComponent("Backups", isDirectory: true))
        let box = Box()
        self.box = box
        service = KeybindPlanService(backupManager: backups, isGameRunning: { box.running })
    }

    static func mod(_ folder: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: "test.\(folder)", name: folder, folderName: folder,
                version: "1.0.0", author: "", description: "", nexusUrl: "",
                nexusModId: "", isEnabled: enabled, dependencies: [], hasConfigFile: true)
    }

    /// Swim (action) et MailboxMenu (info) sur H : l'info cède.
    static func conflictPair() throws -> KeybindPlanFixture {
        try KeybindPlanFixture([("Swim", .action, "{\n  \"DiveKey\": \"H\"\n}"),
                                ("MailboxMenu", .info, "{\n  \"MenuKey\": \"H\",\n  \"Other\": 3\n}")])
    }

    /// Deux conflits indépendants : MailboxMenu (H) et LookupInfo (J) perdent.
    static func twoConflicts() throws -> KeybindPlanFixture {
        try KeybindPlanFixture([("Swim", .action, #"{"DiveKey": "H"}"#),
                                ("MailboxMenu", .info, #"{"MenuKey": "H"}"#),
                                ("Fishing", .action, #"{"CastKey": "J"}"#),
                                ("LookupInfo", .info, #"{"LookupKey": "J"}"#)])
    }

    func config(_ folder: String) -> URL {
        game.appendingPathComponent("Mods/\(folder)/config.json")
    }

    func text(_ folder: String) throws -> String {
        try String(contentsOf: config(folder), encoding: .utf8)
    }

    func value(_ folder: String, _ key: String) throws -> String? {
        guard case .object(let object) = try #require(ConfigJSONTree.parse(try text(folder))),
              case .string(let raw)? = object.members[key] else { return nil }
        return raw
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

    func readyPlan() throws -> KeybindPlan {
        service.compute(report: try report(), familyStore: families, mode: .conflictsOnly)
        guard case .ready(let plan) = service.state else {
            Issue.record("état attendu .ready, obtenu \(service.state)")
            throw CancellationError()
        }
        return plan
    }

    func apply(report: KeybindScanner.KeybindReport? = nil, mods: [ModItem]? = nil,
               excluding: Set<String> = []) async throws {
        let report = try report ?? self.report()
        await service.apply(report: report, gameDir: game.path, mods: mods ?? self.mods,
                            excluding: excluding, rescan: { box.rescans += 1 })
    }

    func undo() async {
        await service.undo(gameDir: game.path, mods: mods, rescan: { box.rescans += 1 })
    }

    func applied() -> KeybindPlanService.AppliedResult? {
        guard case .applied(let result) = service.state else {
            Issue.record("état attendu .applied, obtenu \(service.state)")
            return nil
        }
        return result
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

typealias PlanSkip = KeybindPlanService.Skip
