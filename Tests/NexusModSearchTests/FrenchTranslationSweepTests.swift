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
                     nexus: String = "", version: String = "1.0",
                     children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: "id.\(name)", name: name, folderName: name, version: version,
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
            hit(2, "Immersive Farm - Traduction", tags: ["French", "Translation"], updated: 30),
            hit(5, "Mini Obelisk", tags: ["French"], updated: 40),  // écrit en français, pas une traduction
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
        // Rien de vérifié n'est « à jour » : jamais cherché, recherche en
        // échec, ou traduction posée sans fiche Nexus.
        #expect(FrenchTranslationSweep.status(
            entry: nil, installed: installed(nexusId: 5, name: "X - FR", updated: 100))
            == .installedUnverified)
        #expect(FrenchTranslationSweep.status(
            entry: .init(hits: [], searchedAt: now, failed: true),
            installed: installed(nexusId: 5, name: "X - FR", updated: 100)) == .installedUnverified)
        #expect(FrenchTranslationSweep.status(
            entry: entry, installed: installed(nexusId: 0, name: "X - FR", updated: 100))
            == .installedUnverified)
    }

    /// Une base de comparaison absente ne dit pas « à jour » : la déclaration
    /// manuelle ne relève pas la date Nexus, et un vert mensonger cacherait
    /// précisément la mise à jour qu'on cherche (SVE-Français, 2026-10-05).
    @Test func statusWithoutABaselineStaysUnverified() {
        let now = Date()
        let entry = FrenchTranslationSweep.Entry(hits: [hit(5, "X - FR", updated: 200)],
                                                 searchedAt: now)
        let declared = DeclaredTranslation(nexusModId: 5, nexusName: "X - FR",
                                           version: nil, updatedAt: nil, declaredAt: now)
        #expect(FrenchTranslationSweep.status(
            entry: entry, installed: declared.asTracked(hostFolderName: "Host"))
            == .installedUnverified)
        // Dès que la base existe — adoptée depuis un résultat concordant — la
        // pastille vit comme pour une traduction posée par l'app.
        let based = DeclaredTranslation(nexusModId: 5, nexusName: "X - FR",
                                        version: "1.0", updatedAt: Date(timeIntervalSince1970: 100),
                                        declaredAt: now)
        #expect(FrenchTranslationSweep.status(
            entry: entry, installed: based.asTracked(hostFolderName: "Host"))
            == .updateAvailable(hit(5, "X - FR", updated: 200)))
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

    // MARK: - Re-balayage incrémental (2026-10-05)

    /// ~90 min pour tout le parc dont 90 % sans résultat : on ne re-cherche
    /// que l'utile. Jamais cherché, mod changé, résultat vieux — les trois
    /// seuls signaux ; le reste se relit au cache.
    @Test func rescanWaitsForAChangeOrStaleResults() {
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        let day: TimeInterval = 86_400
        func candidate(_ name: String) -> FrenchTranslationSweep.Candidate {
            .init(folderName: name, name: name, isActive: true, nexusModId: nil, version: "1.0")
        }
        let fresh = FrenchTranslationSweep.Entry(hits: [hit(1, "A - FR")],
                                                 searchedAt: now.addingTimeInterval(-3 * day),
                                                 signature: "0|1.0")
        let stale = FrenchTranslationSweep.Entry(hits: [hit(1, "A - FR")],
                                                 searchedAt: now.addingTimeInterval(-20 * day),
                                                 signature: "0|1.0")
        let staleEmpty = FrenchTranslationSweep.Entry(hits: [],
                                                      searchedAt: now.addingTimeInterval(-40 * day),
                                                      signature: "0|1.0")
        let youngEmpty = FrenchTranslationSweep.Entry(hits: [],
                                                      searchedAt: now.addingTimeInterval(-20 * day),
                                                      signature: "0|1.0")

        #expect(FrenchTranslationSweep.shouldRescan(candidate: candidate("New"),
                                                    previous: nil, now: now))
        // Un cache écrit avant la signature (nil) repasse une dernière fois,
        // le temps de la poser — le premier passage après l'upgrade re-balaye
        // tout, c'est annoncé.
        #expect(FrenchTranslationSweep.shouldRescan(
            candidate: candidate("Unsigned"),
            previous: FrenchTranslationSweep.Entry(hits: [hit(1, "A - FR")],
                                                   searchedAt: now.addingTimeInterval(-3 * day)),
            now: now))
        #expect(FrenchTranslationSweep.shouldRescan(
            candidate: candidate("Fresh"), previous: fresh, now: now) == false)
        // Des hits vieux de plus de deux semaines : une traduction peut être
        // sortie depuis.
        #expect(FrenchTranslationSweep.shouldRescan(
            candidate: candidate("Stale"), previous: stale, now: now))
        // Sans résultat, l'espoir d'une traduction nouvelle s'épuise plus
        // lentement : un mois.
        #expect(FrenchTranslationSweep.shouldRescan(
            candidate: candidate("StaleEmpty"), previous: staleEmpty, now: now))
        #expect(FrenchTranslationSweep.shouldRescan(
            candidate: candidate("YoungEmpty"), previous: youngEmpty, now: now) == false)
    }

    /// Le signal le plus direct : le mod a bougé depuis la recherche (mise à
    /// jour installée, identifiant appris). Sa signature change, on re-cherche
    /// quel que soit l'âge du cache.
    @Test func aChangedModIsRescannedHoweverFreshTheCache() {
        let now = Date()
        let entry = FrenchTranslationSweep.Entry(hits: [hit(1, "A - FR")],
                                                 searchedAt: now, signature: "12|1.0")
        func candidate(_ name: String, id: Int, version: String) -> FrenchTranslationSweep.Candidate {
            .init(folderName: name, name: name, isActive: true,
                  nexusModId: id > 0 ? id : nil, version: version)
        }
        #expect(FrenchTranslationSweep.shouldRescan(
            candidate: candidate("Changed", id: 12, version: "2.0"),
            previous: entry, now: now))
        #expect(FrenchTranslationSweep.shouldRescan(
            candidate: candidate("Same", id: 12, version: "1.0"),
            previous: entry, now: now) == false)
        // Ancien cache sans signature : on la pose au premier passage.
        #expect(FrenchTranslationSweep.shouldRescan(
            candidate: candidate("Old", id: 12, version: "1.0"),
            previous: FrenchTranslationSweep.Entry(hits: [], searchedAt: now), now: now))
    }

    /// Relevé sur l'API réelle (SVE, 2026-09-24) : le lien rend aussi les
    /// traductions des mods qui requièrent SVE. Le titre départage.
    @Test func confidenceNeedsTheLinkAndATitleThatNamesTheMod() {
        let sve = hit(29381, "Stardew Valley Expanded -  Francais")
        let other = hit(7574, "Xtardew Valley - French")
        let nameOnly = hit(1, "Stardew Valley Expanded FR")
        let entry = FrenchTranslationSweep.merge(linked: [sve, other], byName: [nameOnly], at: Date())
        #expect(entry.confidence(of: sve, hostName: "Stardew Valley Expanded") == .confirmed)
        #expect(entry.confidence(of: other, hostName: "Stardew Valley Expanded") == .linkedOnly)
        #expect(entry.confidence(of: nameOnly, hostName: "Stardew Valley Expanded") == .nameOnly)
        // Ordre des mots libre, préfixe de cadre ignoré, nom collé retrouvé.
        #expect(FrenchTranslationSweep.titleNames("Maggs Townsfolk Daily Dialogue Expansion - FR",
                                                  host: "Maggs Daily Townsfolk Dialogue Expansion"))
        #expect(FrenchTranslationSweep.titleNames("Pelican Town Expanded - FR", host: "[CP] Pelican Town Expanded"))
        #expect(FrenchTranslationSweep.titleNames("Better Chests FR", host: "BetterChests"))
        #expect(!FrenchTranslationSweep.titleNames("Spouses React to Player Death (Francais)",
                                                   host: "Stardew Valley Expanded"))
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
