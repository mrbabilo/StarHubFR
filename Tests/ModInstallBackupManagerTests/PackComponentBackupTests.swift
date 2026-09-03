import Foundation
import Testing
@testable import StarHubTHCore

/// **Un composant de pack n'a pas d'état à lui.**
///
/// Le point ne vit que sur l'entrée de premier niveau : `physicalFolderName`
/// vaut `(isEnabled ? "" : ".") + folderName`, et le scan classe l'entrée
/// racine puis fait hériter cet état à tous ses composants
/// (`scanEntryForMods`, appelé avec l'`isEnabled` du dossier de tête). Le
/// sous-parcours passe `.skipsHiddenFiles` : un enfant préfixé d'un point,
/// lui, n'existe pour personne.
///
/// Mesuré sur le parc le 2026-09-03 : **869 dossiers pointés** au premier
/// niveau, dont beaucoup contiennent des composants — et **aucun** composant
/// pointé au second niveau (le seul dossier trouvé est un `.config`). La
/// forme physique d'un composant en pause est donc `.Pack/Composant`, jamais
/// `Pack/.Composant`.
///
/// Ces tests portent sur ce que la restauration en tire : elle doit rendre le
/// composant **au pack qui est là**, sans en fabriquer un second exemplaire.
@Suite struct PackComponentBackupTests {

    /// Sauvegarde un composant, puis supprime son dossier : l'état d'où part
    /// toute restauration qui a un sens.
    private func backupThenDelete(_ env: TestEnvironment, physicalPath: String,
                                  logicalFolderName: String) throws -> ModInstallBackup {
        let dir = env.modsDir.appendingPathComponent(physicalPath, isDirectory: true)
        try writeTestFile(in: dir, filename: "content.txt", content: "v1")
        try writeManifest(in: dir, uniqueId: "test.component", name: "Component")

        let mod = makeTestMod(uniqueId: "test.component", name: "Component",
                              folderName: logicalFolderName,
                              isEnabled: !physicalPath.hasPrefix("."))
        let backup = try env.manager.createBackup(for: mod, gameDir: env.gameDir,
                                                  reason: .beforeInstall)
        try FileManager.default.removeItem(at: dir)
        return backup
    }

