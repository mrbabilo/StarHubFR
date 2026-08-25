import Testing
import Foundation
@testable import StarHubTHCore

struct ManifestlessInstallerTests {
    private let fm = FileManager.default

    /// Un terrain jetable : l'archive dépliée, le mod hôte, le dossier de mise
    /// à l'abri.
    private func makeGround(archive: [String: String] = [:],
                            host: [String: String] = [:]) throws
        -> (extracted: URL, hostPath: URL, backups: URL) {
        let root = fm.temporaryDirectory.appendingPathComponent("mli-\(UUID().uuidString)")
        let extracted = root.appendingPathComponent("extracted")
        let hostPath = root.appendingPathComponent("Mods/Parchment")
        let backups = root.appendingPathComponent("backups")
        for (path, contents) in archive {
            let url = extracted.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try fm.createDirectory(at: hostPath, withIntermediateDirectories: true)
        for (path, contents) in host {
            let url = hostPath.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return (extracted, hostPath, backups)
    }

    private func plan(_ entries: [(String, String)],
                      kind: ManifestlessArchive.Kind = .translation) -> ManifestlessArchive.Plan {
        ManifestlessArchive.Plan(hostFolderName: "Parchment", kind: kind,
                                 entries: entries.map { .init(source: $0.0, destination: $0.1) })
    }

    private func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    @Test func aTranslationLandsInTheMod() throws {
        let g = try makeGround(archive: ["Parchment/i18n/fr.json": "{\"a\":\"traduit\"}"])
        let outcome = try ManifestlessInstaller.install(
            plan: plan([("Parchment/i18n/fr.json", "i18n/fr.json")]),
            extractedRoot: g.extracted, hostPath: g.hostPath, backupRoot: g.backups)
        #expect(outcome.written == ["i18n/fr.json"])
        #expect(outcome.replaced.isEmpty)
        #expect(read(g.hostPath.appendingPathComponent("i18n/fr.json")) == "{\"a\":\"traduit\"}")
    }

    /// **L'obligation qui rend la désinstallation possible.** Un mod livré avec
    /// son propre `fr.json` se retrouverait sans français du tout si on
    /// l'écrasait sans en garder copie.
    @Test func anOverwrittenFileIsPutSafeFirst() throws {
        let g = try makeGround(archive: ["Parchment/i18n/fr.json": "communautaire"],
                               host: ["i18n/fr.json": "livré par l'auteur"])
        let outcome = try ManifestlessInstaller.install(
            plan: plan([("Parchment/i18n/fr.json", "i18n/fr.json")]),
            extractedRoot: g.extracted, hostPath: g.hostPath, backupRoot: g.backups)
        let saved = try #require(outcome.replaced["i18n/fr.json"])
        #expect(read(URL(fileURLWithPath: saved)) == "livré par l'auteur")
        #expect(read(g.hostPath.appendingPathComponent("i18n/fr.json")) == "communautaire")
    }

    /// Une greffe crée les dossiers qui manquent — `assets/Modded Bags/`
    /// n'existe pas tant qu'aucun bagage n'a été ajouté.
    @Test func missingFoldersAreCreated() throws {
        let g = try makeGround(archive: ["Sac.json": "{}"])
        let outcome = try ManifestlessInstaller.install(
            plan: plan([("Sac.json", "assets/Modded Bags/Sac.json")], kind: .addon),
            extractedRoot: g.extracted, hostPath: g.hostPath, backupRoot: g.backups)
        #expect(outcome.written == ["assets/Modded Bags/Sac.json"])
        #expect(fm.fileExists(atPath: g.hostPath.appendingPathComponent("assets/Modded Bags/Sac.json").path))
    }

    /// **Le parc réel est en `0555` par endroits.** Sans ouverture temporaire
    /// des droits, le dépôt échouerait — c'est le piège qui avait déjà fait
    /// échouer les mises à jour de mods.
    @Test func aReadOnlyModFolderIsStillWritable() throws {
        let g = try makeGround(archive: ["Parchment/i18n/fr.json": "traduit"],
                               host: ["i18n/fr.json": "avant"])
        let i18n = g.hostPath.appendingPathComponent("i18n")
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: i18n.path)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: g.hostPath.path)

        _ = try ManifestlessInstaller.install(
            plan: plan([("Parchment/i18n/fr.json", "i18n/fr.json")]),
            extractedRoot: g.extracted, hostPath: g.hostPath, backupRoot: g.backups)
        #expect(read(g.hostPath.appendingPathComponent("i18n/fr.json")) == "traduit")

        // Les droits sont rendus tels qu'on les a trouvés : un mod reste comme
        // son auteur l'a empaqueté.
        let mode = (try fm.attributesOfItem(atPath: i18n.path))[.posixPermissions] as? NSNumber
        #expect(mode?.uint16Value == 0o555)
    }

