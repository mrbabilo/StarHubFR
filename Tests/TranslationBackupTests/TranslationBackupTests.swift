import Testing
import Foundation
@testable import StarHubTHCore

/// Retrouver une traduction française qu'une mise à jour de mod a effacée.
///
/// Le cas n'est pas théorique : sur le parc de référence, **16 mods** ont perdu
/// leur `fr.json` alors qu'une sauvegarde en contient encore un. Les auteurs ne
/// redistribuent pas toujours les traductions communautaires, et une mise à jour
/// remplace le dossier entier.
///
/// Les deux familles de sauvegarde ne rangent pas les fichiers pareil : une
/// sauvegarde d'installation copie le mod tel quel (`<mod>/i18n/fr.json`),
/// une sauvegarde de configuration met les fichiers préservés à plat
/// (`<mod>/fr.json`). Chercher sous le dossier du mod couvre les deux sans avoir
/// à les distinguer.
struct TranslationBackupFinderTests {
    private struct Backups {
        let root: URL
        init(files: [String], dates: [String: Date] = [:]) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("backups-\(UUID().uuidString)", isDirectory: true)
            for relative in files {
                let url = root.appendingPathComponent(relative)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try Data(#"{"a": "1"}"#.utf8).write(to: url)
                if let date = dates[relative] {
                    try FileManager.default.setAttributes([.modificationDate: date],
                                                          ofItemAtPath: url.path)
                }
            }
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func findsAFrenchFileInAnInstallBackup() throws {
        let backups = try Backups(files: ["2026-07-25_install/BetterInventory/i18n/fr.json"])
        defer { backups.cleanup() }
        let found = TranslationBackupFinder.mostRecentFrenchFile(
            forModFolder: "BetterInventory", inBackupRoots: [backups.root])
        #expect(found?.path.lastPathComponent == "fr.json")
    }

    @Test func findsAFrenchFileFlatInAConfigBackup() throws {
        // La sauvegarde de configuration ne recrée pas le dossier `i18n/`.
        let backups = try Backups(files: ["2026-07-23_backup/WhatDoesTrashBearWant/fr.json"])
        defer { backups.cleanup() }
        let found = TranslationBackupFinder.mostRecentFrenchFile(
            forModFolder: "WhatDoesTrashBearWant", inBackupRoots: [backups.root])
        #expect(found != nil)
    }

    @Test func picksTheMostRecentWhenSeveralExist() throws {
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = Date(timeIntervalSince1970: 1_800_000_000)
        let backups = try Backups(
            files: ["a_backup/Mod/i18n/fr.json", "b_backup/Mod/i18n/fr.json"],
            dates: ["a_backup/Mod/i18n/fr.json": old, "b_backup/Mod/i18n/fr.json": recent])
        defer { backups.cleanup() }
        let found = TranslationBackupFinder.mostRecentFrenchFile(
            forModFolder: "Mod", inBackupRoots: [backups.root])
        // La plus récente est la seule utile : les anciennes sont forcément
        // moins complètes ou moins à jour.
        #expect(found?.path.path.contains("b_backup") == true)
        #expect(found?.modifiedAt == recent)
    }

    @Test func doesNotMatchAModWhoseNameMerelyStartsTheSame() throws {
        // `BetterInventory` ne doit pas ramener le `fr.json` de
        // `BetterInventoryPlus` — ce sont deux mods différents.
        let backups = try Backups(files: ["b/BetterInventoryPlus/i18n/fr.json"])
        defer { backups.cleanup() }
        let found = TranslationBackupFinder.mostRecentFrenchFile(
            forModFolder: "BetterInventory", inBackupRoots: [backups.root])
        #expect(found == nil)
    }

    @Test func findsNothingWhenNoBackupHasIt() throws {
        let backups = try Backups(files: ["a/OtherMod/i18n/fr.json"])
        defer { backups.cleanup() }
        #expect(TranslationBackupFinder.mostRecentFrenchFile(
            forModFolder: "Mod", inBackupRoots: [backups.root]) == nil)
    }

    @Test func anAbsentBackupRootIsNotAnError() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString)")
        #expect(TranslationBackupFinder.mostRecentFrenchFile(
            forModFolder: "Mod", inBackupRoots: [missing]) == nil)
    }

    @Test func findsAComponentOfAPack() throws {
        // Le `folderName` d'un composant porte son pack : `Pack/Composant`.
        let backups = try Backups(files: ["a/Pack/Composant/i18n/fr.json"])
        defer { backups.cleanup() }
        let found = TranslationBackupFinder.mostRecentFrenchFile(
            forModFolder: "Pack/Composant", inBackupRoots: [backups.root])
        #expect(found != nil)
    }
}
