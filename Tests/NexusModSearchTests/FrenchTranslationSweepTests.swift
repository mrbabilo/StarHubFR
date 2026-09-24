import Testing
import Foundation
@testable import StarHubTHCore

/// C5-T1 — le lien « requis par » et la vue d'ensemble des traductions FR.
struct FrenchTranslationSweepTests {
    private func hit(_ id: Int, _ name: String, tags: [String] = [],
                     updated: TimeInterval = 0) -> NexusModSearch.Hit {
        NexusModSearch.Hit(modId: id, name: name, version: "1.0",
                           updatedAt: Date(timeIntervalSince1970: updated),
                           categoryName: "", uploader: "", adultContent: false, tags: tags)
    }
    private func mod(_ name: String, languages: [String], enabled: Bool = true,
                     nexus: String = "", children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: "id.\(name)", name: name, folderName: name, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: nexus,
                isEnabled: enabled, dependencies: [], children: children,
                isGroup: children != nil, hasConfigFile: false, languages: languages)
    }
    private func installed(nexusId: Int, name: String, updated: TimeInterval) -> InstalledTranslation {
        InstalledTranslation(hostFolderName: "Host", nexusModId: nexusId, nexusName: name,
                             version: "1.0", updatedAt: Date(timeIntervalSince1970: updated),
                             installedAt: Date(), files: [], replacedFiles: [:])
    }

    // MARK: - Lien « requis par »

    @Test func requiringBodyCarriesTheHostAndPage() throws {
        let data = try #require(NexusModSearch.requiringBody(modId: 3753, gameId: 1303, offset: 80))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let variables = try #require(object["variables"] as? [String: Any])
        #expect(variables["id"] as? String == "3753")
        #expect(variables["game"] as? String == "1303")
        #expect(variables["offset"] as? Int == 80)
        #expect((object["query"] as? String)?.contains("modsRequiringThisMod") == true)
    }

    @Test func decodeRequiringReadsStringIdsAndTotal() {
        let json = #"{"data":{"mods":{"nodes":[{"modRequirements":{"modsRequiringThisMod":{"totalCount":756,"nodes":[{"modId":"29381"},{"modId":32663}]}}}]}}}"#
        let page = try? NexusModSearch.decodeRequiring(Data(json.utf8)).get()
        #expect(page == .init(modIds: [29381, 32663], totalCount: 756))
    }

    /// Une fiche retirée rend `nodes: []` : une page vide, pas une panne.
    @Test func decodeRequiringUnknownModIsEmptyNotFailure() {
        let page = try? NexusModSearch.decodeRequiring(Data(#"{"data":{"mods":{"nodes":[]}}}"#.utf8)).get()
        #expect(page == .init(modIds: [], totalCount: 0))
    }

    /// GraphQL rend 200 avec `errors` : ce n'est pas « aucune traduction ».
    @Test func decodeRequiringErrorsAreFailures() {
        let json = #"{"errors":[{"message":"gameId is required"}],"data":null}"#
        guard case .failure(.service(let message)) = NexusModSearch.decodeRequiring(Data(json.utf8)) else {
            Issue.record("attendu : échec service"); return
        }
        #expect(message.contains("gameId"))
    }

    /// Le filtre `modId` exige `gameId` dans **la même** clause (mesuré : sans
    /// elle, « gameId is required when filtering by modId »).
    @Test func modsByIdsPutsGameIdInEveryClause() throws {
        #expect(NexusModSearch.modsByIdsBody([], gameId: 1303) == nil)
        let data = try #require(NexusModSearch.modsByIdsBody([1, 2, 3], gameId: 1303))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let variables = try #require(object["variables"] as? [String: Any])
        let filters = try #require(variables["filters"] as? [[String: Any]])
        #expect(filters.count == 3)
        #expect(filters.allSatisfy { $0["gameId"] != nil && $0["modId"] != nil })
        #expect(variables["count"] as? Int == 3)
    }

    @Test func linkedFrenchKeepsTagOrTitleDropsHostAndOthers() {
        let hits = [
            hit(1, "SVE - Francais", updated: 10),                 // titre seul
            hit(2, "Immersive Farm - Traduction", tags: ["French"], updated: 30),
            hit(3, "SVE - Deutsch", tags: ["German"], updated: 50),
            hit(4, "Frontier Farm Addon", updated: 60),            // « Fr »ontier : pas un mot
            hit(9, "Host itself", tags: ["French"], updated: 99),  // l'hôte
        ]
        let kept = NexusModSearch.linkedFrenchTranslations(hits, hostModId: 9)
        #expect(kept.map(\.modId) == [2, 1])
    }

    // MARK: - Candidats

    @Test func candidatesAreTopLevelModsWithoutFrenchPlusInstalledHosts() {
        let mods = [
            mod("Sans fr", languages: ["en"], nexus: "12"),
            mod("En pause", languages: ["en"], enabled: false),
            mod("Déjà fr", languages: ["en", "fr"]),
            mod("Traduit par l'app", languages: ["en", "fr"], nexus: "0"),
            mod("Sans i18n", languages: []),
            mod("Pack vide", languages: [], children: []),
            mod("Pack", languages: [], children: [mod("Composant", languages: ["en"])]),
        ]
        let result = FrenchTranslationSweep.candidates(
            among: mods,
            hasInstalledTranslation: { $0.name == "Traduit par l'app" },
            nexusModId: { Int($0.nexusModId) })
        #expect(result.map(\.name) == ["En pause", "Pack", "Sans fr", "Traduit par l'app"])
        #expect(result.first { $0.name == "Sans fr" }?.nexusModId == 12)
        #expect(result.first { $0.name == "En pause" }?.isActive == false)
        // Un identifiant 0 n'est pas une fiche : la recherche par nom prendra le relais.
        #expect(result.first { $0.name == "Traduit par l'app" }?.nexusModId == nil)
    }

    // MARK: - Statut dérivé

    @Test func statusWithoutInstalledTranslation() {
        let now = Date()
        #expect(FrenchTranslationSweep.status(entry: nil, installed: nil) == .notSearched)
        #expect(FrenchTranslationSweep.status(
            entry: .init(hits: [], searchedAt: now, failed: true),
            installed: nil) == .failed)
        #expect(FrenchTranslationSweep.status(
            entry: .init(hits: [], searchedAt: now), installed: nil) == .nothingFound)
        let found = [hit(5, "X - FR")]
        #expect(FrenchTranslationSweep.status(
            entry: .init(hits: found, searchedAt: now), installed: nil)
            == .available(found))
    }

    /// Installer depuis la vue change le statut sans nouvelle recherche : la
    /// même entrée, un registre différent.
    @Test func statusFollowsTheLiveRegistry() {
        let now = Date()
        let entry = FrenchTranslationSweep.Entry(hits: [hit(5, "X - FR", updated: 200)],
                                                 searchedAt: now)
        #expect(FrenchTranslationSweep.status(
            entry: entry, installed: installed(nexusId: 5, name: "X - FR", updated: 100))
            == .updateAvailable(hit(5, "X - FR", updated: 200)))
        #expect(FrenchTranslationSweep.status(
            entry: entry, installed: installed(nexusId: 5, name: "X - FR", updated: 200))
            == .installed)
        // Une recherche en échec ne dit rien d'une traduction posée.
        #expect(FrenchTranslationSweep.status(
            entry: .init(hits: [], searchedAt: now, failed: true),
            installed: installed(nexusId: 5, name: "X - FR", updated: 100)) == .installed)
    }

    /// Le lien passe devant, le nom ne rajoute que ce que le lien n'a pas vu.
    @Test func mergePutsLinkedFirstAndMarksNameOnlyHits() {
        let entry = FrenchTranslationSweep.merge(
            linked: [hit(1, "A - FR"), hit(2, "B - FR")],
            byName: [hit(2, "B - FR"), hit(3, "C - Francais")], at: Date())
        #expect(entry.hits.map(\.modId) == [1, 2, 3])
        #expect(entry.isLinked(hit(2, "B - FR")))
        #expect(!entry.isLinked(hit(3, "C - Francais")))
    }

    @Test func storageRoundTripsAndToleratesGarbage() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweep-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("sweep.json")
        let entries = ["Mod": FrenchTranslationSweep.Entry(
            hits: [hit(1, "A - FR", tags: ["French"], updated: 5)], searchedAt: Date(timeIntervalSince1970: 1_000))]
        #expect(FrenchTranslationSweep.Storage.save(entries, to: url))
        #expect(FrenchTranslationSweep.Storage.load(from: url) == entries)
        try Data("pas du json".utf8).write(to: url)
        #expect(FrenchTranslationSweep.Storage.load(from: url).isEmpty)
    }
}
