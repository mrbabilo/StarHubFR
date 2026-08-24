import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct FileRecoveryRulesTests {

    /// Le seul signal parfaitement sûr : le fichier n'est plus là. Mesuré sur
    /// le parc réel le 2026-08-24 — **10 `i18n/fr.json`** présents en
    /// sauvegarde et disparus de l'installé, dix traductions perdues à une
    /// mise à jour près.
    @Test func aFileThatIsGoneFromTheInstallIsRecoverable() {
        let reason = FileRecoveryRules.reason(installedKeys: nil, backupKeys: ["a", "b"])

        #expect(reason == .absentFromInstall)
    }

    /// Le second signal sûr : le fichier est là, mais la sauvegarde porte des
    /// clés qu'il n'a plus. Mesuré : un `config.json` dans ce cas sur le parc.
    @Test func keysPresentOnlyInTheBackupAreRecoverable() {
        let reason = FileRecoveryRules.reason(installedKeys: ["a"], backupKeys: ["a", "b", "c"])

        #expect(reason == .keysLostSinceBackup(["b", "c"]))
    }

    /// **Le cas qu'il ne faut pas confondre avec une perte.** Un `config.json`
    /// différent de sa sauvegarde est le cas *normal* : l'utilisateur a réglé
    /// le mod depuis. Proposer la récupération ici écraserait des réglages
    /// voulus — la faute est plus grave que l'oubli.
    @Test func aFileWhoseValuesChangedIsNotALoss() {
        let reason = FileRecoveryRules.reason(installedKeys: ["a", "b"], backupKeys: ["a", "b"])

        #expect(reason == nil)
    }

    /// Un fichier installé plus riche que sa sauvegarde n'a rien perdu.
    @Test func aFileThatGainedKeysIsNotALoss() {
        let reason = FileRecoveryRules.reason(installedKeys: ["a", "b", "c"], backupKeys: ["a"])

        #expect(reason == nil)
    }

    /// L'ordre des clés perdues est celui de la sauvegarde : c'est l'ordre du
    /// fichier que l'utilisateur va relire avant d'écrire.
    @Test func lostKeysKeepTheBackupsOrder() {
        let reason = FileRecoveryRules.reason(installedKeys: [], backupKeys: ["z", "a", "m"])

        #expect(reason == .keysLostSinceBackup(["z", "a", "m"]))
    }

    /// Une sauvegarde vide ne prouve rien : ne rien proposer plutôt que de
    /// proposer d'écraser par du vide.
    @Test func anEmptyBackupFileIsNeverProposedOverAnExistingFile() {
        #expect(FileRecoveryRules.reason(installedKeys: ["a"], backupKeys: []) == nil)
    }
}

@Suite struct RecoverableFileScannerTests {

    private func backup(_ folder: String, at path: String, days: Int = 0) -> ModInstallBackup {
        ModInstallBackup(timestamp: Date().addingTimeInterval(TimeInterval(-days * 86_400)),
                         originalFolderName: folder,
                         backupPath: path,
                         modMetadata: ModMetadata(name: folder, version: "1.0.0",
                                                  author: "Auteur", uniqueId: folder),
                         reason: .beforeUpdate)
    }

    /// Le cas nominal : une traduction française qui n'existe plus que dans la
    /// sauvegarde.
    @Test func aTranslationLostInAnUpdateIsFound() {
        let files: [String: [String]] = [
            "/bk/Mod/i18n/fr.json": ["clé"],
            "/mods/Mod/manifest.json": []
        ]

        let found = RecoverableFileScanner.scan(
            backups: [backup("Mod", at: "/bk/Mod")],
            installedFolder: { _ in "/mods/Mod" },
            jsonKeys: { files[$0] })

        #expect(found.count == 1)
        #expect(found.first?.relativePath == "i18n/fr.json")
        #expect(found.first?.folderName == "Mod")
        #expect(found.first?.backupPath == "/bk/Mod/i18n/fr.json")
        #expect(found.first?.reason == .absentFromInstall)
    }

