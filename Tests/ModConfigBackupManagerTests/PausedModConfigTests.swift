import Foundation
import Testing
@testable import StarHubTHCore

/// **Presque toutes les configurations du parc appartiennent à des mods en
/// pause.** Mesuré le 2026-09-04 : **527 des 593 `config.json`** vivent dans un
/// dossier préfixé d'un point, contre 66 dans un mod actif.
///
/// La sauvegarde l'avait appris (elle lit `physicalFolderName`, et l'éditeur de
/// config prend ses instantanés avec `onlyEnabled: false`). La **restauration**,
/// elle, ne l'a jamais su : elle écrivait au nom logique.
@Suite struct PausedModConfigTests {

    private func makeMod(_ folderName: String, enabled: Bool) -> ModItem {
        makeTestMod(folderName: folderName, isEnabled: enabled)
    }

    private func writeConfig(_ env: TestEnvironment, physicalPath: String, content: String) throws {
        let dir = env.modsDir.appendingPathComponent(physicalPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.data(using: .utf8)!.write(to: dir.appendingPathComponent("config.json"))
    }

    private func readConfig(_ env: TestEnvironment, physicalPath: String) -> String? {
        try? String(contentsOf: env.modsDir.appendingPathComponent(physicalPath)
            .appendingPathComponent("config.json"), encoding: .utf8)
    }

    @Test func restoringAPausedModWritesIntoItsRealFolder() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        try writeConfig(env, physicalPath: ".PausedMod", content: #"{"v":1}"#)
        let mod = makeMod("PausedMod", enabled: false)
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod], onlyEnabled: false)

        // L'utilisateur change ses réglages, puis revient en arrière.
        try writeConfig(env, physicalPath: ".PausedMod", content: #"{"v":2}"#)
        try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                      selectedItems: backup.items, currentMods: [mod])

        #expect(readConfig(env, physicalPath: ".PausedMod") == #"{"v":1}"#)
        // Et aucun dossier fantôme : sans manifeste, il serait invisible du
        // scan comme du jeu, et la configuration perdue en silence.
        #expect(!FileManager.default.fileExists(
            atPath: env.modsDir.appendingPathComponent("PausedMod").path))
    }

    @Test func restoringAPausedPackComponentWritesIntoItsRealFolder() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        // Le point ne vit que sur l'entrée de tête, jamais sur le composant.
        try writeConfig(env, physicalPath: ".Pack/[CP] Child", content: #"{"v":1}"#)
        let child = makeMod("Pack/[CP] Child", enabled: false)
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [child], onlyEnabled: false)

        try writeConfig(env, physicalPath: ".Pack/[CP] Child", content: #"{"v":2}"#)
        try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                      selectedItems: backup.items, currentMods: [child])

        #expect(readConfig(env, physicalPath: ".Pack/[CP] Child") == #"{"v":1}"#)
        #expect(!FileManager.default.fileExists(
            atPath: env.modsDir.appendingPathComponent("Pack").path))
    }

    @Test func anActiveModIsUnaffected() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        try writeConfig(env, physicalPath: "ActiveMod", content: #"{"v":1}"#)
        let mod = makeMod("ActiveMod", enabled: true)
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod])

        try writeConfig(env, physicalPath: "ActiveMod", content: #"{"v":2}"#)
        try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                      selectedItems: backup.items, currentMods: [mod])

        #expect(readConfig(env, physicalPath: "ActiveMod") == #"{"v":1}"#)
        #expect(!FileManager.default.fileExists(
            atPath: env.modsDir.appendingPathComponent(".ActiveMod").path))
    }

    @Test func aModNoLongerInstalledIsSkippedNotFabricated() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        try writeConfig(env, physicalPath: ".GoneMod", content: #"{"v":1}"#)
        let mod = makeMod("GoneMod", enabled: false)
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod], onlyEnabled: false)
        try FileManager.default.removeItem(at: env.modsDir.appendingPathComponent(".GoneMod"))

        try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                      selectedItems: backup.items, currentMods: [mod])

        // Restaurer la configuration d'un mod désinstallé n'a pas de sens :
        // le dossier ne se fabrique pas.
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: env.modsDir.path)) ?? []
        #expect(entries.filter { $0 != ".DS_Store" }.isEmpty)
    }

    /// Le filet avant écrasement doit couvrir le mod **en pause** qu'on
    /// restaure — sinon la restauration écrase sans recours.
    @Test func theSafetyCopyCoversThePausedModBeingOverwritten() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        try writeConfig(env, physicalPath: ".PausedMod", content: #"{"v":1}"#)
        let mod = makeMod("PausedMod", enabled: false)
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod], onlyEnabled: false)

        let edited = #"{"v":"réglé depuis"}"#
        try writeConfig(env, physicalPath: ".PausedMod", content: edited)
        try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                      selectedItems: backup.items, currentMods: [mod])

        // Une sauvegarde de plus, et elle porte l'état d'avant la restauration.
        let all = env.manager.loadBackups()
        #expect(all.count == 2)
        guard let safety = all.first(where: { $0.id != backup.id }) else { return }
        let saved = try String(contentsOf: env.manager.backupsDirectory
            .appendingPathComponent(safety.folderName)
            .appendingPathComponent("PausedMod/config.json"), encoding: .utf8)
        #expect(saved == edited)
    }

    /// Le filet ne prend que ce qu'on écrase : parcourir tout le parc coûterait
    /// une traversée complète de `Mods/` (93 784 entrées sur le parc mesuré).
    @Test func theSafetyCopyIgnoresModsThatAreNotBeingRestored() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        try writeConfig(env, physicalPath: ".Restored", content: #"{"v":1}"#)
        try writeConfig(env, physicalPath: ".Untouched", content: #"{"v":1}"#)
        let restored = makeMod("Restored", enabled: false)
        let untouched = makeMod("Untouched", enabled: false)
        let backup = try env.manager.createBackup(gameDir: env.gameDir,
                                                  mods: [restored], onlyEnabled: false)

        try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                      selectedItems: backup.items,
                                      currentMods: [restored, untouched])

        let all = env.manager.loadBackups()
        #expect(all.count == 2)
        guard let safety = all.first(where: { $0.id != backup.id }) else { return }
        #expect(safety.items.map(\.modFolderName) == ["Restored"])
    }
}