    /// **Tout ou rien.** Un dépôt à moitié fait laisse un mod dans un état que
    /// personne n'a voulu : le second fichier manque, le premier est défait.
    @Test func aFailedInstallLeavesNothingBehind() throws {
        let g = try makeGround(archive: ["Parchment/i18n/fr.json": "traduit"],
                               host: ["i18n/fr.json": "avant"])
        #expect(throws: ManifestlessInstaller.InstallError.sourceMissing("Parchment/absent.json")) {
            try ManifestlessInstaller.install(
                plan: plan([("Parchment/i18n/fr.json", "i18n/fr.json"),
                            ("Parchment/absent.json", "assets/absent.json")]),
                extractedRoot: g.extracted, hostPath: g.hostPath, backupRoot: g.backups)
        }
        // Le fichier recouvert a repris sa place.
        #expect(read(g.hostPath.appendingPathComponent("i18n/fr.json")) == "avant")
    }

    @Test func aMissingHostIsRefusedBeforeAnythingIsWritten() throws {
        let g = try makeGround(archive: ["x.json": "{}"])
        let absent = g.hostPath.deletingLastPathComponent().appendingPathComponent("Fantome")
        #expect(throws: ManifestlessInstaller.InstallError.hostMissing("Fantome")) {
            try ManifestlessInstaller.install(plan: plan([("x.json", "x.json")]),
                                              extractedRoot: g.extracted,
                                              hostPath: absent, backupRoot: g.backups)
        }
    }

    // MARK: - Désinstallation

    @Test func uninstallingRemovesWhatWasAdded() throws {
        let g = try makeGround(archive: ["Sac.json": "{}"])
        let outcome = try ManifestlessInstaller.install(
            plan: plan([("Sac.json", "assets/Sac.json")], kind: .addon),
            extractedRoot: g.extracted, hostPath: g.hostPath, backupRoot: g.backups)
        let translation = InstalledTranslation(
            hostFolderName: "Parchment", nexusModId: 1, nexusName: "X", version: "1",
            updatedAt: nil, installedAt: Date(), files: outcome.written,
            replacedFiles: outcome.replaced)

        #expect(ManifestlessInstaller.uninstall(translation, hostPath: g.hostPath).isEmpty)
        #expect(!fm.fileExists(atPath: g.hostPath.appendingPathComponent("assets/Sac.json").path))
    }

    /// **Désinstaller, c'est rendre.** Le `fr.json` de l'auteur reprend sa
    /// place ; l'effacer laisserait le mod sans français du tout.
    @Test func uninstallingGivesBackWhatWasOverwritten() throws {
        let g = try makeGround(archive: ["Parchment/i18n/fr.json": "communautaire"],
                               host: ["i18n/fr.json": "livré par l'auteur"])
        let outcome = try ManifestlessInstaller.install(
            plan: plan([("Parchment/i18n/fr.json", "i18n/fr.json")]),
            extractedRoot: g.extracted, hostPath: g.hostPath, backupRoot: g.backups)
        let translation = InstalledTranslation(
            hostFolderName: "Parchment", nexusModId: 1, nexusName: "X", version: "1",
            updatedAt: nil, installedAt: Date(), files: outcome.written,
            replacedFiles: outcome.replaced)

        #expect(ManifestlessInstaller.uninstall(translation, hostPath: g.hostPath).isEmpty)
        #expect(read(g.hostPath.appendingPathComponent("i18n/fr.json")) == "livré par l'auteur")
    }

    /// Un fichier déjà disparu ne fait pas échouer la désinstallation : le but
    /// est qu'il ne soit plus là.
    @Test func uninstallingSomethingAlreadyGoneIsNotAFailure() throws {
        let g = try makeGround()
        let translation = InstalledTranslation(
            hostFolderName: "Parchment", nexusModId: 1, nexusName: "X", version: "1",
            updatedAt: nil, installedAt: Date(), files: ["i18n/fr.json"])
        #expect(ManifestlessInstaller.uninstall(translation, hostPath: g.hostPath).isEmpty)
    }
}
