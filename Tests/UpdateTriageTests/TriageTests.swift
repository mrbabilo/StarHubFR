import Foundation
import Testing
@testable import StarHubTHCore

struct TriageTests {
    private typealias Decision = UpdateFileTriage.Decision

    // MARK: - Le parc réel

    /// Wildroot 1.4.1 → 1.4.2, rejoué sur la sauvegarde « avant mise à jour »
    /// et les manifestes Nexus : les 23 assets identiques à la 1.3.5 et les
    /// deux `translations/*.json` de 1.2.0 hotfix4 partent ; `zh.json`, resté
    /// celui de l'auteur, prend la version neuve.
    @Test func wildrootDropsItsGhostsAndKeepsTheUsersFiles() throws {
        let plan = try Fixture.triageCase("wildroot").plan()
        #expect(plan.report.removedGhosts.count == 25)
        #expect(plan.decisions["assets/Items/Tools/rift_axe.png"] == .removeGhost)
        #expect(plan.decisions["translations/es.json"] == .removeGhost)
        #expect(plan.decisions["i18n/zh.json"] == .takeNew)
        #expect(plan.decisions["i18n/fr.json"] == .keepLocal(authorNowShips: false))
        #expect(plan.decisions["config.json"] == .keepConfig)
        #expect(plan.report.keptRetouches.isEmpty)
        #expect(plan.respectedDeletions.isEmpty)
    }

