import Foundation
import Testing
@testable import StarHubTHCore

/// `install` dit désormais **où** il a écrit.
///
/// La feuille d'installation recalculait ces chemins de son côté pour ancrer la
/// version posée, retenir l'identifiant Nexus et réconcilier le manifest — trois
/// mécanismes qui lisent le `manifest.json` au chemin qu'on leur donne et
/// s'abstiennent en silence s'il n'y a rien. Or ce calcul divergeait de
/// l'installateur sur deux points, et les deux frappent le même mod :
///
/// - il cherchait le mod déjà installé dans les seules lignes de premier niveau,
///   donc jamais un **composant de pack** — **239 des 1 095 mods du parc**, 21 % ;
/// - sur un écrasement, il reprenait le nom de dossier de l'archive au lieu de
///   celui du mod installé, ce qui détache un composant de son pack.
///
/// Résultat pour ces mods, mis à jour depuis Nexus : chemin faux, donc aucune
/// ancre, aucun identifiant Nexus retenu, et la mise à jour toujours annoncée
/// après l'avoir installée. La règle est maintenant écrite une seule fois, là où
/// l'écriture a lieu.
struct InstalledPathsTests {
    private func detected(folderName: String, relativePath: String, uniqueId: String,
                          version: String, existing: ModItem?) -> DetectedMod {
        DetectedMod(folderName: folderName, relativePath: relativePath,
                    manifest: parsedManifest(uniqueId: uniqueId, name: folderName, version: version),
                    hasConfigFiles: false, dependencies: [], dependencyDetails: [],
                    existingVersion: existing)
    }

    private func installedMod(_ folderName: String, uniqueId: String, enabled: Bool) -> ModItem {
        ModItem(uniqueId: uniqueId, name: folderName, folderName: folderName,
                version: "1.0.0", author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [], children: nil, isGroup: false)
    }

    @Test func updatingAPackComponentReportsItsNestedPath() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(base: env.modsDir, relativePath: ".Parchment/[CP] Example",
                          uniqueId: "peacefulend.example", name: "[CP] Example", version: "1.2.0")
        let existing = installedMod("Parchment/[CP] Example",
                                    uniqueId: "peacefulend.example", enabled: false)