    @Test func aDeletedComponentGoesBackIntoTheLivePack() throws {
        // Le pack est installé et actif, son voisin tourne ; seul le composant
        // manque. Le rendre ailleurs que dans ce pack revient à en fabriquer
        // un second — ce que la documentation de `restoreBackup` interdit
        // explicitement, et que le scan verrait comme deux entrées de même
        // `folderName`.
        let env = TestEnvironment()
        defer { env.cleanup() }

        let sibling = env.modsDir.appendingPathComponent("Parchment/[SMAPI] Parchment", isDirectory: true)
        try writeTestFile(in: sibling, filename: "sibling.txt")
        let backup = try backupThenDelete(env, physicalPath: "Parchment/[CP] Example",
                                          logicalFolderName: "Parchment/[CP] Example")

        let report = try env.manager.restoreBackup(backup, gameDir: env.gameDir)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: env.modsDir.appendingPathComponent("Parchment/[CP] Example/content.txt").path))
        // Aucun pack jumeau : c'est tout l'enjeu.
        #expect(!fm.fileExists(atPath: env.modsDir.appendingPathComponent(".Parchment").path))
        #expect(modsFolderEntries(env) == ["Parchment"])
        // Et le voisin n'a pas bougé.
        #expect(fm.fileExists(atPath: sibling.appendingPathComponent("sibling.txt").path))
        // Le compte rendu dit la vérité : dans un pack actif, le composant
        // est actif — il n'y a pas d'autre forme possible pour lui.
        #expect(report.landedEnabled)
        #expect(report.destinationPath == env.modsDir.appendingPathComponent("Parchment/[CP] Example").path)
    }

    @Test func aDeletedComponentOfAPausedPackGoesBackIntoIt() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let sibling = env.modsDir.appendingPathComponent(".Parchment/[SMAPI] Parchment", isDirectory: true)
        try writeTestFile(in: sibling, filename: "sibling.txt")
        let backup = try backupThenDelete(env, physicalPath: ".Parchment/[CP] Example",
                                          logicalFolderName: "Parchment/[CP] Example")

        let report = try env.manager.restoreBackup(backup, gameDir: env.gameDir)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: env.modsDir.appendingPathComponent(".Parchment/[CP] Example/content.txt").path))
        #expect(!fm.fileExists(atPath: env.modsDir.appendingPathComponent("Parchment").path))
        #expect(modsFolderEntries(env) == [".Parchment"])
        #expect(!report.landedEnabled)
    }

    @Test func aComponentWhosePackIsGoneComesBackPaused() throws {
        // Plus rien du pack sur le disque : le composant revient comme toute
        // nouvelle installation, en pause, à l'utilisateur de l'activer.
        let env = TestEnvironment()
        defer { env.cleanup() }

        let backup = try backupThenDelete(env, physicalPath: "Parchment/[CP] Example",
                                          logicalFolderName: "Parchment/[CP] Example")
        try FileManager.default.removeItem(at: env.modsDir.appendingPathComponent("Parchment"))

        let report = try env.manager.restoreBackup(backup, gameDir: env.gameDir)

        #expect(FileManager.default.fileExists(
            atPath: env.modsDir.appendingPathComponent(".Parchment/[CP] Example/content.txt").path))
        #expect(modsFolderEntries(env) == [".Parchment"])
        #expect(!report.landedEnabled)
    }

    /// Rendre un composant **dans** un pack existant, c'est écrire dans un
    /// dossier que l'app n'avait jamais écrit. Les archives restituent leurs
    /// modes : sur le parc, un seul dossier de tête est en lecture seule — et
    /// c'est un pack, `.[CP] Toothless Pet`, avec deux composants. Sans
    /// ouverture des droits, le correctif ci-dessus troquerait un mauvais
    /// emplacement contre un échec pur et simple.
    @Test func aReadOnlyPackStillAcceptsItsComponentBack() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let sibling = env.modsDir.appendingPathComponent("Toothless/[CP] Sibling", isDirectory: true)
        try writeTestFile(in: sibling, filename: "sibling.txt")
        let backup = try backupThenDelete(env, physicalPath: "Toothless/[CP] Example",
                                          logicalFolderName: "Toothless/[CP] Example")

        let packRoot = env.modsDir.appendingPathComponent("Toothless", isDirectory: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555],
                                              ofItemAtPath: packRoot.path)

        let report = try env.manager.restoreBackup(backup, gameDir: env.gameDir)

        #expect(FileManager.default.fileExists(
            atPath: packRoot.appendingPathComponent("[CP] Example/content.txt").path))
        #expect(report.landedEnabled)
        // Le décompte est fait **dans** la fenêtre de droits ouverts, mais il
        // parcourt un dossier redevenu 0555 juste après : un dossier se
        // traverse avec `x`, pas avec `w`. Sans ce contrôle, un compte rendu
        // annonçant « 0 fichier » après une restauration réussie passerait.
        #expect(report.fileCount == 2)
        // Et le pack est rendu tel qu'on l'a trouvé : un mod reste comme son
        // auteur l'a empaqueté.
        let mode = (try FileManager.default.attributesOfItem(atPath: packRoot.path)[.posixPermissions]
            as? NSNumber)?.uint16Value
        #expect(mode == 0o555)
    }

    // MARK: - Suppression

    /// Le dossier horodaté d'une sauvegarde est l'enfant direct de `backups/`,
    /// pas le parent du dossier sauvegardé : pour un composant, le parent
    /// n'est que la coquille du pack.
    ///
    /// Mesuré sur le magasin réel le 2026-09-03 : **1 262 dossiers horodatés
    /// sur disque pour 922 entrées d'index**, soit **340 coquilles orphelines**
    /// — invisibles dans l'app, qu'aucun chemin ne peut plus supprimer. 373
    /// des 922 entrées restantes en produiraient une de plus à leur
    /// suppression.
    @Test func deletingAComponentBackupLeavesNoEmptyShell() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let dir = env.modsDir.appendingPathComponent("Parchment/[CP] Example", isDirectory: true)
        try writeTestFile(in: dir, filename: "content.txt")
        let mod = makeTestMod(folderName: "Parchment/[CP] Example")
        let backup = try env.manager.createBackup(for: mod, gameDir: env.gameDir, reason: .beforeInstall)

        try env.manager.deleteBackup(backup)

        #expect(env.manager.loadBackups().isEmpty)
        let remaining = (try? FileManager.default.contentsOfDirectory(
            atPath: env.manager.backupsDirectory.path)) ?? []
        #expect(remaining.filter { $0 != ".DS_Store" }.isEmpty)
    }

    @Test func deletingOneComponentBackupSparesAnother() throws {
        // La garantie qui rend la règle sûre : chaque sauvegarde a son propre
        // dossier horodaté (suffixe UUID), donc remonter jusqu'à lui ne peut
        // jamais emporter la sauvegarde d'à côté.
        let env = TestEnvironment()
        defer { env.cleanup() }

        for pack in ["Parchment", "FruitTrees"] {
            let dir = env.modsDir.appendingPathComponent("\(pack)/[CP] Example", isDirectory: true)
            try writeTestFile(in: dir, filename: "content.txt", content: pack)
        }
        let first = try env.manager.createBackup(
            for: makeTestMod(folderName: "Parchment/[CP] Example"),
            gameDir: env.gameDir, reason: .beforeInstall)
        let second = try env.manager.createBackup(
            for: makeTestMod(folderName: "FruitTrees/[CP] Example"),
            gameDir: env.gameDir, reason: .beforeInstall)

        try env.manager.deleteBackup(first)

        #expect(env.manager.loadBackups().map(\.id) == [second.id])
        #expect(FileManager.default.fileExists(atPath: second.backupPath + "/content.txt"))
    }

    // MARK: - Ménage

    /// `deleteBackup` répare les droits avant de supprimer (les sauvegardes
    /// héritent des permissions du mod copié, et le parc en compte en lecture
    /// seule) ; `cleanupOldBackups` faisait la même suppression sans cette
    /// réparation. Deux sauvegardes du magasin réel sont dans ce cas : le
    /// ménage automatique les repousse indéfiniment.
    @Test func cleanupRemovesABackupWhoseFolderIsReadOnly() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let dir = env.modsDir.appendingPathComponent("ReadOnlyMod", isDirectory: true)
        try writeTestFile(in: dir, filename: "content.txt")
        let fresh = try env.manager.createBackup(for: makeTestMod(folderName: "ReadOnlyMod"),
                                                 gameDir: env.gameDir, reason: .beforeInstall)

        // La même sauvegarde, mais datée d'il y a un an : hors fenêtre de 30
        // jours, et repoussée sous le plancher des 5 plus récentes. Le
        // compagnon du même mois est là parce que la rétention garde la plus
        // récente de chaque mois au-delà de 30 jours — sans lui, l'unique
        // ancienne serait protégée à ce titre et le ménage n'essaierait rien.
        let yearAgo = Date().addingTimeInterval(-365 * 24 * 3600)
        let old = ModInstallBackup(timestamp: yearAgo,
                                   originalFolderName: "ReadOnlyMod",
                                   backupPath: fresh.backupPath,
                                   modMetadata: ModMetadata(name: "ReadOnlyMod", version: "1.0.0",
                                                            author: "Test", uniqueId: "test.mod"),
                                   reason: .beforeInstall)
        var filler = [old, makeFakeBackup(timestamp: yearAgo.addingTimeInterval(3600),
                                          folderName: "SameMonthKeeper")]
        for i in 0..<5 {
            filler.append(makeFakeBackup(timestamp: Date().addingTimeInterval(TimeInterval(-i)),
                                         folderName: "Filler\(i)"))
        }
        env.manager.seedIndexForTesting(with: filler)

        // Les droits d'un mod du parc : lecture et parcours, pas d'écriture —
        // impossible d'y délier un fichier tant qu'on ne les rouvre pas.
        try FileManager.default.setAttributes([.posixPermissions: 0o555],
                                              ofItemAtPath: fresh.backupPath)

        let deleted = env.manager.cleanupOldBackups()

        #expect(deleted >= 1)
        #expect(!FileManager.default.fileExists(atPath: fresh.backupPath))
        #expect(!env.manager.loadBackups().contains { $0.id == old.id })
    }
}
