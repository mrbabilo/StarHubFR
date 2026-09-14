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
                         installed: String,
                         errors: [String] = ["err"]) -> NexusFallbackCheck.Blocked {
        NexusFallbackCheck.Blocked(uniqueId: uid, name: name,
                                   installedVersion: installed, declaredKeys: [],
                                   metadataNexusId: 191, errors: errors, heldFacts: nil)
    }

    /// Le message réel de smapi.io pour une page Nexus qu'il ne voit plus —
    /// cachée, supprimée ou jamais existée (sondes du 2026-09-14, A2-T6).
    private static let foundNoNexus = "Found no Nexus mod with this ID."

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

    /// Ni `.noApiKey` ni une erreur **hors statut HTTP** ne disent rien :
    /// ils comptent un échec et se taisent — une rafale d'erreurs ne doit
    /// pas noyer le journal. (`parse_error` est le format réel d'une panne
    /// de décodage côté `fetchModInfo` ; les statuts `http_<code>`, eux,
    /// parlent — voir la mesure A2-T6 plus bas.)
    @Test func errorAndNoApiKeyCountAsSilentFailures() {
        let error = NexusResume.applyPage(.error("parse_error"), target: mixedTarget(),
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

    // MARK: - La mesure A2-T6 — un statut HTTP se nomme

    /// La mesure manquante de la case A2-T6 : `fetchModInfo` construit
    /// `http_<code>` pour tout statut hors 200/429, et un **404** sur une
    /// page réclamée par la reprise est le seul signal qui distingue
    /// « supprimée ou cachée » d'une panne locale. Le journal le nomme
    /// (mesuré sur le cas réel 32260, caché par son auteur) au lieu de
    /// compter un échec muet.
    @Test func http404JournalsTheMeasurement() {
        let outcome = NexusResume.applyPage(.error("http_404"), target: mixedTarget(),
                                            pageIndex: 0, found: [], settled: [], failures: 0)

        #expect(outcome.failures == 1)
        #expect(outcome.rateLimitedRetryAfter == nil)
        #expect(outcome.notFoundPages == 1)
        #expect(outcome.journal.count == 1)
        #expect(outcome.journal[0].level == .info)
        #expect(outcome.journal[0].text.contains("page 191"))
        #expect(outcome.journal[0].text.contains("HTTP 404"))
        #expect(outcome.journal[0].text.contains("supprimée ou cachée"))
        #expect(outcome.journal[0].text.contains("2 mod(s) sans verdict"))
    }

    /// Un autre statut se mesure aussi, sans le gloss du 404 : le texte de
    /// la raison (modération, mise à jour en cours) n'est pas déduit d'un
    /// code qui ne le porte pas.
    @Test func otherHTTPCodesJournalWithoutThe404Gloss() {
        let outcome = NexusResume.applyPage(.error("http_503"), target: mixedTarget(),
                                            pageIndex: 0, found: [], settled: [], failures: 0)

        #expect(outcome.notFoundPages == 0)
        #expect(outcome.journal.count == 1)
        #expect(outcome.journal[0].level == .info)
        #expect(outcome.journal[0].text.contains("HTTP 503"))
        #expect(!outcome.journal[0].text.contains("supprimée"))
    }

    /// Le bilan nomme les 404 quand il y en a : la mesure se lit au coup
    /// d'œil, sans recompter les échecs. Zéro 404 — le bilan ne dit rien de
    /// plus que ce qu'il disait.
    @Test func summaryNames404PagesWhenAny() {
        let with404 = NexusResume.settle(found: [], settled: [], failures: 2,
                                         attempted: 2, cachedRows: [], notFoundPages: 1)
        #expect(with404.journal[0].text.contains("2 échec(s), dont 1 page(s) 404"))

        let without = NexusResume.settle(found: [], settled: [], failures: 0,
                                         attempted: 1, cachedRows: [])
        #expect(!without.journal[0].text.contains("404"))
    }

    // MARK: - L'état de page Nexus sur la fiche (A2-T6)

    /// **404** : la page est morte pour tous ses mods — même ceux dont
    /// l'erreur smapi.io n'était pas « found no » : ce que la page réponde
    /// n'existe plus pour quiconque la réclame.
    @Test func http404MarksEveryModOfTheTargetRemoved() {
        let t = target("32260", mods: [
            blocked("a.mod", name: "Forgotten Woods", installed: "1.5.0",
                    errors: [Self.foundNoNexus]),
            blocked("b.mod", name: "Autre blocage", installed: "1.0.0",
                    errors: ["has no valid versions"]),
        ])
        let outcome = NexusResume.applyPage(.error("http_404"), target: t,
                                            pageIndex: 0, found: [], settled: [], failures: 0)

        #expect(outcome.pageStates == ["a.mod": .removed, "b.mod": .removed])
    }

    /// **200 après « found no »** : la page vit mais est cachée — seuls les
    /// mods porteurs de cette erreur-là sont marqués indisponibles (mesuré
    /// réel : le mod 32260 caché répond 200, version 1.5.0).
    @Test func livingPageMarksSourceNotFoundModsUnavailable() {
        let t = target("32260", mods: [
            blocked("a.mod", name: "Caché", installed: "1.5.0",
                    errors: [Self.foundNoNexus]),
            blocked("b.mod", name: "Autre blocage", installed: "1.0.0",
                    errors: ["has no valid versions"]),
        ])
        let outcome = NexusResume.applyPage(success("1.5.0"), target: t,
                                            pageIndex: 0, found: [], settled: [], failures: 0)

        #expect(outcome.pageStates == ["a.mod": .unavailable])
    }

    /// Page vivante mais **sans version publiable** : un échec au sens
    /// verdict — et pourtant la page existe, cachée. L'état suit la page,
    /// pas le verdict.
    @Test func versionlessLivingPageStillMarksUnavailable() {
        let t = target("32260", mods: [
            blocked("a.mod", name: "Caché", installed: "1.5.0",
                    errors: [Self.foundNoNexus]),
        ])
        let outcome = NexusResume.applyPage(success("   "), target: t,
                                            pageIndex: 0, found: [], settled: [], failures: 0)

        #expect(outcome.failures == 1)
        #expect(outcome.pageStates == ["a.mod": .unavailable])
    }

    /// Une erreur hors 404 (503, transport…) ne dit rien de l'état de la
    /// page — ne rien marquer vaut mieux qu'affirmer à tort.
    @Test func otherHTTPCodesMarkNothing() {
        let t = target("32260", mods: [
            blocked("a.mod", name: "Caché", installed: "1.5.0",
                    errors: [Self.foundNoNexus]),
        ])
        let outcome = NexusResume.applyPage(.error("http_503"), target: t,
                                            pageIndex: 0, found: [], settled: [], failures: 0)

        #expect(outcome.pageStates.isEmpty)
    }

    /// L'élagage : un état ne vaut que pour un mod **installé** — la fiche
    /// d'un mod parti n'existe plus, et un badge orphelin ne doit pas
    /// ressusciter avec lui.
    @Test func pruneKeepsOnlyInstalledMods() {
        let states: [String: NexusPageState] = ["a.mod": .removed, "gone.mod": .unavailable]
        #expect(NexusPageState.prune(states, keeping: ["a.mod"]) == ["a.mod": .removed])
        #expect(NexusPageState.prune(states, keeping: []).isEmpty)
    }

    // MARK: - Fabrique commune

    private func row(_ uid: String, name: String,
                     latest: String) -> NexusUpdateChecker.ModUpdate {
        NexusUpdateChecker.ModUpdate(uniqueId: uid, name: name,
                                     installedVersion: "1.0.0", latestVersion: latest,
                                     nexusModId: "", url: "", uploadedTime: nil)
    }
}