/// Deux garanties que la forme des données et le contrat écrit exigent, et que
/// les cas simples ne touchent pas : un **pack** tel que le scan le produit
/// (une ligne, ses composants dedans), et la promesse de la documentation de
/// `restoreBackup` — « un fichier manquant est sauté, il n'interrompt pas la
/// restauration ».
@Suite struct ConfigRestoreShapeTests {

    private func writeConfig(_ env: TestEnvironment, physicalPath: String, content: String) throws {
        let dir = env.modsDir.appendingPathComponent(physicalPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.data(using: .utf8)!.write(to: dir.appendingPathComponent("config.json"))
    }

    @Test func theSafetyCopyReachesAComponentInsideAPack() throws {
        // La vue passe `vm.mods` : un pack y est **une** ligne dont le
        // `folderName` est celui du pack, ses composants dans `children`. Le
        // nom restauré est celui du composant — c'est par la branche
        // `children` que le pack doit être reconnu. 239 des 1 095 mods du parc
        // sont des composants.
        let env = TestEnvironment()
        defer { env.cleanup() }

        try writeConfig(env, physicalPath: ".Pack/[CP] Child", content: #"{"v":1}"#)
        let child = makeTestMod(folderName: "Pack/[CP] Child", isEnabled: false)
        let pack = makeTestMod(folderName: "Pack", isEnabled: false, children: [child], isGroup: true)

        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [pack], onlyEnabled: false)
        let edited = #"{"v":"réglé depuis"}"#
        try writeConfig(env, physicalPath: ".Pack/[CP] Child", content: edited)

        try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                      selectedItems: backup.items, currentMods: [pack])

        let all = env.manager.loadBackups()
        #expect(all.count == 2)
        guard let safety = all.first(where: { $0.id != backup.id }) else { return }
        #expect(safety.items.map(\.modFolderName) == ["Pack/[CP] Child"])
        let saved = try String(contentsOf: env.manager.backupsDirectory
            .appendingPathComponent(safety.folderName)
            .appendingPathComponent("Pack/[CP] Child/config.json"), encoding: .utf8)
        #expect(saved == edited)
    }

    @Test func oneUnwritableFileDoesNotAbandonTheOtherMods() throws {
        // Le contrat écrit de `restoreBackup`. Un fichier verrouillé
        // (`chflags uchg`) résiste même à la réouverture des droits — c'est le
        // seul cas qu'aucun `chmod` ne répare, donc le bon banc d'essai.
        let env = TestEnvironment()
        defer { env.cleanup() }

        try writeConfig(env, physicalPath: ".Locked", content: #"{"v":1}"#)
        try writeConfig(env, physicalPath: ".Fine", content: #"{"v":1}"#)
        let locked = makeTestMod(folderName: "Locked", isEnabled: false)
        let fine = makeTestMod(folderName: "Fine", isEnabled: false)
        let backup = try env.manager.createBackup(gameDir: env.gameDir,
                                                  mods: [locked, fine], onlyEnabled: false)

        try writeConfig(env, physicalPath: ".Locked", content: #"{"v":2}"#)
        try writeConfig(env, physicalPath: ".Fine", content: #"{"v":2}"#)
        let lockedFile = env.modsDir.appendingPathComponent(".Locked/config.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: lockedFile.path)
        defer { try? FileManager.default.setAttributes([.immutable: false],
                                                       ofItemAtPath: lockedFile.path) }

        // L'ordre compte : le mod verrouillé passe en premier.
        let ordered = backup.items.sorted { $0.modFolderName < $1.modFolderName }
        #expect(ordered.first?.modFolderName == "Fine")
        try env.manager.restoreBackup(gameDir: env.gameDir, backup: backup,
                                      selectedItems: ordered.reversed(), currentMods: [locked, fine])

        // Celui qui pouvait être restauré l'a été, malgré l'échec du premier.
        let fineContent = try String(contentsOf: env.modsDir.appendingPathComponent(".Fine/config.json"),
                                     encoding: .utf8)
        #expect(fineContent == #"{"v":1}"#)
    }
}
