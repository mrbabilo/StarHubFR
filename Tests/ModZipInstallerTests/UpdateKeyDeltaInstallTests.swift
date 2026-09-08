import Foundation
import Testing
@testable import StarHubTHCore

/// C2-T4 §5 — la branche `.overwriteWithBackup` de `install` est le seul
/// instant où l'ancien dossier et la source neuve coexistent : c'est là que
/// le delta de clés se capture, rendu sur l'`InstalledModPath`.
@Suite struct UpdateKeyDeltaInstallTests {

    /// Helpers write : ceux de UpdateKeyPreservationTests, répliqués
    /// (chaque fichier de test du dépôt porte ses helpers).
    private func write(_ content: String, base: URL, relativePath: String) throws {
        let url = base.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(toFile: url.path, atomically: true, encoding: .utf8)
    }

    private func makeOverwriteEnv() throws -> (env: InstallerTestEnv,
                                               installer: ModZipInstaller,
                                               run: (ConflictResolution?) throws -> [InstalledModPath]) {
        let env = InstallerTestEnv()
        // Un existant actif du même UniqueID dans Mods/, une archive au tempDir.
        try makeModFolder(base: env.modsDir, relativePath: "SampleMod",
                          uniqueId: "a.sample", name: "Sample")
        try makeModFolder(base: env.tempExtractDir, relativePath: "SampleMod",
                          uniqueId: "a.sample", name: "Sample")
        let existing = ModItem(uniqueId: "a.sample", name: "Sample",
                               folderName: "SampleMod", version: "1.0.0",
                               author: "A", description: "", nexusUrl: "",
                               nexusModId: "", isEnabled: true, dependencies: [],
                               children: nil, isGroup: false)
        let mod = DetectedMod(folderName: "SampleMod", relativePath: "SampleMod",
                              manifest: parsedManifest(uniqueId: "a.sample", name: "Sample"),
                              hasConfigFiles: false, dependencies: [], dependencyDetails: [],
                              existingVersion: existing)
        let installer = ModZipInstaller(backupManager: env.backupManager)
        let run: (ConflictResolution?) throws -> [InstalledModPath] = { resolution in
            let selection = InstallSelection(modId: mod.id, selected: true,
                                             conflictResolution: resolution)
            return try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                         selections: [selection], detectedMods: [mod],
                                         gameDir: env.gameDir, existingMods: [existing])
        }
        return (env, installer, run)
    }

    @Test func overwriteYieldsExactDelta() throws {
        let (env, _, run) = try makeOverwriteEnv()
        defer { env.cleanup() }
        // Ancien : config utilisateur {"Keep":true,"Old":"x"}, EN {"gone":"Old"},
        // FR {"gone":"Parti"}.
        try write(#"{"Keep":true,"Old":"x"}"#, base: env.modsDir,
                  relativePath: "SampleMod/config.json")
        try write(#"{"gone":"Old"}"#, base: env.modsDir,
                  relativePath: "SampleMod/i18n/default.json")
        try write(#"{"gone":"Parti"}"#, base: env.modsDir,
                  relativePath: "SampleMod/i18n/fr.json")
        // Neuf : config {"Keep":true,"New":"1"}, EN {"gone":"Old","fresh":"Neuf","byAuthor":"A"},
        // FR {"byAuthor":"FR de l'auteur"}.
        try write(#"{"Keep":true,"New":"1"}"#, base: env.tempExtractDir,
                  relativePath: "SampleMod/config.json")
        try write(#"{"gone":"Old","fresh":"Neuf","byAuthor":"A"}"#, base: env.tempExtractDir,
                  relativePath: "SampleMod/i18n/default.json")
        try write(#"{"byAuthor":"FR de l'auteur"}"#, base: env.tempExtractDir,
                  relativePath: "SampleMod/i18n/fr.json")

        let written = try run(.overwriteWithBackup)
        let delta = written.first?.keyDelta
        #expect(delta?.uniqueId == "a.sample")
        #expect(delta?.folderName == "SampleMod")
        #expect(Set((delta?.config?.added ?? [:]).keys) == ["New"])
        #expect(Set((delta?.config?.removed ?? [:]).keys) == ["Old"])
        #expect(delta?.config?.removed["Old"] == "x", "la valeur retirée est celle de l'utilisateur")
        #expect(Set((delta?.translation.addedUntranslated ?? [:]).keys) == ["fresh"])
        #expect(delta?.translation.addedAuthorTranslated["byAuthor"] == "FR de l'auteur")
        #expect(delta?.translation.removedKeys.isEmpty == true)
    }

    @Test func renameAndSkipYieldNoDelta() throws {
        let (env, _, run) = try makeOverwriteEnv()
        defer { env.cleanup() }
        try write(#"{"Keep":true}"#, base: env.modsDir,
                  relativePath: "SampleMod/config.json")

        // .skip : rien n'est écrit, rien n'est rendu.
        let skipped = try run(.skip)
        #expect(skipped.isEmpty || skipped.allSatisfy { $0.keyDelta == nil })

        // .rename : copie horodatée, l'original reste — pas une mise à jour.
        // (L'existant du même UniqueID est déjà posé par le harnais.)
        let renamed = try run(.rename)
        #expect(renamed.allSatisfy { $0.keyDelta == nil })
    }

    @Test func freshInstallYieldsNoDelta() throws {
        // Pas d'existant du même UniqueID : la branche overwrite n'est pas
        // prise, keyDelta reste nil.
        let env = InstallerTestEnv()
        defer { env.cleanup() }
        try makeModFolder(base: env.tempExtractDir, relativePath: "BrandNew",
                          uniqueId: "a.new", name: "BrandNew")
        try write(#"{"a":1}"#, base: env.tempExtractDir, relativePath: "BrandNew/config.json")
        let mod = DetectedMod(folderName: "BrandNew", relativePath: "BrandNew",
                              manifest: parsedManifest(uniqueId: "a.new", name: "BrandNew"),
                              hasConfigFiles: false, dependencies: [], dependencyDetails: [],
                              existingVersion: nil)
        let selection = InstallSelection(modId: mod.id, selected: true,
                                         conflictResolution: .overwriteWithBackup)
        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [mod],
                                            gameDir: env.gameDir, existingMods: [])
        #expect(written.allSatisfy { $0.keyDelta == nil })
    }
}
