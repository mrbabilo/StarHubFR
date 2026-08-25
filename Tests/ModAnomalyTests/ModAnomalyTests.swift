import Testing
import Foundation
@testable import StarHubTHCore

struct ModAnomalyTests {
    private let t0 = Date(timeIntervalSince1970: 1_787_595_034)

    private func mod(_ folder: String, version: String = "1.0.0", id: String = "some.Id") -> ModItem {
        ModItem(uniqueId: id, name: folder, folderName: folder, version: version,
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: true, dependencies: [], languages: [])
    }

    private func pack(_ folder: String, children: [ModItem]) -> ModItem {
        var group = mod(folder, id: "")
        group.children = children
        group.isGroup = true
        return group
    }

    private func history(_ entries: [(mod: String, version: String, errors: Int, warnings: Int)])
        -> ModErrorHistory {
        var history = ModErrorHistory()
        for entry in entries {
            var observations: [ModErrorHistory.Observation] = []
            observations += (0..<entry.errors).map { _ in
                .init(mod: entry.mod, version: entry.version, message: "boom", isError: true)
            }
            observations += (0..<entry.warnings).map { _ in
                .init(mod: entry.mod, version: entry.version, message: "hmm", isError: false)
            }
            history.merge(observations, at: t0)
        }
        return history
    }

    private func anomaly(_ mod: ModItem, _ history: ModErrorHistory,
                         dependencyIssue: Bool = false) -> ModAnomaly? {
        ModAnomalyReport.anomaly(for: mod, history: history, dependencyIssue: { _ in dependencyIssue })
    }

    @Test func aQuietModHasNoAnomaly() {
        #expect(anomaly(mod("Quiet"), ModErrorHistory()) == nil)
    }

    @Test func recentErrorsRaiseAnError() throws {
        let result = try #require(anomaly(mod("Noisy"), history([("Noisy", "1.0.0", 3, 1)])))
        #expect(result.severity == .error)
        #expect(result.errorCount == 3)
        #expect(result.warningCount == 1)
        #expect(result.badgeCount == 4)
    }

    @Test func warningsAloneStayAWarning() throws {
        let result = try #require(anomaly(mod("Chatty"), history([("Chatty", "1.0.0", 0, 5)])))
        #expect(result.severity == .warning)
        #expect(result.warningCount == 5)
    }

    /// **Le cœur de la mesure.** Un mod du parc réel totalisait 76 erreurs, dont
    /// une seule sur la version installée : les 75 autres appartenaient à une
    /// version remplacée depuis. Additionner les versions ferait crier la
    /// pastille pour un problème déjà réglé — et contredirait la fiche du mod,
    /// qui rend l'historique version par version pour cette raison même.
    @Test func onlyTheInstalledVersionCounts() throws {
        let past = history([("Gunther", "2", 75, 0), ("Gunther", "1.0.1", 1, 0)])
        let result = try #require(anomaly(mod("Gunther", version: "1.0.1"), past))
        #expect(result.errorCount == 1)
    }

    /// Trois mods du parc réel n'ont d'historique que sur une version
    /// antérieure : mis à jour depuis, ils ne doivent plus rien afficher.
    @Test func aHistoryOnlyOnAnOlderVersionSaysNothing() {
        let past = history([("Zebrus", "1.3.1", 6, 2)])
        #expect(anomaly(mod("Zebrus", version: "1.3.2"), past) == nil)
    }

    @Test func aMissingDependencyIsAnErrorEvenWithoutAnyLogEntry() throws {
        let result = try #require(anomaly(mod("Lonely"), ModErrorHistory(), dependencyIssue: true))
        #expect(result.severity == .error)
        #expect(result.hasDependencyIssue)
        #expect(result.badgeCount == 0)
    }

    /// Un manifeste que l'app ne sait pas lire donne un `ModItem` sans
    /// `UniqueID` : il apparaît bien dans la liste, mais SMAPI ne le chargera
    /// pas. C'est une anomalie, et elle n'a pas de compte.
    @Test func aModWithoutAnIdentifierCannotBeLoaded() throws {
        let result = try #require(anomaly(mod("Broken", id: ""), ModErrorHistory()))
        #expect(result.severity == .error)
        #expect(result.isUnloadable)
    }

    /// Un en-tête de pack n'a jamais d'`UniqueID` — c'est sa nature. Le tester
    /// signalerait tous les packs du parc comme illisibles.
    @Test func aPackHeaderIsNotUnloadableForLackingAnIdentifier() {
        let sve = pack("SVE", children: [mod("SVE/Core", id: "author.Core")])
        #expect(anomaly(sve, ModErrorHistory()) == nil)
    }

    /// L'en-tête porte l'anomalie de ses composants : sinon il faudrait déplier
    /// chaque pack pour découvrir lequel pose problème.
    @Test func aPackHeaderCarriesItsComponentsTrouble() throws {
        let sve = pack("SVE", children: [mod("SVE/Core", id: "author.Core"),
                                         mod("SVE/Extra", id: "author.Extra")])
        let logs = history([("SVE/Extra", "1.0.0", 2, 0)])
        let result = try #require(anomaly(sve, logs))
        #expect(result.severity == .error)
        #expect(result.errorCount == 2)
    }

    /// Un composant garde la sienne : contrairement au poids, une erreur
    /// s'attribue à un composant précis et ne se compte pas deux fois.
    @Test func aComponentKeepsItsOwnAnomaly() throws {
        let child = mod("SVE/Extra", id: "author.Extra")
        let result = try #require(anomaly(child, history([("SVE/Extra", "1.0.0", 2, 0)])))
        #expect(result.errorCount == 2)
    }

    @Test func aPackHeaderAggregatesEveryComponent() throws {
        let sve = pack("SVE", children: [mod("SVE/A", id: "a"), mod("SVE/B", id: "b")])
        let logs = history([("SVE/A", "1.0.0", 1, 0), ("SVE/B", "1.0.0", 0, 3)])
        let result = try #require(anomaly(sve, logs))
        #expect(result.errorCount == 1)
        #expect(result.warningCount == 3)
        #expect(result.severity == .error)
    }

    /// Une erreur l'emporte sur un avertissement : la pastille dit le pire.
    @Test func anErrorOutranksAWarning() throws {
        let result = try #require(anomaly(mod("Both"), history([("Both", "1.0.0", 1, 9)])))
        #expect(result.severity == .error)
        #expect(result.warningCount == 9)
    }
}
