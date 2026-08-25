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

    // MARK: - Doublons et compatibilité smapi.io

    private func paused(_ item: ModItem) -> ModItem {
        ModItem(uniqueId: item.uniqueId, name: item.name, folderName: item.folderName,
                version: item.version, author: "", description: "", nexusUrl: "",
                nexusModId: "", isEnabled: false, dependencies: [], languages: [])
    }

    /// **Le défaut réel du parc** : `FlyingTNT.Swim` installé deux fois, les
    /// deux copies actives. SMAPI en charge une et laisse l'autre de côté, et
    /// laquelle ne se devine pas.
    @Test func twoActiveCopiesAreAnErrorToday() throws {
        let index = ModDuplicateIndex.build(from: [
            ("FlyingTNT.Swim", "Swim", true),
            ("FlyingTNT.Swim", "Swim Mod-23169/Swim", true),
            ("other.mod", "Other", true),
        ])
        let report = try #require(ModAnomalyReport.anomaly(
            for: mod("Swim", id: "FlyingTNT.Swim"), history: ModErrorHistory(),
            dependencyIssue: { _ in false }, duplicates: index))
        #expect(report.severity == .error)
        // **Nommés, pas comptés** : « installé 2 fois » ne dit pas lequel
        // supprimer dans un parc de 863 dossiers.
        #expect(report.duplicate == .active(folders: ["Swim", "Swim Mod-23169/Swim"]))
    }

    /// Une seule copie active : rien ne casse aujourd'hui, mais le dossier est
    /// toujours là et se réactivera un jour.
    @Test func aDormantDuplicateIsOnlyAWarning() throws {
        let index = ModDuplicateIndex.build(from: [
            ("pseudodiego.nudenpc", "[CP]Xtardew Portraits", false),
            ("pseudodiego.nudenpc", "Xtardew Valley/[CP]Xtardew Portraits", false),
        ])
        let report = try #require(ModAnomalyReport.anomaly(
            for: mod("X", id: "pseudodiego.nudenpc"), history: ModErrorHistory(),
            dependencyIssue: { _ in false }, duplicates: index))
        #expect(report.severity == .warning)
        #expect(report.duplicate?.isDormant == true)
        #expect(report.duplicate?.copies == 2)
    }

    /// **111 mods du parc n'ont aucun `UniqueID`.** Les compter ensemble ferait
    /// de chacun le doublon de tous les autres.
    @Test func modsWithoutAnIdAreNeverDuplicatesOfEachOther() {
        let index = ModDuplicateIndex.build(from: [
            ("", "A", true), ("", "B", true), ("", "C", false),
        ])
        #expect(index.folders.isEmpty)
        #expect(index.duplicate(of: "") == nil)
    }

    /// **L'état actif gradue, il ne filtre pas.** Les sept mods que smapi.io
    /// signale sur ce parc sont tous en pause : les masquer les ferait
    /// disparaître de l'onglet Problèmes, où l'utilisateur les cherche.
    @Test func aPausedBrokenModIsStillReported() throws {
        let report = try #require(ModAnomalyReport.anomaly(
            for: paused(mod("TrainTracks", id: "aedenthorn.TrainTracks")),
            history: ModErrorHistory(), dependencyIssue: { _ in false },
            compatibility: ["aedenthorn.TrainTracks": .workaround]))
        #expect(report.severity == .warning)
        #expect(report.compatibility == .workaround)
    }

    /// Le même mod, activé : ce n'est plus un dossier à ranger, c'est un défaut
    /// du jour.
    @Test func anEnabledBrokenModIsAnError() throws {
        let report = try #require(ModAnomalyReport.anomaly(
            for: mod("TrainTracks", id: "aedenthorn.TrainTracks"),
            history: ModErrorHistory(), dependencyIssue: { _ in false },
            compatibility: ["aedenthorn.TrainTracks": .workaround]))
        #expect(report.severity == .error)
    }

    /// Un verdict `Ok` ne signale rien — sinon 281 mods du parc entreraient
    /// dans l'onglet Problèmes pour avoir été déclarés sains.
    @Test func aHealthyVerdictReportsNothing() {
        #expect(ModAnomalyReport.anomaly(
            for: mod("Fine", id: "fine.mod"), history: ModErrorHistory(),
            dependencyIssue: { _ in false }, compatibility: ["fine.mod": .ok]) == nil)
    }

    /// Un pack porte le doublon de son composant : sans quoi il faudrait
    /// déplier chaque pack pour le découvrir.
    @Test func aPackCarriesItsComponentDuplicate() throws {
        let child = mod("Swim", id: "FlyingTNT.Swim")
        let index = ModDuplicateIndex.build(from: [
            ("FlyingTNT.Swim", "Swim", true),
            ("FlyingTNT.Swim", "Swim Mod-23169/Swim", true),
        ])
        let report = try #require(ModAnomalyReport.anomaly(
            for: pack("Swim Mod-23169", children: [child]), history: ModErrorHistory(),
            dependencyIssue: { _ in false }, duplicates: index))
        #expect(report.duplicate?.isActive == true)
    }

    /// **Un pack à composants mixtes.** Le verdict qui l'emporte vient du
    /// composant en pause, mais c'est l'autre — actif et cassé — qui décide de
    /// la gravité : le mod tourne aujourd'hui.
    @Test func aPackWithOneBrokenComponentEnabledIsAnError() throws {
        let dormant = paused(mod("A", id: "broken.paused"))
        let live = mod("B", id: "broken.live")
        let report = try #require(ModAnomalyReport.anomaly(
            for: pack("Pack", children: [dormant, live]), history: ModErrorHistory(),
            dependencyIssue: { _ in false },
            compatibility: ["broken.paused": .workaround, "broken.live": .workaround]))
        #expect(report.severity == .error)
    }

    /// Deux composants dormants en double : les dossiers nommés ne doivent pas
    /// dépendre de l'ordre dans lequel on les parcourt.
    @Test func twoDormantDuplicatesDoNotOverwriteEachOther() throws {
        let index = ModDuplicateIndex.build(from: [
            ("a.mod", "A1", false), ("a.mod", "A2", false),
            ("b.mod", "B1", false), ("b.mod", "B2", false),
        ])
        let report = try #require(ModAnomalyReport.anomaly(
            for: pack("Pack", children: [paused(mod("A", id: "a.mod")),
                                         paused(mod("B", id: "b.mod"))]),
            history: ModErrorHistory(), dependencyIssue: { _ in false },
            duplicates: index))
        #expect(report.duplicate?.folders == ["A1", "A2"])
    }
}
