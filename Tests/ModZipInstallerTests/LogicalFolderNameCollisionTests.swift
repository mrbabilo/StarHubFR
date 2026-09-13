import Foundation
import Testing
@testable import StarHubTHCore

/// Le nom **logique** de dossier d'un mod à installer est déjà pris par un mod
/// d'**autre** UniqueID — le cas réel qui a déclenché le chantier : deux
/// `[CP] Sounds of the Valley`, l'auteur ayant changé l'identifiant entre
/// versions (`Juanpa98ar.SotV` en 3.1.0 active, `Juanpa98ar.Source.SotV` en
/// 4.0.0 en pause). L'installateur ne voyait que l'identifiant : le nouveau
/// partait en pause en silence et — `ModItem.id` étant le nom logique — les
/// deux mods partageaient l'identité `Identifiable`, un seul rendu à l'écran.
///
/// Décision de l'auteur (2026-09-13) : **signal + choix dans l'aperçu**,
/// jamais d'écrasement automatique d'un mod d'uniqueId différent.
///
/// Les deux types de conflit ne fusionnent jamais : identifiant identique →
/// `.folderExists` seul (l'occupant du nom EST l'existant) ; le nom ne
/// redétecte jamais ce cas.
///
/// La détection est appelée par la fonction **pure** extraite
/// (`ModZipInstaller.detectConflicts`) : aucun fichier, aucun zip — la pureté
/// est le but, le harnais tmp UUID des suites voisines ne sert qu'aux tests
/// qui touchent le disque.
@Suite struct LogicalFolderNameCollisionTests {

    private func modItem(folderName: String, uniqueId: String,
                         version: String = "1.0.0",
                         isEnabled: Bool = false) -> ModItem {
        ModItem(uniqueId: uniqueId, name: folderName,
                folderName: folderName, version: version,
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: isEnabled, dependencies: [], children: nil, isGroup: false)
    }

    // MARK: - Le finder logique (`Array<ModItem>.mod(withLogicalFolderName:)`)

    /// Test 1 — le point de pause est décapité des deux côtés.
    @Test func logicalNameStripsThePauseDot() {
        let sounds = modItem(folderName: "[CP] Sounds of the Valley",
                             uniqueId: "Juanpa98ar.SotV", version: "3.1.0",
                             isEnabled: false)
        #expect(sounds.physicalFolderName == ".[CP] Sounds of the Valley")
        let mods = [sounds]

        // Le mod en pause vit à `.[CP] Sounds of the Valley` sur le disque ;
        // son nom **logique** reste le sien.
        #expect(mods.mod(withLogicalFolderName: "[CP] Sounds of the Valley")?.id
                == "[CP] Sounds of the Valley")

        // Une entrée portant le point de tête (construction directe, comme le
        // nom brut d'une archive) est trouvée par son nom logique.
        let dotted = [modItem(folderName: ".[CP] X", uniqueId: "some.dotted",
                              isEnabled: true)]
        #expect(dotted.mod(withLogicalFolderName: "[CP] X")?.id == ".[CP] X")

