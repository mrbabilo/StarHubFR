import Testing
import Foundation
@testable import StarHubTHCore

/// Les décisions de la reprise Nexus (B2-T10), extraites du ViewModel
/// (2026-09-11) : ce qu'une page fait à l'état de la reprise
/// (`applyPage`), et le bilan final avec substitution du cache (`settle`).
///
/// La récursion réseau, la progression et le relâchement des drapeaux
/// restent au ViewModel — ce qui reste ici est ce que l'utilisateur lit
/// dans la fenêtre et le journal.
struct NexusResumeTests {

    // MARK: - Fabriques

    private func blocked(_ uid: String, name: String,
                         installed: String) -> NexusFallbackCheck.Blocked {
        NexusFallbackCheck.Blocked(uniqueId: uid, name: name,
                                   installedVersion: installed, declaredKeys: [],
                                   metadataNexusId: 191, errors: ["err"], heldFacts: nil)
    }

    /// Une page dont tous les mods sont dépassés par `pageVersion`.
    private func target(_ nexusId: String, mods: [NexusFallbackCheck.Blocked]) -> NexusFallbackCheck.Target {
        NexusFallbackCheck.Target(nexusId: nexusId, mods: mods)
    }

    private func success(_ version: String) -> NexusUpdateChecker.SingleFetchResult {
        .success(version: version, categoryId: nil, extra: .init(summary: "", pictureUrl: ""),
                 pageFile: nil)
    }

    /// Une page qui tranche les deux sens : Alpha (1.0.0) est dépassé, Bêta
    /// (2.0) est confirmé à jour.
    private func mixedTarget() -> NexusFallbackCheck.Target {
        target("191", mods: [blocked("a.mod", name: "Alpha", installed: "1.0.0"),
                             blocked("b.mod", name: "Bêta", installed: "2.0")])
    }

    // MARK: - applyPage — verdict d'une page

    /// Une page qui parle tranche **tous** ses mods : les lignes trouvées
    /// s'ajoutent, les mods sortent des « non vérifiables » (settled), et le
    /// journal nomme chacun — mise à jour en `.warning` (préfixe `[MAJ]`),
    /// confirmation à jour en info.
    @Test func pageWithVersionYieldsRowsSettlesAndNamesEachMod() {
        let outcome = NexusResume.applyPage(success("2.0"), target: mixedTarget(),
                                            pageIndex: 0,
                                            found: [], settled: [], failures: 0)

        // Seul Alpha est dépassé : Bêta est confirmé à jour — il n'entre pas
        // dans `found`, il entre dans `settled`.
        #expect(outcome.found.count == 1)
        #expect(outcome.settled == ["a.mod", "b.mod"])
        #expect(outcome.failures == 0)
        #expect(outcome.rateLimitedRetryAfter == nil)
        #expect(outcome.journal.count == 2)
        let updated = outcome.journal[0]
        #expect(updated.level == .warning)
        #expect(updated.text.contains("[MAJ] Reprise Nexus : Alpha — 1.0.0 → 2.0"))
        #expect(updated.text.contains("(page 191)"))
        let upToDate = outcome.journal[1]
        #expect(upToDate.level == .info)
        #expect(upToDate.text.contains("Bêta à jour"))
    }

    /// Un manifeste sans champ `Version` existe : ne pas afficher un blanc là
    /// où le lecteur attend un numéro.
    @Test func missingInstalledVersionReadsAsUnknown() {
        let t = target("191", mods: [blocked("c.mod", name: "Sans version", installed: "")])
        let outcome = NexusResume.applyPage(success("2.0"), target: t, pageIndex: 0,
                                            found: [], settled: [], failures: 0)

        #expect(outcome.journal[0].text.contains("version inconnue"))
    }

    /// Une page **sans version** n'est pas un verdict : une chaîne vide se
    /// décode sans broncher, et la tenir pour « à jour » retirerait le mod des
    /// invérifiables sur un quitus inventé — le défaut même que la reprise
    /// existe pour supprimer. Donc : échec compté, rien de settled, un mot
    /// dans le journal.
    @Test func pageWithoutVersionIsAFailureNotAVerdict() {
        let outcome = NexusResume.applyPage(success("   "), target: mixedTarget(),
                                            pageIndex: 1,
                                            found: [], settled: [], failures: 0)

        #expect(outcome.failures == 1)
        #expect(outcome.found.isEmpty)
        #expect(outcome.settled.isEmpty)
        #expect(outcome.rateLimitedRetryAfter == nil)
        #expect(outcome.journal.count == 1)
        #expect(outcome.journal[0].level == .warning)
        #expect(outcome.journal[0].text.contains("ne publie aucune version"))
        #expect(outcome.journal[0].text.contains("2 mod(s) toujours sans verdict"))
    }

    /// Un 429 arrête la reprise sur place — les suivantes seraient refusées
    /// localement, et ce qui a abouti reste acquis (état inchangé, pas
    /// d'échec compté).
    @Test func rateLimitStopsTheResume() {
        let outcome = NexusResume.applyPage(.rateLimited(retryAfter: 42),
                                            target: mixedTarget(),
                                            pageIndex: 3,
                                            found: [], settled: [], failures: 0)

        #expect(outcome.rateLimitedRetryAfter == 42)
        #expect(outcome.found.isEmpty)
        #expect(outcome.settled.isEmpty)
        #expect(outcome.failures == 0)
        #expect(outcome.journal.count == 1)
        #expect(outcome.journal[0].level == .warning)
        #expect(outcome.journal[0].text.contains("limitation de débit (42 s) après 3 page(s)"))
    }

