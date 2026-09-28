import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T11 plan 2 — ce que « Nettoyer les anciens fichiers » propose.
struct LegacyFileCleanupTests {
    private typealias Cleanup = LegacyFileCleanup

    private func plan(_ outcome: Cleanup.Outcome) throws -> Cleanup.Plan {
        guard case .plan(let plan) = outcome else { Issue.record("plan attendu"); throw CancellationError() }
        return plan
    }

    // MARK: - Cas réels du parc

    @Test func wildrootProposesItsTwentyFiveGhostsAsIdentical() throws {
        let fixture = try Fixture.triageCase("wildroot")   // installé en 1.4.1
        let result = try plan(Cleanup.plan(installed: fixture.installedListing, index: fixture.index(),
                                           legacy: [], installedVersion: fixture.installedVersion,
                                           deposits: [], nexusIncomplete: false))
        #expect(result.reference == .nexusRecent)
        #expect(result.candidates.count == 25)
        #expect(result.candidates.allSatisfy { $0.certainty == .identical })
        let paths = Set(result.candidates.map(\.path))
        #expect(paths.contains("assets/Items/Tools/rift_axe.png"))
        // Identiques à des fichiers Nexus étiquetés « 14 », déposés avant la
        // 1.4.1 : l'étiquette ne dit rien, l'ordre de dépôt si.
        #expect(paths.contains("translations/es.json"))
        #expect(paths.contains("translations/pt.json"))
        #expect(!paths.contains("i18n/zh.json"))   // livré par la 1.4.1 : dans la référence
        #expect(!paths.contains("i18n/fr.json"))
        #expect(!paths.contains("config.json"))
    }

    @Test func fotpProposesNothingBecauseItsVersionShipsTheSourceTree() throws {
        // Le fichier Nexus 184318 (3.4.19) livre le code source : l'union des
        // fichiers de la version installée penche du côté sûr (spec).
        let fixture = try Fixture.triageCase("fotp")
        let result = try plan(Cleanup.plan(installed: fixture.installedListing, index: fixture.index(),
                                           legacy: [], installedVersion: fixture.installedVersion,
                                           deposits: [], nexusIncomplete: false))
        #expect(result.candidates.isEmpty)
    }

    @Test func itemBagsWithAnOldFormatReferenceKeepsEveryBag() throws {
        let fixture = try Fixture.triageCase("itembags")   // aucune version au format récent
        let real = try #require(NexusLegacyFileManifest.decode(Fixture.data("manifest-legacy-itembags-3.1.0.json")))
        var hashes = fixture.installed
        hashes["assets/old_icon.png"] = "0123456789abcdef"
        let installed = ModFolderHasher.Listing(hashes: hashes)
        let current = try #require(real.paths(matching: Set(installed.byKey.keys)))
        let result = try plan(Cleanup.plan(
            installed: installed, index: AuthorFileIndex(versions: []),
            legacy: [.init(fileId: 20, version: "3.1.0", paths: current),
                     .init(fileId: 10, version: "3.0.0", paths: ["manifest.json", "itembags.dll", "assets/old_icon.png"])],
            installedVersion: "3.1.0", deposits: [], nexusIncomplete: false))
        #expect(result.reference == .nexusLegacy)
        #expect(result.candidates.map(\.path) == ["assets/old_icon.png"])
        #expect(result.candidates.first?.certainty == .pathOnly)
    }

    // MARK: - Règles

    private func author(_ files: [String: String], _ version: String, _ fileId: Int) -> AuthorFileIndex.Version {
        .init(source: .nexus(fileId: fileId), version: version, files: files)
    }

    private func run(installed: [String: String], versions: [AuthorFileIndex.Version],
                     legacy: [Cleanup.LegacyVersion] = [], installedVersion: String = "1.0.0",
                     deposits: Set<String> = [], unreadable: [String] = []) throws -> Cleanup.Plan {
        try plan(Cleanup.plan(installed: .init(hashes: installed, unreadable: unreadable),
                              index: AuthorFileIndex(versions: versions), legacy: legacy,
                              installedVersion: installedVersion, deposits: deposits, nexusIncomplete: false))
    }

    @Test func withoutAnyReferenceNothingIsProposed() {
        let outcome = Cleanup.plan(installed: .init(hashes: ["old.png": "a"]),
                                   index: AuthorFileIndex(versions: [author(["old.png": "a"], "0.9.0", 1)]),
                                   legacy: [.init(fileId: 2, version: "0.8.0", paths: ["old.png"])],
                                   installedVersion: "1.0.0", deposits: [], nexusIncomplete: false)
        #expect(outcome == .noReference)
    }

    @Test func aFileOfTheInstalledVersionIsNeverProposedEvenRetouched() throws {
        let result = try run(installed: ["manifest.json": "m", "a.png": "retouched", "old.png": "o"],
                             versions: [author(["manifest.json": "m", "a.png": "a"], "1.0.0", 2),
                                        author(["manifest.json": "m0", "a.png": "a", "old.png": "o"], "0.9.0", 1)])
        #expect(result.candidates.map(\.path) == ["old.png"])
    }