        #expect(mods.mod(withLogicalFolderName: "Absent") == nil)
    }

    /// Test 2 — la comparaison est insensible à la casse : APFS n'en distingue
    /// pas, `[CP] X` et `[cp] x` sont le même dossier.
    @Test func logicalNameIsCaseInsensitive() {
        let mods = [modItem(folderName: "[CP] Sounds of the Valley",
                            uniqueId: "Juanpa98ar.SotV")]
        #expect(mods.mod(withLogicalFolderName: "[cp] sounds of the valley")?.id
                == "[CP] Sounds of the Valley")
    }

    // MARK: - La détection (`ModZipInstaller.detectConflicts`)

    /// Test 3 — identifiant absent des installés, nom logique occupé par un
    /// mod d'autre identifiant : un conflit `.nameTakenByOtherMod`,
    /// `existingVersion` = la version de l'**occupant**, les trois
    /// résolutions offertes.
    @Test func aDifferentUniqueIdOnATakenNameDetectsNameTaken() throws {
        let occupant = modItem(folderName: "[CP] Sounds of the Valley",
                               uniqueId: "Juanpa98ar.SotV", version: "3.1.0")
        let incoming = parsedManifest(uniqueId: "Juanpa98ar.Source.SotV",
                                      name: "[CP] Sounds of the Valley",
                                      version: "4.0.0")

        let detection = ModZipInstaller.detectConflicts(
            forFolderName: "[CP] Sounds of the Valley",
            manifest: incoming, in: [occupant])

        // L'identifiant du nouveau n'a trouvé personne : pas d'existing.
        #expect(detection.existing == nil)
        #expect(detection.conflicts.count == 1)
        let conflict = try #require(detection.conflicts.first)
        #expect(conflict.conflictType == .nameTakenByOtherMod)
        // La version affichée est celle de l'occupant — c'est lui qu'on
        // remplacerait.
        #expect(conflict.existingVersion == "3.1.0")
        #expect(conflict.newVersion == "4.0.0")
        #expect(Set(conflict.resolutionOptions)
                == Set([.overwriteWithBackup, .rename, .skip]))
    }

    /// Test 4 — le cas voisin qui ne doit **pas** fusionner : identifiant
    /// identique → exactement un conflit `.folderExists`, jamais de conflit
    /// de nom (l'occupant du nom EST l'existant).
    @Test func sameUniqueIdStillDetectsFolderExistsOnly() throws {
        let existing = modItem(folderName: "[CP] Sounds of the Valley",
                               uniqueId: "Juanpa98ar.SotV", version: "3.1.0")
        let incoming = parsedManifest(uniqueId: "Juanpa98ar.SotV",
                                      name: "[CP] Sounds of the Valley",
                                      version: "4.0.0")

        let detection = ModZipInstaller.detectConflicts(
            forFolderName: "[CP] Sounds of the Valley",
            manifest: incoming, in: [existing])

        #expect(detection.existing?.id == existing.id)
        #expect(detection.conflicts.count == 1,
                "les deux types de conflit ne fusionnent jamais")
        let conflict = try #require(detection.conflicts.first)
        #expect(conflict.conflictType == .folderExists)
        #expect(conflict.existingVersion == "3.1.0")
    }

    /// Test 5 — le défaut **par type** : une mise à jour d'identifiant écrase
    /// (le geste demandé, comportement historique inchangé) ; un nom pris par
    /// un autre mod se décale — jamais d'écrasement d'un autre mod sans choix
    /// explicite.
    @Test func defaultResolutionDependsOnConflictType() {
        #expect(ConflictResolution.default(for: .folderExists) == .overwriteWithBackup)
        #expect(ConflictResolution.default(for: .nameTakenByOtherMod) == .rename)
    }

    // MARK: - La comptabilité post-installation (`accountingPaths`)

    /// Le défaut armé `.rename` ne doit pas faire perdre la comptabilité
    /// Nexus (ancre de version, réconciliation, enregistrement id→dossier) :
    /// l'abstention vise la **copie du même UniqueID restée en place**, pas
    /// la valeur brute de la résolution. Un nom pris par un **autre** mod se
    /// décale, mais rien de son identifiant ne survit ailleurs — sans cela,
    /// le mod à peine posé réapparaît dans Mod Updates. C'est le scénario
    /// cible du chantier (SotV 4.0.0 posée par téléchargement intégré).
    @Test func aNameTakenConflictRenamedStillCountsForNexusAccounting() {
        let detected = DetectedMod(
            folderName: "[CP] Sounds of the Valley",
            relativePath: "[CP] Sounds of the Valley",
            manifest: parsedManifest(uniqueId: "Juanpa98ar.Source.SotV",
                                     name: "[CP] Sounds of the Valley",
                                     version: "4.0.0"),
            hasConfigFiles: false, dependencies: [], dependencyDetails: [],
            existingVersion: nil) // aucun mod du même identifiant en place
        let selection = InstallSelection(modId: detected.id, selected: true,
                                         conflictResolution: .rename)
        let written = InstalledModPath(modId: detected.id,
                                       path: "/Mods/.[CP] Sounds of the Valley",
                                       displacedFrom: nil)

        let paths = ModZipInstaller.accountingPaths(
            written: [written], selections: [selection], detectedMods: [detected])

        #expect(paths == [written.path],
                "renommé pour nom pris par un autre mod : la comptabilité doit le compter")
    }

    /// Le cas voisin qui ne doit **pas** bouger : un conflit d'identifiant
    /// résolu par renommage laisse une copie du même `UniqueID` en place —
    /// l'ancien dossier survit, et l'ancre (unique par identifiant) doit
    /// décrire **celle qui reste active**. Abstention comme avant.
    @Test func aSameUniqueIdConflictRenamedIsStillExcludedFromAccounting() {
        let existing = modItem(folderName: "[CP] Sounds of the Valley",
                               uniqueId: "Juanpa98ar.SotV", version: "3.1.0",
                               isEnabled: true)
        let detected = DetectedMod(
            folderName: "[CP] Sounds of the Valley",
            relativePath: "[CP] Sounds of the Valley",
            manifest: parsedManifest(uniqueId: "Juanpa98ar.SotV",
                                     name: "[CP] Sounds of the Valley",
                                     version: "4.0.0"),
            hasConfigFiles: false, dependencies: [], dependencyDetails: [],
            existingVersion: existing) // une copie du même identifiant survit
        let selection = InstallSelection(modId: detected.id, selected: true,
                                         conflictResolution: .rename)
        let written = InstalledModPath(modId: detected.id,
                                       path: "/Mods/.[CP] Sounds of the Valley 2",
                                       displacedFrom: nil)

        let paths = ModZipInstaller.accountingPaths(
            written: [written], selections: [selection], detectedMods: [detected])

        #expect(paths.isEmpty,
                "renommé pour conflit d'identifiant : la copie restée en place interdit l'ancre")
    }

    /// Le déplacement physique (X63) reste exclu des deux types : le critère
    /// corrigé ne doit pas le faire rentrer.
    @Test func aDisplacedWriteIsStillExcludedFromAccounting() {
        let detected = DetectedMod(
            folderName: "[CP] Sounds of the Valley",
            relativePath: "[CP] Sounds of the Valley",
            manifest: parsedManifest(uniqueId: "Juanpa98ar.Source.SotV",
                                     name: "[CP] Sounds of the Valley",
                                     version: "4.0.0"),
            hasConfigFiles: false, dependencies: [], dependencyDetails: [],
            existingVersion: nil)
        let selection = InstallSelection(modId: detected.id, selected: true,
                                         conflictResolution: .rename)
        let written = InstalledModPath(modId: detected.id,
                                       path: "/Mods/.[CP] Sounds of the Valley 2026-09-13",
                                       displacedFrom: "[CP] Sounds of the Valley")

        let paths = ModZipInstaller.accountingPaths(
            written: [written], selections: [selection], detectedMods: [detected])

        #expect(paths.isEmpty,
                "déplacé (X63) : renommage par d'autres moyens, même abstention")
    }

    // MARK: - L'installation honore la résolution (l'occupant traité comme l'existant)

    // Les quatre tests qui suivent touchent le disque : harnais
    // `InstallerTestEnv` (tmp UUID, magasin de sauvegardes du test), même
    // patron que `InstallFolderCollisionTests`. Aujourd'hui la résolution
    // n'est honorée que derrière un existant d'identifiant — un nom pris par
    // un autre mod ignore `.skip` (le mod s'installe quand même) et
    // `.overwriteWithBackup` (le nouveau se décale, l'occupant reste).
    // Seul `.rename` est déjà le bon comportement : son test verdit d'entrée
    // et le restera — c'est la preuve de fidélité du chemin inchangé.

    /// Résolution `.overwriteWithBackup` sur un nom pris : la sauvegarde
    /// porte l'**occupant** (ses octets, pas ceux du neuf), l'occupant
    /// disparaît, le nouveau vit à son chemin logique — **actif** quand
    /// l'occupant l'était (le geste demandé : remplacer un mod actif par sa
    /// suite d'identifiant changé).
    @Test func overwriteResolutionReplacesTheOccupantWithBackup() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        // L'occupant est ACTIF : `Mods/[CP] Sounds of the Valley`, sans point.
        try makeModFolder(base: env.modsDir, relativePath: "[CP] Sounds of the Valley",
                          uniqueId: "Juanpa98ar.SotV", name: "[CP] Sounds of the Valley",
                          version: "3.1.0", extraContent: "l'original de Liana")
        let occupant = modItem(folderName: "[CP] Sounds of the Valley",
                               uniqueId: "Juanpa98ar.SotV", version: "3.1.0",
                               isEnabled: true)

        // L'archive : la suite du mod, l'auteur ayant changé l'identifiant
        // (le scénario réel qui a déclenché le chantier).
        try makeModFolder(base: env.tempExtractDir, relativePath: "[CP] Sounds of the Valley",
                          uniqueId: "Juanpa98ar.Source.SotV", name: "[CP] Sounds of the Valley",
                          version: "4.0.0", extraContent: "le nouveau")
        let detected = DetectedMod(
            folderName: "[CP] Sounds of the Valley",
            relativePath: "[CP] Sounds of the Valley",
            manifest: parsedManifest(uniqueId: "Juanpa98ar.Source.SotV",
                                     name: "[CP] Sounds of the Valley",
                                     version: "4.0.0"),
            hasConfigFiles: false, dependencies: [], dependencyDetails: [],
            existingVersion: nil) // aucun mod du même identifiant en place
        let selection = InstallSelection(modId: detected.id, selected: true,
                                         conflictResolution: .overwriteWithBackup)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [detected],
                                            gameDir: env.gameDir, existingMods: [occupant])

        // Une sauvegarde — et c'est celle de l'OCCUPANT : ses octets y sont.
        let backups = env.backupManager.loadBackups()
        #expect(backups.count == 1,
                "écraser l'occupant exige sa sauvegarde AVANT toute touche")
        let backup = try #require(backups.first)
        #expect(backup.originalFolderName == "[CP] Sounds of the Valley")
        #expect(backup.backupPath.hasPrefix(env.backupsRoot.path),
                "la sauvegarde va dans le magasin du test, pas ailleurs")
        let backupData = (backup.backupPath as NSString).appendingPathComponent("data.txt")
        #expect(try String(contentsOfFile: backupData, encoding: .utf8) == "l'original de Liana")

        // Le nouveau vit à la place exacte de l'occupant — ACTIF (sans
        // point), puisque l'occupant l'était.
        #expect(written.count == 1)
        let expected = env.modsDir.appendingPathComponent("[CP] Sounds of the Valley").path
        #expect(written.first?.path == expected,
                "l'installé reprend le chemin logique de l'occupant actif")
        let dataFile = (expected as NSString).appendingPathComponent("data.txt")
        #expect(try String(contentsOfFile: dataFile, encoding: .utf8) == "le nouveau")

        // Aucun double en pause à côté : remplacer un mod actif ne pose pas
        // une seconde copie que SMAPI chargerait en plus.
        let dotted = env.modsDir.appendingPathComponent(".[CP] Sounds of the Valley").path
        #expect(!FileManager.default.fileExists(atPath: dotted))
    }

    /// Le `config.json` et la traduction FR de l'**occupant** survivent à
    /// l'écrasement — le patron `PreserveUserConfigsTests`, bout en bout par
    /// `install` : la résolution porte sur l'occupant, la préservation aussi.
    @Test func overwriteResolutionPreservesUserConfigsOfTheOccupant() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        // L'occupant, en pause : un config.json et un fr.json communautaire —
        // ce que l'utilisateur a réglé et que l'archive neuve ne porte pas.
        let occupantDir = try makeModFolder(
            base: env.modsDir, relativePath: ".[CP] Sounds of the Valley",
            uniqueId: "Juanpa98ar.SotV", name: "[CP] Sounds of the Valley",
            version: "3.1.0", extraContent: "l'original de Liana")
        try #"{"OldConfig":true}"#.data(using: .utf8)!
            .write(to: occupantDir.appendingPathComponent("config.json"))
        let occupantI18n = occupantDir.appendingPathComponent("i18n", isDirectory: true)
        try FileManager.default.createDirectory(at: occupantI18n, withIntermediateDirectories: true)
        try #"{"key":"Bonjour"}"#.data(using: .utf8)!
            .write(to: occupantI18n.appendingPathComponent("fr.json"))
        let occupant = modItem(folderName: "[CP] Sounds of the Valley",
                               uniqueId: "Juanpa98ar.SotV", version: "3.1.0",
                               isEnabled: false)

        // L'archive neuve : ni config.json ni fr.json — le cas courant,
        // l'auteur ne redistribue pas la traduction.
        try makeModFolder(base: env.tempExtractDir, relativePath: "[CP] Sounds of the Valley",
                          uniqueId: "Juanpa98ar.Source.SotV", name: "[CP] Sounds of the Valley",
                          version: "4.0.0", extraContent: "le nouveau")
        let detected = DetectedMod(
            folderName: "[CP] Sounds of the Valley",
            relativePath: "[CP] Sounds of the Valley",
            manifest: parsedManifest(uniqueId: "Juanpa98ar.Source.SotV",
                                     name: "[CP] Sounds of the Valley",
                                     version: "4.0.0"),
            hasConfigFiles: false, dependencies: [], dependencyDetails: [],
            existingVersion: nil)
        let selection = InstallSelection(modId: detected.id, selected: true,
                                         conflictResolution: .overwriteWithBackup)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [detected],
                                            gameDir: env.gameDir, existingMods: [occupant])

        // Le remplacement a bien eu lieu, à la place de l'occupant (en pause).
        #expect(written.count == 1)
        let expected = env.modsDir.appendingPathComponent(".[CP] Sounds of the Valley").path
        #expect(written.first?.path == expected,
                "l'occupant était en pause : l'installé arrive en pause")
        #expect(try String(contentsOfFile: (expected as NSString).appendingPathComponent("data.txt"),
                           encoding: .utf8) == "le nouveau")

        // Et la config de l'utilisateur a survécu à l'écrasement.
        let config = try String(contentsOfFile: (expected as NSString)
            .appendingPathComponent("config.json"), encoding: .utf8)
        #expect(config.contains("OldConfig"),
                "le config.json de l'occupant doit être préservé")
        let fr = try String(contentsOfFile: (expected as NSString)
            .appendingPathComponent("i18n/fr.json"), encoding: .utf8)
        #expect(fr.contains("Bonjour"))
    }

    /// Résolution `.rename` : le comportement du neuf, inchangé — un nom
    /// horodaté, l'écart annoncé, l'occupant intact. Le cas voisin qui ne
    /// doit **pas** fusionner avec l'écrasement : décaler n'a jamais détruit
    /// personne, et ne doit toujours pas.
    @Test func renameResolutionKeepsBothAliveUnderDistinctNames() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(base: env.modsDir, relativePath: ".[CP] Sounds of the Valley",
                          uniqueId: "Juanpa98ar.SotV", name: "[CP] Sounds of the Valley",
                          version: "3.1.0", extraContent: "l'original de Liana")
        let occupant = modItem(folderName: "[CP] Sounds of the Valley",
                               uniqueId: "Juanpa98ar.SotV", version: "3.1.0",
                               isEnabled: false)

        try makeModFolder(base: env.tempExtractDir, relativePath: "[CP] Sounds of the Valley",
                          uniqueId: "Juanpa98ar.Source.SotV", name: "[CP] Sounds of the Valley",
                          version: "4.0.0", extraContent: "le nouveau")
        let detected = DetectedMod(
            folderName: "[CP] Sounds of the Valley",
            relativePath: "[CP] Sounds of the Valley",
            manifest: parsedManifest(uniqueId: "Juanpa98ar.Source.SotV",
                                     name: "[CP] Sounds of the Valley",
                                     version: "4.0.0"),
            hasConfigFiles: false, dependencies: [], dependencyDetails: [],
            existingVersion: nil)
        let selection = InstallSelection(modId: detected.id, selected: true,
                                         conflictResolution: .rename)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [detected],
                                            gameDir: env.gameDir, existingMods: [occupant])

        // L'occupant est intact, là où tous les magasins persistés le
        // cherchent (`ModItem.id` est le nom de dossier).
        let occupantFile = env.modsDir
            .appendingPathComponent(".[CP] Sounds of the Valley/data.txt")
        #expect(try String(contentsOf: occupantFile, encoding: .utf8) == "l'original de Liana")

        // Le nouveau vit sous un nom horodaté, l'écart annoncé à la vue.
        #expect(written.count == 1)
        let newPath = try #require(written.first?.path)
        #expect(newPath != occupantFile.deletingLastPathComponent().path)
        #expect((newPath as NSString).lastPathComponent.hasPrefix(".[CP] Sounds of the Valley_"))
        #expect(try String(contentsOfFile: (newPath as NSString).appendingPathComponent("data.txt"),
                           encoding: .utf8) == "le nouveau")
        #expect(written.first?.displacedFrom == "[CP] Sounds of the Valley")

        // Exactement deux dossiers : personne n'a disparu.
        #expect(try FileManager.default.contentsOfDirectory(atPath: env.modsDir.path).count == 2)
    }

    /// Résolution `.skip` sur un nom pris : **rien ne s'installe**. Le choix
    /// était perdu — la branche skip ne vivait que derrière un existant
    /// d'identifiant, et le mod s'installait quand même au nom pris.
    @Test func skipResolutionInstallsNothing() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(base: env.modsDir, relativePath: ".[CP] Sounds of the Valley",
                          uniqueId: "Juanpa98ar.SotV", name: "[CP] Sounds of the Valley",
                          version: "3.1.0", extraContent: "l'original de Liana")
        let occupant = modItem(folderName: "[CP] Sounds of the Valley",
                               uniqueId: "Juanpa98ar.SotV", version: "3.1.0",
                               isEnabled: false)

        try makeModFolder(base: env.tempExtractDir, relativePath: "[CP] Sounds of the Valley",
                          uniqueId: "Juanpa98ar.Source.SotV", name: "[CP] Sounds of the Valley",
                          version: "4.0.0", extraContent: "le nouveau")
        let detected = DetectedMod(
            folderName: "[CP] Sounds of the Valley",
            relativePath: "[CP] Sounds of the Valley",
            manifest: parsedManifest(uniqueId: "Juanpa98ar.Source.SotV",
                                     name: "[CP] Sounds of the Valley",
                                     version: "4.0.0"),
            hasConfigFiles: false, dependencies: [], dependencyDetails: [],
            existingVersion: nil)
        let selection = InstallSelection(modId: detected.id, selected: true,
                                         conflictResolution: .skip)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        let written = try installer.install(from: env.tempExtractDir, to: env.modsDisabledDir.path,
                                            selections: [selection], detectedMods: [detected],
                                            gameDir: env.gameDir, existingMods: [occupant])

        #expect(written.isEmpty, "skip : aucun dossier ne doit être posé")
        let occupantFile = env.modsDir
            .appendingPathComponent(".[CP] Sounds of the Valley/data.txt")
        #expect(try String(contentsOf: occupantFile, encoding: .utf8) == "l'original de Liana")
        // Ni occupant décalé, ni dossier horodaté à côté : Mods/ n'a pas bougé.
        #expect(try FileManager.default.contentsOfDirectory(atPath: env.modsDir.path)
            == [".[CP] Sounds of the Valley"])
    }
}
