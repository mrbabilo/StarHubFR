import Foundation
import Testing
@testable import StarHubTHCore

/// `restoreBackup` sait sauter — un dossier de sauvegarde disparu, un mod
/// désinstallé, un fichier absent de la sauvegarde, un fichier impossible à
/// écrire — et c'est le bon comportement : un incident sur un mod n'emporte pas
/// les autres. Mais elle ne rendait rien, et l'écran annonçait « Sauvegarde
/// restaurée » sans distinguer douze fichiers écrits de **zéro**.
///
/// Ces tests épinglent ce que la restauration rapporte, sur le modèle de
/// `ModInstallRestoreReport` (X22), qui rend ce qui a été écrit et où.
@Suite struct RestoreReportTests {

    private func writeConfig(_ env: TestEnvironment, physicalPath: String, content: String) throws {
        let dir = env.modsDir.appendingPathComponent(physicalPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.data(using: .utf8)!.write(to: dir.appendingPathComponent("config.json"))
    }

    @Test func aNominalRestoreReportsWhatItWrote() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        try writeConfig(env, physicalPath: "ModA", content: #"{"v":1}"#)
        try writeConfig(env, physicalPath: "ModB", content: #"{"v":1}"#)
        let mods = [makeTestMod(folderName: "ModA", isEnabled: true),
                    makeTestMod(folderName: "ModB", isEnabled: true)]
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: mods, onlyEnabled: false)

        let report = try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                                   selectedItems: backup.items, currentMods: mods)
        #expect(report.filesWritten == 2)
        #expect(report.modsRestored == 2)
        #expect(report.isComplete)
        #expect(report.skippedMods.isEmpty)
        #expect(report.skippedFiles.isEmpty)
    }

    @Test func aModNoLongerInstalledIsNamedInTheReport() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        try writeConfig(env, physicalPath: "Gone", content: #"{"v":1}"#)
        let mod = makeTestMod(folderName: "Gone", isEnabled: true)
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod], onlyEnabled: false)

        // Le mod est désinstallé entre la sauvegarde et la restauration : son
        // dossier n'existe plus, ni actif ni en pause.
        try FileManager.default.removeItem(at: env.modsDir.appendingPathComponent("Gone"))

        let report = try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                                   selectedItems: backup.items, currentMods: [mod])
        #expect(report.filesWritten == 0)
        #expect(report.modsRestored == 0)
        #expect(!report.isComplete)   // « restaurée » serait un mensonge
        #expect(report.skippedMods == ["Gone"])
    }

    @Test func aMissingBackupFolderIsNamedInTheReport() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        try writeConfig(env, physicalPath: "ModA", content: #"{"v":1}"#)
        let mod = makeTestMod(folderName: "ModA", isEnabled: true)
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod], onlyEnabled: false)

        // Le magasin a été amputé — c'est le cas des dossiers orphelins qu'on
        // sait exister (X25) : l'index cite un mod dont les fichiers sont
        // partis.
        let stored = env.manager.backupsDirectory
            .appendingPathComponent(backup.folderName, isDirectory: true)
            .appendingPathComponent("ModA", isDirectory: true)
        try FileManager.default.removeItem(at: stored)

        let report = try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                                   selectedItems: backup.items, currentMods: [mod])
        #expect(report.filesWritten == 0)
        #expect(!report.isComplete)
        #expect(report.skippedMods == ["ModA"])
    }

    @Test func onlyTheHealthyModsCountWhenOneIsSkipped() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        try writeConfig(env, physicalPath: "Healthy", content: #"{"v":1}"#)
        try writeConfig(env, physicalPath: "Gone", content: #"{"v":1}"#)
        let mods = [makeTestMod(folderName: "Healthy", isEnabled: true),
                    makeTestMod(folderName: "Gone", isEnabled: true)]
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: mods, onlyEnabled: false)
        try FileManager.default.removeItem(at: env.modsDir.appendingPathComponent("Gone"))

        let report = try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                                   selectedItems: backup.items, currentMods: mods)
        // Le mod sain est restauré — un incident n'emporte pas les autres —
        // et le rapport nomme celui qui manque.
        #expect(report.filesWritten == 1)
        #expect(report.modsRestored == 1)
        #expect(report.skippedMods == ["Gone"])
        #expect(!report.isComplete)
    }

    @Test func anUnwritableFileIsNamedWithItsMod() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        try writeConfig(env, physicalPath: "Locked", content: #"{"v":1}"#)
        let mod = makeTestMod(folderName: "Locked", isEnabled: true)
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod], onlyEnabled: false)

        // Le dossier du mod devient un **fichier** : l'écriture ne peut pas
        // aboutir, mais le mod est bien « installé » du point de vue du
        // résolveur de dossier.
        let modDir = env.modsDir.appendingPathComponent("Locked")
        try FileManager.default.removeItem(at: modDir)
        try Data("bloqué".utf8).write(to: modDir)

        let report = try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                                   selectedItems: backup.items, currentMods: [mod])
        #expect(report.filesWritten == 0)
        #expect(!report.isComplete)
        #expect(report.skippedFiles == ["Locked/config.json"])
    }
}