    @Test func configManifestDepositsAndUnreadableAreNeverProposed() throws {
        let result = try run(
            installed: ["manifest.json": "m", "config.json": "c", "i18n/fr.json": "fr", "deposit.png": "d"],
            versions: [author(["manifest.json": "m"], "1.0.0", 2),
                       author(["config.json": "c", "i18n/fr.json": "fr", "deposit.png": "d",
                               "ghost.png": "g"], "0.9.0", 1)],
            deposits: ["deposit.png"], unreadable: ["ghost.png"])
        // i18n/fr.json identique à une version d'auteur : identique, proposé.
        #expect(result.candidates.map(\.path) == ["i18n/fr.json"])
    }

    @Test func aNestedModIsNeverProposed() throws {
        let result = try run(installed: ["manifest.json": "m", "[CP] Sub/manifest.json": "s",
                                         "[CP] Sub/old.png": "o", "old.png": "o"],
                             versions: [author(["manifest.json": "m"], "1.0.0", 2),
                                        author(["old.png": "o", "[cp] sub/old.png": "o"], "0.9.0", 1)])
        #expect(result.candidates.map(\.path) == ["old.png"])
    }

    @Test func anAuthorFileDepositedAfterTheReferenceIsNeverProposed() throws {
        // L'auteur a oublié de relever la version de son manifest.json : le
        // dossier est la 1.1.0, il se dit 1.0.0. Ses fichiers neufs sont
        // identiques à un dépôt **postérieur** à la référence : jamais cochés,
        // jamais proposés.
        let result = try run(installed: ["manifest.json": "m", "new.png": "n"],
                             versions: [author(["manifest.json": "m"], "1.0.0", 10),
                                        author(["manifest.json": "m", "new.png": "n"], "1.1.0", 20)])
        #expect(result.candidates.isEmpty)
    }

    @Test func aNoisyVersionLabelDoesNotHideAGhost() throws {
        // Wildroot : des fichiers étiquetés « 14 » sur Nexus, déposés avant la
        // 1.4.1. `compare("14", "1.4.1")` les dirait plus récents.
        let result = try run(installed: ["manifest.json": "m", "old.png": "o"],
                             versions: [author(["manifest.json": "m"], "1.4.1", 10),
                                        author(["old.png": "o"], "14", 5)],
                             installedVersion: "1.4.1")
        #expect(result.candidates.map(\.path) == ["old.png"])
    }

    @Test func aProbableGhostComesOnlyFromAnEarlierDepositAndNeverFromATranslation() throws {
        let result = try run(
            installed: ["manifest.json": "m", "older.png": "?", "later.png": "?", "noisy.png": "?",
                        "i18n/de.json": "?", "i18n/default.json": "?"],
            versions: [author(["manifest.json": "m"], "1.0.0", 3)],
            legacy: [.init(fileId: 1, version: "0.8", paths: ["older.png", "i18n/de.json", "i18n/default.json"]),
                     .init(fileId: 2, version: "14", paths: ["noisy.png"]),
                     .init(fileId: 5, version: "0.9.9", paths: ["later.png"])])
        #expect(result.candidates.map(\.path) == ["i18n/default.json", "noisy.png", "older.png"])
        #expect(result.candidates.allSatisfy { $0.certainty == .pathOnly })
    }

    @Test func aUserFileAtAnOldPathIsOnlyProbable() throws {
        let result = try run(installed: ["manifest.json": "m", "assets/bag.json": "mine"],
                             versions: [author(["manifest.json": "m"], "1.0.0", 2)],
                             legacy: [.init(fileId: 1, version: "0.9.0", paths: ["assets/bag.json"])])
        #expect(result.candidates.first?.certainty == .pathOnly)
    }

    @Test func theOldFormatReferenceComparesVersionsNotStrings() throws {
        let outcome = Cleanup.plan(installed: .init(hashes: ["manifest.json": "m", "old.png": "o"]),
                                   index: AuthorFileIndex(versions: []),
                                   legacy: [.init(fileId: 2, version: "1.1", paths: ["manifest.json"]),
                                            .init(fileId: 1, version: "1.0", paths: ["old.png"])],
                                   installedVersion: "1.1.0", deposits: [], nexusIncomplete: false)
        guard case .plan(let result) = outcome else { Issue.record("référence 1.1 = 1.1.0"); return }
        #expect(result.reference == .nexusLegacy)
        #expect(result.candidates.map(\.path) == ["old.png"])
    }

    @Test func theLocalHistoryIsTheReferenceWhenItMatches() throws {
        let local = AuthorFileIndex.Version(source: .localHistory, version: "1.0.0",
                                            files: ["manifest.json": "m", "a.png": "a"])
        let older = AuthorFileIndex.Version(source: .localHistory, version: "0.9.0",
                                            files: ["manifest.json": "m0", "old.png": "o"])
        let result = try run(installed: ["manifest.json": "m", "a.png": "a", "old.png": "o"],
                             versions: [older, local])
        #expect(result.reference == .localHistory)
        #expect(result.candidates.map(\.path) == ["old.png"])
    }

