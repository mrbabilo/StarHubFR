import Foundation
import Testing
@testable import StarHubTHCore

/// X63 — installer un mod **neuf** ne doit pas effacer le dossier d'un autre.
///
/// `install` cherche le mod déjà présent par `UniqueID` seul
/// (`findExistingMod`). Quand aucun ne correspond, il pose la copie à
/// `Mods/.<nom de dossier de l'archive>` — et si ce chemin est déjà occupé, il
/// écarte l'occupant dans le dossier temporaire puis **le supprime** dès que la
/// copie réussit. L'occupant n'a été ni sauvegardé (la sauvegarde ne vit que
/// dans la branche `.overwriteWithBackup`, conditionnée au même `UniqueID`) ni
/// annoncé.
///
/// Ce n'est pas une hypothèse : deux `[CP] Seaside Sounds` d'auteurs différents
/// se disputent déjà un nom de dossier sur le parc de référence (X60). Le même
/// nom logique porté par deux `UniqueID` distincts est un cas réel, et il suffit
/// que l'un soit en pause — donc à `Mods/.X`, exactement là où atterrit un mod
/// neuf — pour que l'installation du second le détruise en silence.
@Suite struct InstallFolderCollisionTests {

    private func detected(folderName: String, uniqueId: String, version: String = "1.0.0") -> DetectedMod {
        DetectedMod(folderName: folderName, relativePath: folderName,
                    manifest: parsedManifest(uniqueId: uniqueId, name: folderName, version: version),
                    hasConfigFiles: false, dependencies: [], dependencyDetails: [],
                    existingVersion: nil)
    }

    @Test func aNewModDoesNotDestroyAnUnrelatedFolderOfTheSameName() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        // Déjà en place, en pause : un mod d'un autre auteur, même nom de dossier.
        try makeModFolder(base: env.modsDir, relativePath: ".[CP] Seaside Sounds",
                          uniqueId: "liana.seasidesounds", name: "[CP] Seaside Sounds",
                          version: "2.0.0", extraContent: "l'original de Liana")
        let occupant = ModItem(uniqueId: "liana.seasidesounds", name: "[CP] Seaside Sounds",
                               folderName: "[CP] Seaside Sounds", version: "2.0.0",
                               author: "Liana", description: "", nexusUrl: "", nexusModId: "",
                               isEnabled: false, dependencies: [], children: nil, isGroup: false)