    /// Un mod qui n'est plus installé du tout ne relève pas d'ici : c'est la
    /// restauration complète qui répond, pas la récupération d'un fichier.
    @Test func aModThatIsNoLongerInstalledIsSkipped() {
        let found = RecoverableFileScanner.scan(
            backups: [backup("Mod", at: "/bk/Mod")],
            installedFolder: { _ in nil },
            jsonKeys: { _ in ["clé"] })

        #expect(found.isEmpty)
    }

    /// Un fichier absent **des deux côtés** n'est pas une perte.
    @Test func aFileMissingFromTheBackupTooIsNotAnOffer() {
        let found = RecoverableFileScanner.scan(
            backups: [backup("Mod", at: "/bk/Mod")],
            installedFolder: { _ in "/mods/Mod" },
            jsonKeys: { _ in nil })

        #expect(found.isEmpty)
    }

    /// Un dossier a plusieurs sauvegardes : seule **la plus récente** est
    /// examinée. Les anciennes décrivent un état que l'utilisateur a déjà
    /// dépassé, et le parc en compte jusqu'à une dizaine par mod.
    @Test func onlyTheMostRecentBackupOfAFolderIsExamined() {
        let files: [String: [String]] = ["/bk/ancien/i18n/fr.json": ["vieille"]]

        let found = RecoverableFileScanner.scan(
            backups: [backup("Mod", at: "/bk/ancien", days: 10),
                      backup("Mod", at: "/bk/recent", days: 1)],
            installedFolder: { _ in "/mods/Mod" },
            jsonKeys: { files[$0] })

        #expect(found.isEmpty)
    }

    /// Deux dossiers différents restent deux mods : le même `UniqueID` installé
    /// deux fois est un cas réel du parc.
    @Test func twoFoldersAreScannedIndependently() {
        let files: [String: [String]] = [
            "/bk/A/i18n/fr.json": ["a"],
            "/bk/B/config.json": ["b"]
        ]

        let found = RecoverableFileScanner.scan(
            backups: [backup("A", at: "/bk/A"), backup("B", at: "/bk/B")],
            installedFolder: { "/mods/\($0)" },
            jsonKeys: { files[$0] })

        #expect(Set(found.map(\.folderName)) == ["A", "B"])
    }

    /// Les fichiers sont rendus dans un ordre stable — deux affichages
    /// successifs ne se réordonnent pas sous les yeux de l'utilisateur.
    @Test func resultsAreInAStableOrder() {
        let files: [String: [String]] = [
            "/bk/Z/i18n/fr.json": ["a"],
            "/bk/A/i18n/fr.json": ["a"],
            "/bk/A/config.json": ["a"]
        ]

        let found = RecoverableFileScanner.scan(
            backups: [backup("Z", at: "/bk/Z"), backup("A", at: "/bk/A")],
            installedFolder: { "/mods/\($0)" },
            jsonKeys: { files[$0] })

        #expect(found.map { "\($0.folderName)/\($0.relativePath)" }
                == ["A/config.json", "A/i18n/fr.json", "Z/i18n/fr.json"])
    }

    /// Le nom du mod voyage avec le fichier : « [CP] Aquatic Sea Fish » se lit,
    /// pas son dossier.
    @Test func theModNameTravelsWithTheFile() {
        let files: [String: [String]] = ["/bk/Mod/i18n/fr.json": ["a"]]

        let found = RecoverableFileScanner.scan(
            backups: [ModInstallBackup(timestamp: Date(),
                                       originalFolderName: "Mod",
                                       backupPath: "/bk/Mod",
                                       modMetadata: ModMetadata(name: "Un joli nom", version: "1.0.0",
                                                                author: "Auteur", uniqueId: "a.mod"),
                                       reason: .beforeUpdate)],
            installedFolder: { _ in "/mods/Mod" },
            jsonKeys: { files[$0] })

        #expect(found.first?.modName == "Un joli nom")
    }
}