    @Test func pathsMatchWithoutCaseAndKeepTheirDiskSpelling() throws {
        let result = try run(installed: ["manifest.json": "m", "Assets/Old.PNG": "o"],
                             versions: [author(["manifest.json": "m"], "1.0.0", 2),
                                        author(["assets/old.png": "o"], "0.9.0", 1)])
        #expect(result.candidates.map(\.path) == ["Assets/Old.PNG"])
    }

    // MARK: - Revue globale (I1, I2)

    private func run(installed: [String: String], versions: [AuthorFileIndex.Version],
                     legacy: [Cleanup.LegacyVersion] = [], installedVersionFileIds: Set<Int>,
                     nexusIncomplete: Bool = false) throws -> Cleanup.Plan {
        try plan(Cleanup.plan(installed: .init(hashes: installed), index: AuthorFileIndex(versions: versions),
                              legacy: legacy, installedVersion: "1.4.0", deposits: [],
                              nexusIncomplete: nexusIncomplete, installedVersionFileIds: installedVersionFileIds))
    }

    @Test func aPartialNexusReferenceChecksNothing() throws {
        // Deux fichiers principaux en 1.4.0 (Wildroot) ; le manifeste du second
        // (21) n'a pas été lu : x.png, qu'il livre, passerait pour un fantôme.
        let versions = [author(["manifest.json": "m"], "1.4.0", 20), author(["x.png": "x"], "1.3.0", 10)]
        let partial = try run(installed: ["manifest.json": "m", "x.png": "x"], versions: versions,
                              installedVersionFileIds: [20, 21])
        #expect(partial.candidates.map(\.path) == ["x.png"])
        #expect(!partial.preselectsIdentical)
        let complete = try run(installed: ["manifest.json": "m", "x.png": "x"], versions: versions,
                               installedVersionFileIds: [20])
        #expect(complete.preselectsIdentical)
    }

    @Test func anIncompleteNexusReadChecksNothingUnlessTheReferenceIsLocal() throws {
        let nexusRef = try run(installed: ["manifest.json": "m", "x.png": "x"],
                               versions: [author(["manifest.json": "m"], "1.4.0", 20),
                                          author(["x.png": "x"], "1.3.0", 10)],
                               installedVersionFileIds: [20], nexusIncomplete: true)
        #expect(!nexusRef.preselectsIdentical)
        let local = AuthorFileIndex.Version(source: .localHistory, version: "1.4.0", files: ["manifest.json": "m"])
        let localRef = try run(installed: ["manifest.json": "m", "x.png": "x"],
                               versions: [local, author(["x.png": "x"], "1.3.0", 10)],
                               installedVersionFileIds: [20], nexusIncomplete: true)
        #expect(localRef.reference == .localHistory)
        #expect(localRef.preselectsIdentical)
    }

    @Test func aVariantOfTheInstalledVersionIsNotEarlier() throws {
        // Installé par l'app en variante Lite 1.4.0 ; l'utilisateur a ajouté un
        // fichier de la variante Full 1.4.0 : ce n'est pas un fantôme.
        let local = AuthorFileIndex.Version(source: .localHistory, version: "1.4.0",
                                            files: ["manifest.json": "m", "a.png": "a"])
        let result = try run(installed: ["manifest.json": "m", "a.png": "a", "extra.png": "e"],
                             versions: [local, author(["manifest.json": "m", "extra.png": "e"], "1.4.0", 50)],
                             installedVersionFileIds: [50])
        #expect(result.candidates.isEmpty)
    }

    @Test func anOldFormatFileOfTheInstalledVersionJoinsTheReference() throws {
        let result = try run(installed: ["manifest.json": "m", "keep.png": "k"],
                             versions: [author(["manifest.json": "m"], "1.4.0", 20),
                                        author(["keep.png": "k"], "1.3.0", 10)],
                             legacy: [.init(fileId: 21, version: "1.4.0", paths: ["keep.png"])],
                             installedVersionFileIds: [20, 21])
        #expect(result.candidates.isEmpty)
        #expect(result.preselectsIdentical)
    }

    @Test func candidatesCarryTheirSize() throws {
        let outcome = Cleanup.plan(installed: .init(hashes: ["manifest.json": "m", "old.png": "o"],
                                                    sizes: ["old.png": 4_096]),
                                   index: AuthorFileIndex(versions: [author(["manifest.json": "m"], "1.0.0", 2),
                                                                     author(["old.png": "o"], "0.9.0", 1)]),
                                   legacy: [], installedVersion: "1.0.0", deposits: [], nexusIncomplete: true)
        let result = try plan(outcome)
        #expect(result.candidates.first?.size == 4_096)
        #expect(result.nexusIncomplete)
    }
}