        // L'archive : un mod **neuf**, autre `UniqueID`, même nom de dossier.
        try makeModFolder(base: env.tempExtractDir, relativePath: "[CP] Seaside Sounds",
                          uniqueId: "witchtopia.seasidesounds", name: "[CP] Seaside Sounds",
                          version: "1.0.0", extraContent: "le nouveau de witchtopia")
        let mod = detected(folderName: "[CP] Seaside Sounds", uniqueId: "witchtopia.seasidesounds")
        let selection = InstallSelection(modId: mod.id, selected: true,
                                         conflictResolution: nil, configResolution: nil)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [mod],
                                            gameDir: env.gameDir, existingMods: [occupant])

        // L'occupant est intact, là où il était.
        let occupantFile = env.modsDir
            .appendingPathComponent(".[CP] Seaside Sounds/data.txt")
        #expect(FileManager.default.fileExists(atPath: occupantFile.path),
                "le mod déjà installé a été effacé par l'installation d'un mod sans rapport")
        #expect(try String(contentsOf: occupantFile, encoding: .utf8) == "l'original de Liana")

        // Et le nouveau est bien posé, ailleurs — le chemin rendu le dit.
        #expect(written.count == 1)
        let newPath = try #require(written.first?.path)
        #expect(newPath != env.modsDir.appendingPathComponent(".[CP] Seaside Sounds").path)
        #expect(FileManager.default.fileExists(atPath: (newPath as NSString).appendingPathComponent("data.txt")))

        // L'écart se dit : c'est ce que la vue journalise.
        #expect(written.first?.displacedFrom == "[CP] Seaside Sounds")
    }

    @Test func twoModsOfTheSameArchiveSharingAFolderNameBothSurvive() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        // Une archive à deux composants de même nom feuille sous deux parents
        // différents : `commonParent` ne trouve rien de partagé, les deux
        // atterrissent donc sous le même `Mods/.<feuille>`.
        try makeModFolder(base: env.tempExtractDir, relativePath: "A/[CP] Portraits",
                          uniqueId: "author.portraits.a", name: "[CP] Portraits",
                          extraContent: "variante A")
        try makeModFolder(base: env.tempExtractDir, relativePath: "B/[CP] Portraits",
                          uniqueId: "author.portraits.b", name: "[CP] Portraits",
                          extraContent: "variante B")

        let first = DetectedMod(folderName: "[CP] Portraits", relativePath: "A/[CP] Portraits",
                                manifest: parsedManifest(uniqueId: "author.portraits.a", name: "[CP] Portraits"),
                                hasConfigFiles: false, dependencies: [], dependencyDetails: [],
                                existingVersion: nil)
        let second = DetectedMod(folderName: "[CP] Portraits", relativePath: "B/[CP] Portraits",
                                 manifest: parsedManifest(uniqueId: "author.portraits.b", name: "[CP] Portraits"),
                                 hasConfigFiles: false, dependencies: [], dependencyDetails: [],
                                 existingVersion: nil)
        let selections = [first, second].map {
            InstallSelection(modId: $0.id, selected: true, conflictResolution: nil, configResolution: nil)
        }

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: selections, detectedMods: [first, second],
                                            gameDir: env.gameDir, existingMods: [])

        #expect(written.count == 2)
        let paths = Set(written.map { $0.path })
        #expect(paths.count == 2, "les deux composants se sont écrits au même endroit")
        let contents = written.map { path -> String in
            let file = (path.path as NSString).appendingPathComponent("data.txt")
            return (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        }
        #expect(Set(contents) == Set(["variante A", "variante B"]))
    }

    /// Le cas voisin qui ne doit **pas** bouger : réinstaller le même mod
    /// écrase son propre dossier, garde son nom, et n'invente pas d'horodatage.
    /// Une garde qui se déclencherait ici laisserait deux copies du même
    /// `UniqueID` sous `Mods/` — SMAPI les chargerait toutes les deux.
    @Test func reinstallingTheSameModStillOverwritesItsOwnFolder() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(base: env.modsDir, relativePath: ".[CP] Portraits",
                          uniqueId: "author.portraits", name: "[CP] Portraits",
                          version: "1.0.0", extraContent: "ancienne version")
        let existing = ModItem(uniqueId: "author.portraits", name: "[CP] Portraits",
                               folderName: "[CP] Portraits", version: "1.0.0",
                               author: "", description: "", nexusUrl: "", nexusModId: "",
                               isEnabled: false, dependencies: [], children: nil, isGroup: false)

        try makeModFolder(base: env.tempExtractDir, relativePath: "[CP] Portraits",
                          uniqueId: "author.portraits", name: "[CP] Portraits",
                          version: "1.1.0", extraContent: "nouvelle version")
        let mod = detected(folderName: "[CP] Portraits", uniqueId: "author.portraits", version: "1.1.0")
        let selection = InstallSelection(modId: mod.id, selected: true,
                                         conflictResolution: nil, configResolution: nil)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [mod],
                                            gameDir: env.gameDir, existingMods: [existing])

        let expected = env.modsDir.appendingPathComponent(".[CP] Portraits").path
        #expect(written.first?.path == expected)
        #expect(written.first?.displacedFrom == nil)
        let file = (expected as NSString).appendingPathComponent("data.txt")
        #expect(try String(contentsOfFile: file, encoding: .utf8) == "nouvelle version")
        // Aucun dossier horodaté à côté.
        let siblings = try FileManager.default.contentsOfDirectory(atPath: env.modsDir.path)
        #expect(siblings == [".[CP] Portraits"])
    }

    /// Une **racine de pack** ne porte pas de `manifest.json` — ce sont ses
    /// composants qui en portent. Le propriétaire y est donc illisible, et
    /// l'absence de propriétaire ne vaut pas permission d'effacer : c'est le
    /// nouveau qui se décale.
    @Test func aPackRootIsNotMistakenForAFreeFolder() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        // Le pack en pause : seule sa feuille porte un manifeste.
        try makeModFolder(base: env.modsDir, relativePath: ".Lilybrook/[CP] Lilybrook",
                          uniqueId: "lilybrook.cp", name: "[CP] Lilybrook",
                          extraContent: "le pack de l'utilisateur")

        // Une archive à plat dont le dossier s'appelle, lui aussi, « Lilybrook ».
        try makeModFolder(base: env.tempExtractDir, relativePath: "Lilybrook",
                          uniqueId: "someone.lilybrook", name: "Lilybrook",
                          extraContent: "l'archive")
        let mod = detected(folderName: "Lilybrook", uniqueId: "someone.lilybrook")
        let selection = InstallSelection(modId: mod.id, selected: true,
                                         conflictResolution: nil, configResolution: nil)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [mod],
                                            gameDir: env.gameDir, existingMods: [])

        let packFile = env.modsDir
            .appendingPathComponent(".Lilybrook/[CP] Lilybrook/data.txt")
        #expect(try String(contentsOf: packFile, encoding: .utf8) == "le pack de l'utilisateur")
        #expect(written.first?.path != env.modsDir.appendingPathComponent(".Lilybrook").path)
    }
}
