import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T11 plan 2 — le nettoyage de bout en bout, sur des dossiers temporaires
/// et un faux Nexus. Jamais le vrai Application Support.
struct LegacyCleanupSessionTests {
    private let root: URL
    private var gameDir: String { root.appendingPathComponent("Game").path }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyCleanupSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    private func write(_ text: String, _ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func sha(_ text: String) throws -> String {
        try ModFolderHasher.sha256(of: write(text, "hash/\(UUID().uuidString)"))
    }

    private func mod(enabled: Bool = true, nexusId: String = "123") -> ModItem {
        ModItem(uniqueId: "a.sample", name: "Sample", folderName: "SampleMod", version: "1.0.0",
                author: "A", description: "", nexusUrl: "", nexusModId: nexusId, isEnabled: enabled,
                dependencies: [], children: nil, isGroup: false)
    }

    /// `modFiles` : 1.0.0 (dépôt 3) et 0.9.0 (dépôt 2) au format récent, 0.8.0
    /// (dépôt 1) au format ancien.
    private func nexus(current: [String: String], older: [String: String],
                       legacyPaths: [String]) -> NexusFileManifestFetcher.Transport {
        func recent(_ files: [String: String]) -> String {
            let entries = files.map { #"{"file_path":"\#($0.key)","file_hashes":{"SHA256":"\#($0.value)"}}"# }
            return #"{"archive":{"hashes":{"SHA256":"ARCH"}},"files":["# + entries.joined(separator: ",") + "]}"
        }
        let legacy = #"{"children":["# + legacyPaths.map {
            #"{"path":"\#($0)","name":"x","type":"file","size":"1 kB"}"#
        }.joined(separator: ",") + "]}"
        let listing = #"{"data":{"modFiles":["#
            + #"{"fileId":3,"version":"1.0.0","uri":"aa/bb/cc/aabbcc03-0000-4000-8000-000000000003","date":1700000000},"#
            + #"{"fileId":2,"version":"0.9.0","uri":"aa/bb/cc/aabbcc02-0000-4000-8000-000000000002","date":1690000000},"#
            + #"{"fileId":1,"version":"0.8.0","uri":"Sample 0.8-123-0-8-1600000000.zip","date":1600000000}"#
            + "]}}"
        let currentBody = recent(current), olderBody = recent(older)
        return { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasSuffix("/v2/graphql") { return .init(body: Data(listing.utf8), status: 200) }
            if url.hasSuffix("000000000003") { return .init(body: Data(currentBody.utf8), status: 200) }
            if url.hasSuffix("000000000002") { return .init(body: Data(olderBody.utf8), status: 200) }
            if url.hasSuffix("zip.json") { return .init(body: Data(legacy.utf8), status: 200) }
            return .init(body: nil, status: nil)
        }
    }

    @Test func analyzeEndToEnd() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = "Game/Mods/SampleMod/"
        try write("m", folder + "manifest.json")
        try write("a", folder + "a.png")
        try write("old", folder + "old.png")                 // identique à la 0.9.0
        try write("whatever", folder + "older.png")          // chemin de la 0.8.0
        try write("cfg", folder + "config.json")
        try write("fr", folder + "i18n/fr.json")
        try write("mine", folder + "user.png")
        try write("sub", folder + "[CP] Sub/manifest.json")  // un autre mod rangé ici
        try write("old", folder + "[CP] Sub/old.png")
        let transport = nexus(
            current: ["Sample/manifest.json": try sha("m"), "Sample/a.png": try sha("a")],
            older: ["Sample/manifest.json": try sha("m0"), "Sample/old.png": try sha("old")],
            legacyPaths: ["Sample/manifest.json", "Sample/older.png"])
        let outcome = LegacyCleanupSession.analyze(
            mod: mod(), gameDir: gameDir, translations: InstalledTranslationRegistry(byHost: [:]),
            customNexusIds: [:], historyDirectory: root.appendingPathComponent("History"),
            cacheDirectory: nil, transport: transport)
        guard case .plan(let plan) = outcome else { Issue.record("plan attendu"); return }
        #expect(plan.reference == .nexusRecent)
        #expect(plan.candidates.map(\.path) == ["old.png", "older.png"])
        #expect(plan.candidates.map(\.certainty) == [.identical, .pathOnly])
    }