        try makeModFolder(base: env.tempExtractDir, relativePath: "Parchment/[CP] Example",
                          uniqueId: "peacefulend.example", name: "[CP] Example", version: "1.3.0")
        // Le nom détecté dans l'archive n'est que la dernière composante :
        // c'est là que le calcul de la vue partait à côté.
        let mod = detected(folderName: "[CP] Example", relativePath: "Parchment/[CP] Example",
                           uniqueId: "peacefulend.example", version: "1.3.0", existing: existing)
        let selection = InstallSelection(modId: mod.id, selected: true,
                                         conflictResolution: .overwriteWithBackup,
                                         configResolution: nil)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [mod],
                                            gameDir: env.gameDir, existingMods: [existing])

        let expected = env.modsDir.appendingPathComponent(".Parchment/[CP] Example").path
        #expect(written == [expected])
        #expect(FileManager.default.fileExists(atPath: expected + "/manifest.json"))
        // Ce que la vue calculait à la place : un chemin où il n'y a rien.
        #expect(!FileManager.default.fileExists(
            atPath: env.modsDir.appendingPathComponent(".[CP] Example").path))
    }

    @Test func updatingAnEnabledModKeepsItEnabledAndSaysSo() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(base: env.modsDir, relativePath: "Automate",
                          uniqueId: "pathoschild.automate", name: "Automate", version: "1.0.0")
        let existing = installedMod("Automate", uniqueId: "pathoschild.automate", enabled: true)

        try makeModFolder(base: env.tempExtractDir, relativePath: "Automate",
                          uniqueId: "pathoschild.automate", name: "Automate", version: "2.0.0")
        let mod = detected(folderName: "Automate", relativePath: "Automate",
                           uniqueId: "pathoschild.automate", version: "2.0.0", existing: existing)
        let selection = InstallSelection(modId: mod.id, selected: true,
                                         conflictResolution: .overwriteWithBackup,
                                         configResolution: nil)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [mod],
                                            gameDir: env.gameDir, existingMods: [existing])

        #expect(written == [env.modsDir.appendingPathComponent("Automate").path])
    }

    @Test func aBrandNewModLandsPausedAndSaysSo() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(base: env.tempExtractDir, relativePath: "NewMod",
                          uniqueId: "new.mod", name: "NewMod", version: "1.0.0")
        let mod = detected(folderName: "NewMod", relativePath: "NewMod",
                           uniqueId: "new.mod", version: "1.0.0", existing: nil)
        let selection = InstallSelection(modId: mod.id, selected: true,
                                         conflictResolution: nil, configResolution: nil)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [mod],
                                            gameDir: env.gameDir, existingMods: [])

        #expect(written == [env.modsDir.appendingPathComponent(".NewMod").path])
    }

    @Test func aRenamedInstallReportsItsStampedFolder() throws {
        // La vue s'abstenait sur `.rename` : le suffixe horodaté est fabriqué
        // dans l'installateur et n'était visible nulle part. Il l'est enfin.
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(base: env.modsDir, relativePath: "Automate",
                          uniqueId: "pathoschild.automate", name: "Automate", version: "1.0.0")
        let existing = installedMod("Automate", uniqueId: "pathoschild.automate", enabled: true)

        try makeModFolder(base: env.tempExtractDir, relativePath: "Automate",
                          uniqueId: "pathoschild.automate", name: "Automate", version: "2.0.0")
        let mod = detected(folderName: "Automate", relativePath: "Automate",
                           uniqueId: "pathoschild.automate", version: "2.0.0", existing: existing)
        let selection = InstallSelection(modId: mod.id, selected: true,
                                         conflictResolution: .rename, configResolution: nil)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [mod],
                                            gameDir: env.gameDir, existingMods: [existing])

        #expect(written.count == 1)
        let name = (written[0] as NSString).lastPathComponent
        #expect(name.hasPrefix(".Automate_"))
        #expect(FileManager.default.fileExists(atPath: written[0] + "/manifest.json"))
        // L'original reste en place : c'est tout le sens de « renommer ».
        #expect(FileManager.default.fileExists(
            atPath: env.modsDir.appendingPathComponent("Automate").path))
    }

    @Test func aSkippedModIsNotReported() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(base: env.modsDir, relativePath: "Automate",
                          uniqueId: "pathoschild.automate", name: "Automate", version: "1.0.0")
        let existing = installedMod("Automate", uniqueId: "pathoschild.automate", enabled: true)

        try makeModFolder(base: env.tempExtractDir, relativePath: "Automate",
                          uniqueId: "pathoschild.automate", name: "Automate", version: "2.0.0")
        let mod = detected(folderName: "Automate", relativePath: "Automate",
                           uniqueId: "pathoschild.automate", version: "2.0.0", existing: existing)
        let selection = InstallSelection(modId: mod.id, selected: true,
                                         conflictResolution: .skip, configResolution: nil)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [mod],
                                            gameDir: env.gameDir, existingMods: [existing])

        #expect(written.isEmpty)
    }

    @Test func anUnselectedModIsNotReported() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(base: env.tempExtractDir, relativePath: "NewMod",
                          uniqueId: "new.mod", name: "NewMod", version: "1.0.0")
        let mod = detected(folderName: "NewMod", relativePath: "NewMod",
                           uniqueId: "new.mod", version: "1.0.0", existing: nil)
        let selection = InstallSelection(modId: mod.id, selected: false,
                                         conflictResolution: nil, configResolution: nil)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [mod],
                                            gameDir: env.gameDir, existingMods: [])

        #expect(written.isEmpty)
    }
}