    /// Ni `.noApiKey` ni `.error` n'arrêtent rien : ils comptent un échec et
    /// se taisent — une rafale d'erreurs ne doit pas noyer le journal.
    @Test func errorAndNoApiKeyCountAsSilentFailures() {
        let error = NexusResume.applyPage(.error("HTTP 500"), target: mixedTarget(),
                                          pageIndex: 0, found: [], settled: [], failures: 0)
        let noKey = NexusResume.applyPage(.noApiKey, target: mixedTarget(),
                                          pageIndex: 0, found: [], settled: [], failures: 2)

        #expect(error.failures == 1)
        #expect(error.rateLimitedRetryAfter == nil)
        #expect(error.journal.isEmpty)
        #expect(noKey.failures == 3)
        #expect(noKey.journal.isEmpty)
    }

    /// L'état reçu est **porté** : les pages précédentes survivent à la
    /// suivante (la récursion du ViewModel n'additionne plus rien elle-même).
    @Test func priorStateIsCarriedThrough() {
        let priorRow = NexusUpdateChecker.ModUpdate(uniqueId: "old.mod", name: "Ancien",
                                                    installedVersion: "1.0", latestVersion: "1.5",
                                                    nexusModId: "", url: "", uploadedTime: nil)
        let outcome = NexusResume.applyPage(success("2.0"),
                                            target: target("191",
                                                           mods: [blocked("a.mod", name: "Alpha",
                                                                          installed: "1.0.0")]),
                                            pageIndex: 0,
                                            found: [priorRow], settled: ["old.mod"],
                                            failures: 1)

        #expect(outcome.found.map(\.uniqueId) == ["old.mod", "a.mod"])
        #expect(outcome.settled == ["old.mod", "a.mod"])
        #expect(outcome.failures == 1)
    }

    // MARK: - settle — le bilan final

    /// Les lignes Nexus se **substituent** aux lignes précédentes des mêmes
    /// mods : le cache est indexé par `UniqueID`, et deux lignes de même
    /// identité donneraient des doublons à un `ForEach`.
    @Test func foundRowsReplacePreviousRowsOfSameMods() {
        let cached = [row("a.mod", name: "Alpha", latest: "1.5"),
                      row("b.mod", name: "Bêta", latest: "1.5")]
        let found = [row("a.mod", name: "Alpha", latest: "2.0")]
        let settlement = NexusResume.settle(found: found, settled: ["a.mod"],
                                            failures: 0, attempted: 1, cachedRows: cached)

        #expect(settlement.merged.map(\.uniqueId) == ["a.mod", "b.mod"])
        #expect(settlement.merged.first { $0.uniqueId == "a.mod" }?.latestVersion == "2.0")
    }

    /// Le décompte honnête : tenté, trouvé, confirmé à jour, échoué — une
    /// reprise silencieuse laisserait croire qu'elle n'a rien trouvé alors
    /// qu'elle n'a pas abouti. Le niveau monte en `.warning` dès qu'elle a
    /// trouvé quelque chose.
    @Test func summaryCountsAttemptedFoundConfirmedAndFailed() {
        let settlement = NexusResume.settle(found: [row("a.mod", name: "Alpha", latest: "2.0")],
                                            settled: ["a.mod", "b.mod"],
                                            failures: 1, attempted: 3, cachedRows: [])
        #expect(settlement.journal.count == 1)
        #expect(settlement.journal[0].level == .warning)
        #expect(settlement.journal[0].text.contains("3 page(s) interrogée(s)"))
        #expect(settlement.journal[0].text.contains("1 mise(s) à jour trouvée(s)"))
        #expect(settlement.journal[0].text.contains("1 mod(s) confirmé(s) à jour"))
        #expect(settlement.journal[0].text.contains("1 échec(s)"))

        let empty = NexusResume.settle(found: [], settled: ["a.mod"],
                                       failures: 0, attempted: 1, cachedRows: [])
        #expect(empty.journal[0].level == .info)
    }

    /// Ex æquo de nom départagés par `UniqueID` — la même règle que la
    /// consolidation et que `SmapiVerdicts` (le tri de Swift n'est pas
    /// stable). (Déviation consignée : le code déplacé ne départageait pas.)
    @Test func mergedSortBreaksNameTiesByUniqueId() {
        let cached = [row("z9.mod", name: "Homonyme", latest: "1.0")]
        let found = [row("j1.mod", name: "homonyme", latest: "2.0"),
                     row("j2.mod", name: "Homonyme", latest: "2.0"),
                     row("a1.mod", name: "homonyme", latest: "2.0")]
        let settlement = NexusResume.settle(found: found, settled: [],
                                            failures: 0, attempted: 3, cachedRows: cached)

        #expect(settlement.merged.map(\.uniqueId) == ["a1.mod", "j1.mod", "j2.mod", "z9.mod"])
    }

    // MARK: - Fabrique commune

    private func row(_ uid: String, name: String,
                     latest: String) -> NexusUpdateChecker.ModUpdate {
        NexusUpdateChecker.ModUpdate(uniqueId: uid, name: name,
                                     installedVersion: "1.0.0", latestVersion: latest,
                                     nexusModId: "", url: "", uploadedTime: nil)
    }
}