    /// FOTP 3.4.19 réinstallé : le code source et la seconde DLL d'une
    /// ancienne version partent ; les fichiers que le mod écrit restent.
    @Test func fotpDropsTheSourceTreeAndTheSecondDll() throws {
        let plan = try Fixture.triageCase("fotp").plan()
        #expect(plan.report.removedGhosts.count == 47)
        #expect(plan.decisions["bin/Release/net6.0/FOTP.dll"] == .removeGhost)
        #expect(plan.decisions["ModEntry.cs"] == .removeGhost)
        #expect(plan.report.keptLocal == ["ConfigData/reference.pet.config.json",
                                          "ConfigData/reference.pet.diet.json",
                                          "ConfigData/reference.pet.hatoffset.json",
                                          "ModConfig.json"])
        #expect(plan.decisions["i18n/zh.json"] == .takeNew)
        #expect(plan.decisions["i18n/es.json"] == .takeNew)
    }

    /// ItemBags : aucune version au format récent. Les 24 sacs posés à la
    /// main dans `Modded Bags/` restent — pas les 18 échantillons que
    /// l'auteur livre à côté, sous `Samples (…)/`, aux mêmes octets mais à un
    /// autre chemin — et rien n'est retiré.
    @Test func itemBagsKeepsEveryBag() throws {
        let plan = try Fixture.triageCase("itembags").plan()
        #expect(plan.report.removedGhosts.isEmpty)
        let bags = plan.report.keptLocal.filter { $0.hasPrefix("assets/Modded Bags/") }
        #expect(bags.count == 24)
        #expect(!bags.contains { $0.contains("Samples") })
        #expect(Set(plan.report.keptLocal).subtracting(bags)
                == ["bagconfig.json", "i18n/fr.json.bak", "modded_items.json"])
        #expect(plan.decisions["assets/Modded Bags/Cloth and Colors Bag.json"]
                == .keepLocal(authorNowShips: false))
    }

    // MARK: - Les règles une à une

    private func version(_ files: [String: String], _ label: String = "1.0.0",
                         local: Bool = false) -> AuthorFileIndex.Version {
        .init(source: local ? .localHistory : .nexus(fileId: 1), version: label, files: files)
    }

    private func plan(installed: [String: String], new: [String: String],
                      versions: [AuthorFileIndex.Version], installedVersion: String = "1.0.0",
                      deposits: Set<String> = []) -> UpdateFileTriage.Plan {
        UpdateFileTriage.plan(installed: .init(hashes: installed), newArchive: .init(hashes: new),
                              index: AuthorFileIndex(versions: versions),
                              installedVersion: installedVersion, deposits: deposits)
    }

    @Test func aRetouchIsKeptAndSaysWhenTheAuthorChangedItToo() {
        let result = plan(installed: ["a.png": "mine", "b.png": "mine"],
                          new: ["a.png": "v1", "b.png": "v2"],
                          versions: [version(["a.png": "v1", "b.png": "v1"])])
        #expect(result.decisions["a.png"] == .keepRetouch(authorChanged: false))
        #expect(result.decisions["b.png"] == .keepRetouch(authorChanged: true))
        #expect(result.report.retouchesAuthorChanged == ["b.png"])
    }

    @Test func withoutReferenceAChangedFileTakesTheNewVersion() {
        let result = plan(installed: ["a.png": "mine", "i18n/fr.json": "mine"],
                          new: ["a.png": "v2", "i18n/fr.json": "author"], versions: [])
        #expect(result.decisions["a.png"] == .replaceUnverified)
        // Règle 7b : ta traduction reste, même si l'auteur en livre une.
        #expect(result.decisions["i18n/fr.json"] == .keepUnverifiedTranslation)
    }

    @Test func manifestAndCodeAlwaysTakeTheNewVersion() {
        let result = plan(installed: ["manifest.json": "mine", "Mod.dll": "mine", "content.json": "mine"],
                          new: ["manifest.json": "v2", "Mod.dll": "v2", "content.json": "v2"],
                          versions: [version(["manifest.json": "v1", "Mod.dll": "v1", "content.json": "v1"])])
        #expect(result.decisions["manifest.json"] == .replaceStructural)
        #expect(result.decisions["Mod.dll"] == .replaceStructural)
        #expect(result.decisions["content.json"] == .keepContentRetouch(authorChanged: true))
    }

    @Test func aFileTheAuthorNowShipsKeepsYourVersion() {
        let result = plan(installed: ["assets/extra.png": "mine"], new: ["assets/extra.png": "author"],
                          versions: [version(["manifest.json": "m"])])
        #expect(result.decisions["assets/extra.png"] == .keepLocal(authorNowShips: true))
        #expect(result.report.authorNowShips == ["assets/extra.png"])
    }

    @Test func depositsAreKeptWhateverTheArchiveSays() {
        let result = plan(installed: ["i18n/fr.json": "hub"], new: ["i18n/fr.json": "author"],
                          versions: [version(["i18n/fr.json": "hub"])], deposits: ["i18n/fr.json"])
        #expect(result.decisions["i18n/fr.json"] == .keepDeposit)
    }

    /// Le journal local dit ce qui avait été posé : ce qui manque au dossier
    /// a été supprimé par l'utilisateur, et ne revient pas.
    @Test func deletionsAreRespectedOnlyWithTheLocalHistory() {
        let local = plan(installed: ["a.png": "v1"], new: ["a.png": "v1", "b.png": "v2"],
                         versions: [version(["a.png": "v1", "b.png": "v1"], local: true)])
        #expect(local.respectedDeletions == ["b.png"])
        let nexus = plan(installed: ["a.png": "v1"], new: ["a.png": "v1", "b.png": "v2"],
                         versions: [version(["a.png": "v1", "b.png": "v1"])])
        #expect(nexus.respectedDeletions.isEmpty)
    }

    /// Un mod remplacé à la main depuis la dernière installation : le
    /// journal décrit une autre version, il ne sert pas de référence.
    @Test func aStaleLocalHistoryIsNoReference() {
        let result = plan(installed: ["a.png": "v2"], new: ["a.png": "v3", "b.png": "v3"],
                          versions: [version(["a.png": "v1", "b.png": "v1"], "1.0.0", local: true)],
                          installedVersion: "2.0.0")
        #expect(result.respectedDeletions.isEmpty)
        #expect(result.decisions["a.png"] == .replaceUnverified)
    }

    @Test func versionsCompareAsVersionsNotStrings() {
        let result = plan(installed: ["a.png": "mine"], new: ["a.png": "v2"],
                          versions: [version(["a.png": "v1"], "1.1")], installedVersion: "1.1.0")
        #expect(result.decisions["a.png"] == .keepRetouch(authorChanged: true))
    }

    @Test func pathsMatchWithoutCase() {
        let result = plan(installed: ["Assets/Old.png": "v1"], new: ["assets/new.png": "v2"],
                          versions: [version(["assets/old.png": "v1"])])
        #expect(result.decisions["Assets/Old.png"] == .removeGhost)
    }

    @Test func anUnreadableFileIsNeverFrozenNorRemoved() {
        let result = UpdateFileTriage.plan(
            installed: .init(hashes: [:], unreadable: ["a.png", "b.png"]),
            newArchive: .init(hashes: ["a.png": "v2"]), index: AuthorFileIndex(versions: []),
            installedVersion: "1.0.0", deposits: [])
        #expect(result.decisions["a.png"] == .replaceUnverified)
        #expect(result.decisions["b.png"] == .keepLocal(authorNowShips: false))
    }

    /// Non-régression A1-T7 : une donnée de partie n'est livrée par aucune
    /// version, elle reste.
    @Test func saveDataStays() {
        let result = plan(installed: ["data/essai_448486987_SaveData.save": "x", "data/default.json": "d1"],
                          new: ["data/default.json": "d2"],
                          versions: [version(["data/default.json": "d1"])])
        #expect(result.decisions["data/essai_448486987_SaveData.save"] == .keepLocal(authorNowShips: false))
        #expect(result.decisions["data/default.json"] == .takeNew)
    }

    @Test func criticalAndLocalSplitTheKeptFiles() {
        let result = plan(installed: ["config.json": "c", "save.dat": "s", "a.png": "mine"],
                          new: ["a.png": "v1"], versions: [version(["a.png": "v0"])])
        #expect(result.critical == ["a.png", "config.json"])
        #expect(result.local == ["save.dat"])
    }
}
