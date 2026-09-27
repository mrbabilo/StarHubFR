import Foundation
import Testing
@testable import StarHubTHCore

struct RecorderAndRebaseTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecorderAndRebaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    private func write(_ text: String, _ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func detected(_ relativePath: String) throws -> DetectedMod {
        let manifest = try #require(ModManifest(dict: ["UniqueID": "a.sample", "Name": "Sample",
                                                       "Version": "2.0.0", "Author": "A"]))
        return DetectedMod(folderName: "SampleMod", relativePath: relativePath, manifest: manifest,
                           hasConfigFiles: false, dependencies: [], dependencyDetails: [],
                           existingVersion: nil)
    }

    private var existing: ModItem {
        ModItem(uniqueId: "a.sample", name: "Sample", folderName: "SampleMod", version: "1.0.0",
                author: "A", description: "", nexusUrl: "", nexusModId: "", isEnabled: true,
                dependencies: [], children: nil, isGroup: false)
    }

    @Test func aFreshInstallRecordsWhatTheArchiveShipped() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a", "Extract/SampleMod/a.png")
        let mod = try detected("SampleMod")
        let written = [InstalledModPath(modId: mod.id, path: "/Mods/SampleMod")]
        let history = root.appendingPathComponent("History")
        let failures = ModHistoryRecorder.recordInstall(
            written: written, accountedPaths: ["/Mods/SampleMod"], detectedMods: [mod],
            existingMods: [], tempDir: root.appendingPathComponent("Extract"),
            archive: try write("zip", "SampleMod.zip"), historyDirectory: history)
        #expect(failures.isEmpty)
        let entry = try #require(ModHistoryFile.history(uniqueId: "a.sample", directory: history).entries.last)
        #expect(entry.kind == .install)
        #expect(entry.toVersion == "2.0.0")
        #expect(entry.files.map(\.path) == ["a.png"])
        #expect(entry.source == "SampleMod.zip")
        #expect(entry.archiveSHA256?.count == 64)
    }

    @Test func anUpdateRecordsItsReportAndPreviousVersion() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let mod = try detected("SampleMod")
        var report = UpdateTriageReport()
        report.removedGhosts = ["ghost.png"]
        let plan = UpdateFileTriage.Plan(decisions: [:], respectedDeletions: [], report: report,
                                         newArchive: .init(hashes: ["a.png": "x"], sizes: ["a.png": 1]),
                                         sourceFileId: 9)
        var path = InstalledModPath(modId: mod.id, path: "/Mods/SampleMod")
        path.triage = plan
        let history = root.appendingPathComponent("History")
        _ = ModHistoryRecorder.recordInstall(
            written: [path], accountedPaths: ["/Mods/SampleMod"], detectedMods: [mod],
            existingMods: [existing], tempDir: root, archive: nil, historyDirectory: history)
        let entry = try #require(ModHistoryFile.history(uniqueId: "a.sample", directory: history).entries.last)
        #expect(entry.kind == .update)
        #expect(entry.fromVersion == "1.0.0")
        #expect(entry.nexusFileId == 9)
        #expect(entry.report?.removedGhosts == ["ghost.png"])
    }

    /// Une copie renommée à côté de l'original n'est pas journalisée.
    @Test func unaccountedPathsAreNotRecorded() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let mod = try detected("")
        let history = root.appendingPathComponent("History")
        _ = ModHistoryRecorder.recordInstall(
            written: [InstalledModPath(modId: mod.id, path: "/Mods/SampleMod_2026")],
            accountedPaths: [], detectedMods: [mod], existingMods: [], tempDir: root,
            archive: nil, historyDirectory: history)
        #expect(ModHistoryFile.load(uniqueId: "a.sample", directory: history) == .missing)
    }

    @Test func anAdditionIsADeposit() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("bag", "Host/assets/Modded Bags/bag.json")
        let history = root.appendingPathComponent("History")
        #expect(ModHistoryRecorder.recordAddition(
            host: existing, hostRoot: root.appendingPathComponent("Host"),
            files: [root.appendingPathComponent("Host/assets/Modded Bags/bag.json"),
                    root.appendingPathComponent("Elsewhere/x.json")],
            source: "Cloth And Colors Bag",
            historyDirectory: history))
        let loaded = ModHistoryFile.history(uniqueId: "a.sample", directory: history)
        // Hors de l'hôte : ignoré.
        #expect(loaded.depositedKeys == ["assets/modded bags/bag.json"])
        #expect(loaded.entries.last?.source == "Cloth And Colors Bag")
    }

    /// Les originaux mis à l'abri par une traduction deviennent ceux de la
    /// version neuve ; ceux que l'auteur ne livre plus sont oubliés.
    @Test func translationOriginalsFollowTheNewVersion() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let kept = try write("old fr", "Backups/fr.json")
        let gone = try write("old png", "Backups/old.png")
        try write("new fr", "New/i18n/fr.json")
        let translation = InstalledTranslation(
            hostFolderName: "SampleMod", nexusModId: 5, nexusName: "FR", version: "1",
            updatedAt: nil, installedAt: Date(), files: ["i18n/fr.json", "assets/old.png"],
            replacedFiles: ["i18n/fr.json": kept.path, "assets/old.png": gone.path])
        let steps = TranslationOriginalsRebase.steps(
            for: [translation], newArchive: ModFolderHasher.listing(of: root.appendingPathComponent("New")))
        let outcome = TranslationOriginalsRebase.apply(steps, newSource: root.appendingPathComponent("New"))
        #expect(outcome.failed.isEmpty)
        #expect(outcome.dropped == ["assets/old.png"])
        #expect(try String(contentsOf: kept, encoding: .utf8) == "new fr")
        #expect(!FileManager.default.fileExists(atPath: gone.path))

        var registry = InstalledTranslationRegistry(byHost: ["SampleMod": translation])
        // Hors du macro : `#expect` fige son autoclosure, un appel mutant n'y
        // compile pas.
        let changed = registry.forgetReplacedOriginals(outcome.dropped, host: "SampleMod")
        #expect(changed)
        #expect(registry.translation(forHost: "SampleMod")?.replacedFiles == ["i18n/fr.json": kept.path])
    }

    /// Le rebasage, tel que l'installation l'appelle : seulement pour les mods
    /// mis à jour (tri appliqué) qui portent une traduction.
    @Test func afterInstallRebasesOnlyTriagedHosts() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let backup = try write("old fr", "Backups/fr.json")
        try write("new fr", "Extract/SampleMod/i18n/fr.json")
        let mod = try detected("SampleMod")
        var path = InstalledModPath(modId: mod.id, path: "/Mods/SampleMod")
        path.triage = UpdateFileTriage.Plan(
            decisions: [:], respectedDeletions: [], report: UpdateTriageReport(),
            newArchive: ModFolderHasher.listing(of: root.appendingPathComponent("Extract/SampleMod")))
        let registry = InstalledTranslationRegistry(byHost: ["SampleMod": InstalledTranslation(
            hostFolderName: "SampleMod", nexusModId: 5, nexusName: "FR", version: "1", updatedAt: nil,
            installedAt: Date(), files: ["i18n/fr.json"], replacedFiles: ["i18n/fr.json": backup.path])])
        let outcome = TranslationOriginalsRebase.afterInstall(
            written: [path, InstalledModPath(modId: UUID(), path: "/Mods/Other")],
            detectedMods: [mod], existingMods: [existing], translations: registry,
            tempDir: root.appendingPathComponent("Extract"))
        #expect(outcome.dropped.isEmpty)
        #expect(outcome.failed.isEmpty)
        #expect(try String(contentsOf: backup, encoding: .utf8) == "new fr")
    }
}
