import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T1 — dépendances absentes du disque, prêtes à installer. Le cas réel du
/// parc (2026-10-02) : `[QF] Personal Effects`, en pause, exige
/// `PurrplingCat.QuestFramework` (Nexus 6414), absent.
@Suite struct MissingDependenciesTests {

    private func mod(_ uid: String, name: String, enabled: Bool = true,
                     requires: [String] = [], optional: [String] = []) -> ModItem {
        ModItem(uniqueId: uid, name: name, folderName: uid, version: "1.0.0",
                author: "A", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled,
                dependencies: requires.map { ModDependency(uniqueId: $0, isRequired: true) }
                    + optional.map { ModDependency(uniqueId: $0, isRequired: false) },
                children: nil, isGroup: false, installedFileDate: nil)
    }

    private let directory = DependencyNexusDirectory(entries: [
        .init(id: "PurrplingCat.QuestFramework", status: nil, brokeIn: nil, summary: nil,
              nexusID: 6414, name: "Quest Framework"),
        .init(id: "Author.PartA, Author.PartB", status: nil, brokeIn: nil, summary: nil,
              nexusID: 77, name: "Bundle"),
        .init(id: "Gone.Mod", status: nil, brokeIn: nil, summary: nil, nexusID: -1, name: "Gone"),
    ])

    @Test func anActiveModsAbsentDependencyIsMissingWithItsPage() {
        let plan = MissingDependencies.plan(
            mods: [mod("ceruleandeep.PersonalEffects", name: "Personal Effects",
                       requires: ["purrplingcat.questframework"])],
            installedIds: [], directory: directory)
        #expect(plan.count == 1)
        #expect(plan.first?.name == "Quest Framework")
        #expect(plan.first?.nexusId == 6414)
        #expect(plan.first?.requiredBy == ["Personal Effects"])
    }

    /// Le cas voisin : un mod en pause ne réclame rien au jeu.
    @Test func aPausedModClaimsNothing() {
        let plan = MissingDependencies.plan(
            mods: [mod("x.paused", name: "Paused", enabled: false,
                       requires: ["PurrplingCat.QuestFramework"])],
            installedIds: [], directory: directory)
        #expect(plan.isEmpty)
    }

    /// Installée (même en pause, casse différente) ou facultative : rien à installer.
    @Test func installedOrOptionalDependenciesAreNotMissing() {
        let plan = MissingDependencies.plan(
            mods: [mod("x.a", name: "A", requires: ["PURRPLINGCAT.QUESTFRAMEWORK"],
                       optional: ["Some.Optional"])],
            installedIds: ["purrplingcat.questframework"], directory: directory)
        #expect(plan.isEmpty)
    }

    /// Deux identifiants d'une même page : un seul téléchargement, les deux
    /// mods demandeurs nommés.
    @Test func twoIdsOfOnePageAreOneDependency() {
        let plan = MissingDependencies.plan(
            mods: [mod("x.a", name: "A", requires: ["Author.PartA"]),
                   mod("x.b", name: "B", requires: ["Author.PartB"])],
            installedIds: [], directory: directory)
        #expect(plan.count == 1)
        #expect(plan.first?.uniqueIds == ["Author.PartA", "Author.PartB"])
        #expect(plan.first?.requiredBy == ["A", "B"])
    }

    /// Inconnu du dump, ou `nexus` négatif : pas de page, nom lisible tiré
    /// de l'identifiant.
    @Test func anUnknownDependencyHasNoPage() {
        let plan = MissingDependencies.plan(
            mods: [mod("x.a", name: "A", requires: ["Some.UnknownThing", "Gone.Mod"])],
            installedIds: [], directory: directory)
        #expect(plan.map(\.nexusId) == [nil, nil])
        #expect(plan.map(\.name).sorted() == ["Gone", "Unknown Thing"])
    }

    @Test func mostClaimedComesFirst() {
        let plan = MissingDependencies.plan(
            mods: [mod("x.a", name: "A", requires: ["Z.Rare", "PurrplingCat.QuestFramework"]),
                   mod("x.b", name: "B", requires: ["PurrplingCat.QuestFramework"])],
            installedIds: [], directory: directory)
        #expect(plan.map(\.name) == ["Quest Framework", "Rare"])
    }

    // MARK: - Actions

    private func dep(_ uid: String, nexus: Int?) -> MissingDependency {
        MissingDependency(uniqueIds: [uid], name: uid, nexusId: nexus, requiredBy: ["A"])
    }

    @Test func premiumDownloadsInAppWithTheExpectedIds() {
        let actions = MissingDependencies.actions(for: [dep("a.b", nexus: 6414)], canDownloadInApp: true)
        #expect(actions == [.download(nexusId: 6414, uniqueIds: ["a.b"])])
    }

    @Test func aFreeAccountOpensTheFilesTab() {
        let actions = MissingDependencies.actions(for: [dep("a.b", nexus: 6414)], canDownloadInApp: false)
        #expect(actions == [.openPage(URL(string: "https://www.nexusmods.com/stardewvalley/mods/6414?tab=files")!,
                                      nexusId: 6414, uniqueIds: ["a.b"])])
    }

    /// SMAPI s'installe par son installateur ; une page inconnue se cherche.
    @Test func smapiIsSkippedAndUnknownIsSearched() {
        let actions = MissingDependencies.actions(for: [dep("SMAPI", nexus: 2400), dep("x.y", nexus: nil)],
                                                  canDownloadInApp: true)
        #expect(actions.count == 1)
        if case .search = actions.first {} else { Issue.record("recherche attendue") }
    }

    @Test func pagesAreCappedButDownloadsAreNot() {
        let many = (1...20).map { dep("a.\($0)", nexus: $0) }
        #expect(MissingDependencies.actions(for: many, canDownloadInApp: false).count == MissingDependencies.pageLimit)
        #expect(MissingDependencies.actions(for: many, canDownloadInApp: true).count == 20)
    }

    // MARK: - Contrôle de l'archive

    @Test func anArchiveWithoutTheExpectedIdIsFlagged() {
        #expect(MissingDependencies.absent(expected: ["PurrplingCat.QuestFramework"],
                                           in: ["purrplingcat.questframework"]).isEmpty)
        #expect(MissingDependencies.absent(expected: ["PurrplingCat.QuestFramework"],
                                           in: ["Other.Mod"]) == ["PurrplingCat.QuestFramework"])
        #expect(MissingDependencies.absent(expected: [], in: ["Other.Mod"]).isEmpty)
    }
}

/// `.urlQueryAllowed` laisse passer `&`, `+` et `=` : un nom portant `&`
/// coupait la recherche Nexus au premier mot (`gsearch=Mail ` puis un
/// paramètre parasite).
struct MissingDependenciesSearchURLTests {
    @Test func reservedQueryCharactersAreEncoded() throws {
        let url = try #require(MissingDependencies.searchPage(for: "Mail & Co + 2=3"))
        let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "gsearch" }
        #expect(item?.value == "Mail & Co + 2=3")
    }

    @Test func authorPageEncodesTheSameWay() throws {
        let url = try #require(MissingDependencies.authorPage(for: "A&B"))
        let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "author" }
        #expect(item?.value == "A&B")
    }
}

