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

    /// X136 — StardewOptimizer 1.0.0 → 3.0.3 sur le parc (2026-10-14) : le
    /// `config.json` installé est celui que l'auteur livrait en 1.0.0, octet
    /// pour octet (SHA-256 `d38c4ba7…`, manifeste Nexus 186155). Jamais modifié,
    /// il ne porte aucun réglage : garder lui faisait tourner les défauts
    /// abandonnés par l'auteur. Le neuf le remplace, et le bilan le dit.
    @Test func anUntouchedShippedConfigTakesTheNewOne() {
        let result = plan(installed: ["config.json": "d38c4ba7", "StardewOptimizer.dll": "dll1"],
                          new: ["config.json": "cfg303", "StardewOptimizer.dll": "dll303"],
                          versions: [version(["config.json": "d38c4ba7", "StardewOptimizer.dll": "dll1"])],
                          installedVersion: "3.0.3")
        #expect(result.decisions["config.json"] == .takeNewDefaultConfig)
        #expect(!result.critical.contains("config.json"))
        #expect(result.report.replacedDefaultConfigs == ["config.json"])
        // Le journal local décrit l'archive livrée : il prouve aussi bien.
        let local = plan(installed: ["config.json": "d38c4ba7"], new: ["config.json": "cfg303"],
                         versions: [version(["config.json": "d38c4ba7"], local: true)])
        #expect(local.decisions["config.json"] == .takeNewDefaultConfig)
    }

    /// Les cas voisins, qui ne doivent **pas** bouger : réglé à la main, même
    /// fichier que le neuf, plus livré du tout, et sans aucune référence.
    @Test func everyOtherConfigIsStillKept() {
        let edited = plan(installed: ["config.json": "mine"], new: ["config.json": "cfg2"],
                          versions: [version(["config.json": "cfg1"])])
        #expect(edited.decisions["config.json"] == .keepConfig)
        let same = plan(installed: ["config.json": "cfg1"], new: ["config.json": "cfg1"],
                        versions: [version(["config.json": "cfg1"])])
        #expect(same.decisions["config.json"] == .keepConfig)
        let notShipped = plan(installed: ["config.json": "cfg1"], new: ["a.dll": "x"],
                              versions: [version(["config.json": "cfg1"])])
        #expect(notShipped.decisions["config.json"] == .keepConfig)
        let unknown = plan(installed: ["config.json": "cfg1"], new: ["config.json": "cfg2"], versions: [])
        #expect(unknown.decisions["config.json"] == .keepConfig)
        // Un pack : le `config.json` d'un composant suit la même règle, par chemin.
        let nested = plan(installed: ["Core/config.json": "mine"], new: ["Core/config.json": "cfg2"],
                          versions: [version(["Core/config.json": "cfg1"])])
        #expect(nested.decisions["Core/config.json"] == .keepConfig)
        #expect(edited.report.replacedDefaultConfigs.isEmpty)
    }

    /// Un journal d'avant X136 se relit : le champ absent vaut vide.
    @Test func anOlderReportWithoutTheFieldStillDecodes() throws {
        let old = #"{"removedGhosts":["a.png"],"nexusIncomplete":false}"#
        let report = try JSONDecoder().decode(UpdateTriageReport.self, from: Data(old.utf8))
        #expect(report.removedGhosts == ["a.png"] && report.replacedDefaultConfigs.isEmpty)
        var fresh = UpdateTriageReport()
        fresh.replacedDefaultConfigs = ["config.json"]
        let back = try JSONDecoder().decode(UpdateTriageReport.self, from: JSONEncoder().encode(fresh))
        #expect(back.replacedDefaultConfigs == ["config.json"])
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

    @Test func withoutReferenceAFolderFormTranslationIsKeptToo() {
        // SMAPI 4 : `i18n/fr/gui.json`. Remplacée jusqu'ici, comme un asset.
        let result = plan(installed: ["i18n/fr/gui.json": "mine", "i18n/default/gui.json": "old"],
                          new: ["i18n/fr/gui.json": "author", "i18n/default/gui.json": "new"], versions: [])
        #expect(result.decisions["i18n/fr/gui.json"] == .keepUnverifiedTranslation)
        #expect(result.decisions["i18n/default/gui.json"] == .replaceUnverified)
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