    @Test func withoutNexusIdNorHistoryNothingIsAsked() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("m", "Game/Mods/SampleMod/manifest.json")
        let asked = Box()
        let outcome = LegacyCleanupSession.analyze(
            mod: mod(nexusId: ""), gameDir: gameDir, translations: InstalledTranslationRegistry(byHost: [:]),
            customNexusIds: [:], historyDirectory: root.appendingPathComponent("History"),
            cacheDirectory: nil, transport: { _ in asked.hit(); return .init(body: nil, status: nil) })
        #expect(outcome == .noReference)
        #expect(asked.count == 0)
    }

    @Test func aSharedUniqueIdIgnoresTheJournalAndDoesNotWriteIt() throws {
        // Swim installé deux fois : le journal de l'autre copie ne décrit pas
        // ce dossier (même abstention que `ModHistoryRecorder.recordInstall`).
        defer { try? FileManager.default.removeItem(at: root) }
        try write("m", "Game/Mods/SampleMod/manifest.json")
        try write("old", "Game/Mods/SampleMod/old.png")
        let history = root.appendingPathComponent("History")
        try ModHistoryFile.append(.init(date: Date(), kind: .install, fromVersion: nil, toVersion: "1.0.0",
                                        archiveSHA256: nil, nexusFileId: nil, source: nil,
                                        files: [.init(path: "manifest.json", size: 1, sha256: try sha("m"))],
                                        report: nil),
                                  uniqueId: "a.sample", directory: history)
        let alone = LegacyCleanupSession.analyze(
            mod: mod(nexusId: ""), gameDir: gameDir, translations: InstalledTranslationRegistry(byHost: [:]),
            customNexusIds: [:], historyDirectory: history, cacheDirectory: nil)
        guard case .plan(let plan) = alone else { Issue.record("référence locale attendue"); return }
        #expect(plan.reference == .localHistory)
        let shared = LegacyCleanupSession.analyze(
            mod: mod(nexusId: ""), gameDir: gameDir, translations: InstalledTranslationRegistry(byHost: [:]),
            customNexusIds: [:], uniqueIdIsShared: true, historyDirectory: history, cacheDirectory: nil)
        #expect(shared == .noReference)

        let before = ModHistoryFile.history(uniqueId: "a.sample", directory: history).entries.count
        let result = try LegacyCleanupSession.apply([try candidate("old.png")], mod: mod(), gameDir: gameDir,
                                                    backupManager: manager(), historyDirectory: history,
                                                    recordInHistory: false)
        #expect(result.removed.map(\.path) == ["old.png"])
        #expect(ModHistoryFile.history(uniqueId: "a.sample", directory: history).entries.count == before)
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func hit() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    /// Un candidat tel que l'analyse l'aurait rendu : l'empreinte réelle du
    /// fichier sur le disque.
    private func candidate(_ path: String, in folder: String = "SampleMod") throws -> LegacyFileCleanup.Candidate {
        let url = root.appendingPathComponent("Game/Mods/\(folder)/\(path)")
        return .init(path: path, size: 3, sha256: try ModFolderHasher.sha256(of: url), certainty: .identical)
    }

    private func manager() -> ModInstallBackupManager {
        ModInstallBackupManager(backupsBasePath: root.appendingPathComponent("Backups"))
    }

    @Test func applyBacksUpRemovesPrunesAndRecords() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("m", "Game/Mods/SampleMod/manifest.json")
        try write("old", "Game/Mods/SampleMod/obj/Debug/old.cs")
        try write("keep", "Game/Mods/SampleMod/obj/keep.txt")
        let backups = manager()
        let history = root.appendingPathComponent("History")
        let result = try LegacyCleanupSession.apply([try candidate("obj/Debug/old.cs")], mod: mod(),
                                                    gameDir: gameDir, backupManager: backups,
                                                    historyDirectory: history)
        let modRoot = root.appendingPathComponent("Game/Mods/SampleMod")
        #expect(result.removed.map(\.path) == ["obj/Debug/old.cs"])
        #expect(result.failed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: modRoot.appendingPathComponent("obj/Debug").path))
        #expect(FileManager.default.fileExists(atPath: modRoot.appendingPathComponent("obj/keep.txt").path))
        #expect(backups.loadBackups().first?.reason == .beforeCleanup)
        #expect(result.historyWritten)
        let entry = ModHistoryFile.history(uniqueId: "a.sample", directory: history).entries.last
        #expect(entry?.kind == .cleanup)
        #expect(entry?.files.map(\.path) == ["obj/Debug/old.cs"])
    }

    @Test func aGhostInAReadOnlyFolderIsRemoved() throws {
        defer {
            // La sauvegarde a copié le dossier en 0555 : tout rouvrir avant d'effacer.
            ModZipInstaller.grantOwnerWriteAccess(in: root)
            try? FileManager.default.removeItem(at: root)
        }
        try write("m", "Game/Mods/SampleMod/manifest.json")
        try write("old", "Game/Mods/SampleMod/locked/ghost.png")
        try write("keep", "Game/Mods/SampleMod/locked/keep.png")
        let locked = root.appendingPathComponent("Game/Mods/SampleMod/locked").path
        let ghost = try candidate("locked/ghost.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked)
        let result = try LegacyCleanupSession.apply([ghost], mod: mod(), gameDir: gameDir,
                                                    backupManager: manager(), historyDirectory: nil)
        #expect(result.removed.map(\.path) == ["locked/ghost.png"])
        #expect(!FileManager.default.fileExists(atPath: locked + "/ghost.png"))
        // Le dossier retrouve ses droits : l'ouverture ne sert qu'au retrait.
        #expect(try mode(of: locked) == 0o555)
    }

    private func mode(of path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777
    }

    @Test func aFolderEmptiedInsideAReadOnlyFolderIsPruned() throws {
        defer {
            ModZipInstaller.grantOwnerWriteAccess(in: root)
            try? FileManager.default.removeItem(at: root)
        }
        try write("m", "Game/Mods/SampleMod/manifest.json")
        try write("old", "Game/Mods/SampleMod/locked/sub/ghost.png")
        try write("keep", "Game/Mods/SampleMod/locked/keep.png")
        let locked = root.appendingPathComponent("Game/Mods/SampleMod/locked").path
        let ghost = try candidate("locked/sub/ghost.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked)
        let result = try LegacyCleanupSession.apply([ghost], mod: mod(), gameDir: gameDir,
                                                    backupManager: manager(), historyDirectory: nil)
        #expect(result.removed.map(\.path) == ["locked/sub/ghost.png"])
        #expect(!FileManager.default.fileExists(atPath: locked + "/sub"))
        #expect(try mode(of: locked) == 0o555)
    }

    private func component(enabled: Bool) -> ModItem {
        ModItem(uniqueId: "a.component", name: "Comp", folderName: "Pack/Comp", version: "1.0.0",
                author: "A", description: "", nexusUrl: "", nexusModId: "", isEnabled: enabled,
                dependencies: [], children: nil, isGroup: false)
    }

    @Test(arguments: [true, false])
    func aPackComponentIsCleanedInItsOwnFolder(enabled: Bool) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = enabled ? "Pack/Comp" : ".Pack/Comp"
        try write("m", "Game/Mods/\(folder)/manifest.json")
        try write("old", "Game/Mods/\(folder)/old.png")
        try write("sibling", "Game/Mods/\(enabled ? "Pack" : ".Pack")/Other/old.png")
        let backups = manager()
        let result = try LegacyCleanupSession.apply([try candidate("old.png", in: folder)],
                                                    mod: component(enabled: enabled), gameDir: gameDir,
                                                    backupManager: backups, historyDirectory: nil)
        #expect(result.removed.map(\.path) == ["old.png"])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Game/Mods/\(folder)/old.png").path))
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Game/Mods/\(enabled ? "Pack" : ".Pack")/Other/old.png").path))
        #expect(backups.loadBackups().count == 1)
    }

    @Test func aPausedModIsCleanedInItsRealFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("m", "Game/Mods/.SampleMod/manifest.json")
        try write("old", "Game/Mods/.SampleMod/old.png")
        let result = try LegacyCleanupSession.apply([try candidate("old.png", in: ".SampleMod")],
                                                    mod: mod(enabled: false), gameDir: gameDir,
                                                    backupManager: manager(), historyDirectory: nil)
        #expect(result.removed.map(\.path) == ["old.png"])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Game/Mods/.SampleMod/old.png").path))
    }

    @Test func aFileChangedSinceTheAnalysisIsKept() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("m", "Game/Mods/SampleMod/manifest.json")
        try write("old", "Game/Mods/SampleMod/old.png")
        let analysed = try candidate("old.png")
        // Une mise à jour est passée entre l'analyse et la confirmation.
        let changed = try write("new version", "Game/Mods/SampleMod/old.png")
        let result = try LegacyCleanupSession.apply([analysed], mod: mod(), gameDir: gameDir,
                                                    backupManager: manager(), historyDirectory: nil)
        #expect(result.removed.isEmpty)
        #expect(result.failed == ["old.png"])
        #expect(FileManager.default.fileExists(atPath: changed.path))
    }

    @Test func aFailedBackupRemovesNothing() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("m", "Game/Mods/SampleMod/manifest.json")
        let ghost = try write("old", "Game/Mods/SampleMod/old.png")
        let analysed = try candidate("old.png")
        // La base des sauvegardes est un fichier : impossible d'y créer un dossier.
        let blocked = try write("not a folder", "Backups")
        let broken = ModInstallBackupManager(backupsBasePath: blocked)
        #expect(throws: LegacyCleanupSession.ApplyError.self) {
            try LegacyCleanupSession.apply([analysed], mod: mod(), gameDir: gameDir,
                                           backupManager: broken, historyDirectory: nil)
        }
        #expect(FileManager.default.fileExists(atPath: ghost.path))
    }

    @Test func aPathLeavingTheModFolderIsRefused() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("m", "Game/Mods/SampleMod/manifest.json")
        let outside = try write("other", "Game/Mods/Other/file.png")
        let escaping = LegacyFileCleanup.Candidate(path: "../Other/file.png", size: 5,
                                                   sha256: try ModFolderHasher.sha256(of: outside),
                                                   certainty: .identical)
        let result = try LegacyCleanupSession.apply([escaping], mod: mod(), gameDir: gameDir,
                                                    backupManager: manager(), historyDirectory: nil)
        #expect(result.removed.isEmpty)
        #expect(result.failed == ["../Other/file.png"])
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }
}
