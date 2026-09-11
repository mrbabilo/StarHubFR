import Testing
import Foundation
@testable import StarHubTHCore

/// Les décisions de `applySmapiResults`, extraites du ViewModel (2026-09-11).
///
/// Chaque test épingle un comportement que le code déplacé portait sans le
/// vérifier : la classification (suggestion / erreur / bloqué), le filet
/// « sans réponse » (override manuel, puis dump Pathoschild, sinon silence),
/// la fusion avec le cache plat — « absent de la réponse » n'est pas « à
/// jour » — et la fusion avec purge des verdicts de compatibilité.
struct SmapiVerdictsTests {

    // MARK: - Fabriques — les constructeurs réels, jamais des dictionnaires

    private func entry(_ id: String,
                       updateKeys: [String] = [],
                       installedVersion: String = "1.0.0") -> SmapiUpdateRequest.Entry {
        SmapiUpdateRequest.Entry(id: id, updateKeys: updateKeys,
                                 installedVersion: installedVersion)
    }

    private func suggestion(_ version: String, url: String? = nil) -> SmapiUpdateResponse.Version {
        SmapiUpdateResponse.Version(version: version, url: url)
    }

    private func mod(_ id: String,
                     suggested: SmapiUpdateResponse.Version? = nil,
                     metadata: SmapiUpdateResponse.Metadata? = nil,
                     errors: [String] = []) -> SmapiUpdateResponse.Mod {
        SmapiUpdateResponse.Mod(id: id, suggestedUpdate: suggested,
                                metadata: metadata, errors: errors)
    }

    private func metadata(name: String? = nil, nexusID: Int? = nil,
                          status: String? = nil, summary: String? = nil,
                          brokeIn: String? = nil) -> SmapiUpdateResponse.Metadata {
        SmapiUpdateResponse.Metadata(name: name, nexusID: nexusID, main: nil,
                                     unofficial: nil, compatibilityStatus: status,
                                     compatibilitySummary: summary, brokeIn: brokeIn)
    }

    private func anchor(_ uid: String, _ version: String,
                        facts: NexusInstallFacts? = nil) -> ModVersionAnchor {
        ModVersionAnchor(uniqueId: uid, anchoredVersion: version,
                         origin: .userAffirmed, anchoredAt: Date(), nexusFacts: facts)
    }

    private func row(_ uid: String, name: String, installed: String,
                     latest: String) -> NexusUpdateChecker.ModUpdate {
        NexusUpdateChecker.ModUpdate(uniqueId: uid, name: name,
                                     installedVersion: installed, latestVersion: latest,
                                     nexusModId: "", url: "", uploadedTime: nil)
    }

    private var verdict: ModCompatibility {
        ModCompatibility.from(status: "broken", brokeIn: "Stardew Valley 1.6",
                              summary: "cassé")!
    }

    // MARK: - Classification

    /// Une suggestion devient une ligne : le nom vient du parc (même mod, même
    /// nom d'un écran à l'autre), l'identifiant Nexus vient de smapi.io, la
    /// version installée est celle **affirmée** par l'entrée envoyée.
    @Test func suggestionBecomesUpdateRowWithResolvedNameAndNexusId() {
        let app = SmapiVerdicts.apply(
            [mod("a.mod", suggested: suggestion("2.0", url: "https://nexus/1"),
                 metadata: metadata(name: "Nom smapi.io", nexusID: 191))],
            entries: [entry("a.mod", installedVersion: "1.2.3")],
            installedNames: ["a.mod": "Nom du parc"],
            anchors: [:], pathoschildIndex: [:],
            previousRows: [], previousVerdicts: [:])

        #expect(app.updates.count == 1)
        let line = app.updates[0]
        #expect(line.uniqueId == "a.mod")
        #expect(line.name == "Nom du parc")
        #expect(line.installedVersion == "1.2.3")
        #expect(line.latestVersion == "2.0")
        #expect(line.nexusModId == "191")
        #expect(line.url == "https://nexus/1")
        #expect(line.uploadedTime == nil)
        // Un verdict ne se reprend pas : pas de reprise Nexus pour lui.
        #expect(app.blocked.isEmpty)
    }

    /// Sans `metadata.nexusID`, la clé déclarée porte l'identifiant — et sans
    /// clé non plus, la ligne reste, la sentinelle étant l'`UniqueID` (un mod
    /// suivi par GitHub n'a pas de page Nexus à ouvrir).
    @Test func nexusIdFallsBackToDeclaredKeyThenToUniqueId() {
        let app = SmapiVerdicts.apply(
            [mod("git.mod", suggested: suggestion("2.0")),
             mod("key.mod", suggested: suggestion("3.0"))],
            entries: [entry("git.mod"), entry("key.mod", updateKeys: ["Nexus: 23169@SwimItems"])],
            installedNames: [:], anchors: [:], pathoschildIndex: [:],
            previousRows: [], previousVerdicts: [:])

        #expect(app.updates.first { $0.uniqueId == "git.mod" }?.nexusModId == "git.mod")
        #expect(app.updates.first { $0.uniqueId == "key.mod" }?.nexusModId == "23169")
    }

    /// Une erreur **sans** suggestion pousse le mod vers la reprise Nexus, et
    /// c'est la version **affirmée** — l'ancre — qui commande la comparaison :
    /// une étiquette Nexus libre (« 5 ») que smapi.io refuse est remplacée par
    /// le manifeste envoyé, mais la page Nexus parle le vocabulaire de l'ancre.
    @Test func errorWithoutSuggestionGoesToFallbackWithAnchorCommandedVersion() {
        let facts = NexusInstallFacts(modId: "191", fileId: 2,
                                      fileUploadedAt: Date(timeIntervalSince1970: 100))
        let app = SmapiVerdicts.apply(
            [mod("b.mod", metadata: metadata(nexusID: 191),
                 errors: ["b.mod isn't in a valid format"])],
            entries: [entry("b.mod", updateKeys: ["Nexus:191"],
                            installedVersion: "5")],
            installedNames: ["b.mod": "Bloqué"],
            anchors: ["b.mod": anchor("b.mod", "1.0.1", facts: facts)],
            pathoschildIndex: [:],
            previousRows: [], previousVerdicts: [:])

        #expect(app.updates.isEmpty)
        #expect(app.unverifiable.count == 1)
        #expect(app.unverifiable[0].name == "Bloqué")
        let blocked = app.blocked
        #expect(blocked.count == 1)
        #expect(blocked[0].installedVersion == "1.0.1")
        #expect(blocked[0].declaredKeys == ["Nexus:191"])
        #expect(blocked[0].metadataNexusId == 191)
        #expect(blocked[0].heldFacts == facts)
        // Une erreur sans suggestion ne déclenche pas de ligne de reprise :
        // seul le filet « sans réponse » en rend une.
        #expect(app.report.resumeTriggered.isEmpty)
    }

    /// Une erreur **avec** suggestion n'est pas un choix : la suggestion reste
    /// un verdict et l'erreur reste affichée comme blocage. Les deux listes
    /// portent le mod — mais la reprise Nexus, elle, ne le reprend pas.
    @Test func errorWithSuggestionStaysUnverifiableAndStillYieldsUpdate() {
        let app = SmapiVerdicts.apply(
            [mod("c.mod", suggested: suggestion("2.0"),
                 errors: ["c.mod has no valid versions"])],
            entries: [entry("c.mod")],
            installedNames: ["c.mod": "Deux voies"],
            anchors: [:], pathoschildIndex: [:],
            previousRows: [], previousVerdicts: [:])

        #expect(app.updates.count == 1)
        #expect(app.unverifiable.count == 1)
        #expect(app.blocked.isEmpty)
    }

    /// Les invérifiables sont triés par nom, ex æquo départagés par
    /// `UniqueID` : `sorted` n'est pas stable, et deux homonymes changeaient
    /// d'ordre d'une passe à l'autre.
    @Test func unverifiableIsSortedByNameThenUniqueId() {
        let app = SmapiVerdicts.apply(
            [mod("z.mod", errors: ["z.mod found no update"]),
             mod("a.mod", errors: ["a.mod found no update"]),
             mod("m1.mod", errors: ["m1.mod found no update"]),
             mod("m2.mod", errors: ["m2.mod found no update"])],
            entries: [entry("z.mod"), entry("a.mod"), entry("m1.mod"), entry("m2.mod")],
            installedNames: ["z.mod": "Homo", "a.mod": "homo",
                             "m1.mod": "Homo", "m2.mod": "Homo"],
            anchors: [:], pathoschildIndex: [:],
            previousRows: [], previousVerdicts: [:])

        #expect(app.unverifiable.map(\.uniqueId) == ["a.mod", "m1.mod", "m2.mod", "z.mod"])
    }

    // MARK: - Filet « sans réponse »

    /// Un mod absent de la réponse n'est pas « à jour » : quand on connaît son
    /// identifiant Nexus par l'override **manuel**, la reprise part sur lui —
    /// le manuel prime sur tout.
    @Test func unansweredEntryPrefersManualOverrideOverPathoschild() {
        let app = SmapiVerdicts.apply(
            [],
            entries: [entry("d.mod", updateKeys: ["Nexus:191"])],
            installedNames: ["d.mod": "Silencieux"],
            anchors: [:], pathoschildIndex: ["d.mod": 999],
            previousRows: [], previousVerdicts: [:])

        #expect(app.blocked.count == 1)
        #expect(app.blocked[0].metadataNexusId == 191)
        #expect(app.blocked[0].errors == ["nexus: no smapi.io answer; resolved via manual override"])
        #expect(app.report.resumeTriggered == [SmapiVerdicts.ResumeTrigger(
            uniqueId: "d.mod", resolvedId: "191")])
    }

    /// Sans override manuel, le dump Pathoschild amorce la reprise.
    @Test func unansweredEntryFallsBackToPathoschildIndex() {
        let app = SmapiVerdicts.apply(
            [],
            entries: [entry("e.mod")],
            installedNames: [:],
            anchors: [:], pathoschildIndex: ["e.mod": 999],
            previousRows: [], previousVerdicts: [:])

        #expect(app.blocked.count == 1)
        #expect(app.blocked[0].metadataNexusId == 999)
        #expect(app.blocked[0].errors == ["nexus: no smapi.io answer; resolved via Pathoschild dump"])
        #expect(app.report.resumeTriggered == [SmapiVerdicts.ResumeTrigger(
            uniqueId: "e.mod", resolvedId: "999")])
    }

    /// Ni override ni dump : silence — le comportement historique. Le mod
    /// reste saisissable à la main dans la fiche.
    @Test func unansweredEntryWithoutAnyIdStaysSilent() {
        let app = SmapiVerdicts.apply(
            [],
            entries: [entry("f.mod")],
            installedNames: [:],
            anchors: [:], pathoschildIndex: [:],
            previousRows: [], previousVerdicts: [:])

        #expect(app.blocked.isEmpty)
        #expect(app.report.resumeTriggered.isEmpty)
    }

    /// Une entrée d'identifiant vide ne déclenche rien, même connue du dump :
    /// un `UniqueID` vide ne désigne personne.
    @Test func emptyEntryIdNeverTriggersFallback() {
        let app = SmapiVerdicts.apply(
            [],
            entries: [entry("")],
            installedNames: [:],
            anchors: [:], pathoschildIndex: ["": 191],
            previousRows: [], previousVerdicts: [:])

        #expect(app.blocked.isEmpty)
        #expect(app.report.resumeTriggered.isEmpty)
    }

    // MARK: - Fusion avec le cache plat

    /// La ligne précédente d'un mod non répondu **et encore installé** est
    /// conservée ; celle d'un mod disparu est retirée — et comptée, pour que
    /// le retrait se dise.
    @Test func previousRowSurvivesWhileRowOfRemovedModIsDropped() {
        let kept = row("g.mod", name: "Gardé", installed: "1.0.0", latest: "2.0")
        let gone = row("gone.mod", name: "Parti", installed: "1.0.0", latest: "2.0")
        let app = SmapiVerdicts.apply(
            [],
            entries: [entry("g.mod")],
            installedNames: [:],
            anchors: [:], pathoschildIndex: [:],
            previousRows: [kept, gone], previousVerdicts: [:])

        #expect(app.merged.map(\.uniqueId) == ["g.mod"])
        #expect(app.report.droppedCount == 1)
        #expect(app.report.unansweredCount == 1)
    }

    /// « Conservée » ne veut pas dire « à vie » : une ligne posée avant un
    /// « Je l'ai déjà » est re-confrontée à l'ancre, et une ligne que l'ancre
    /// ne rend plus due disparaît.
    @Test func previousRowThatAnchorNoLongerMakesDueIsNotKept() {
        let stale = row("h.mod", name: "Affirmé", installed: "1.0.0", latest: "2.0")
        let app = SmapiVerdicts.apply(
            [],
            entries: [entry("h.mod")],
            installedNames: [:],
            anchors: ["h.mod": anchor("h.mod", "2.0")],
            pathoschildIndex: [:],
            previousRows: [stale], previousVerdicts: [:])

        #expect(app.merged.isEmpty)
    }

    /// Une ligne répondues cette passe n'est pas re-conservée : la réponse la
    /// remplace.
    @Test func previousRowOfAnsweredModIsNotKept() {
        let superseded = row("i.mod", name: "Répondu", installed: "1.0.0", latest: "1.5")
        let app = SmapiVerdicts.apply(
            [mod("i.mod", suggested: suggestion("2.0"))],
            entries: [entry("i.mod")],
            installedNames: [:],
            anchors: [:], pathoschildIndex: [:],
            previousRows: [superseded], previousVerdicts: [:])

        #expect(app.merged.map(\.uniqueId) == ["i.mod"])
        #expect(app.merged[0].latestVersion == "2.0")
    }

    /// Le tri de `merged` : par nom, insensible à la casse ; ex æquo
    /// départagés par `UniqueID` — le tri de Swift n'est pas stable, et deux
    /// homonymes changeaient d'ordre d'une vérification à l'autre.
    /// (Déviation consignée : le code déplacé ne départageait pas.)
    @Test func mergedIsSortedByNameThenUniqueId() {
        let app = SmapiVerdicts.apply(
            [mod("z9.mod", suggested: suggestion("2.0")),
             mod("a1.mod", suggested: suggestion("2.0")),
             mod("j1.mod", suggested: suggestion("2.0")),
             mod("j2.mod", suggested: suggestion("2.0"))],
            entries: [entry("z9.mod"), entry("a1.mod"), entry("j1.mod"), entry("j2.mod")],
            installedNames: ["z9.mod": "Homonyme", "a1.mod": "homonyme",
                             "j1.mod": "Homonyme", "j2.mod": "Homonyme"],
            anchors: [:], pathoschildIndex: [:],
            previousRows: [], previousVerdicts: [:])

        #expect(app.merged.map(\.uniqueId) == ["a1.mod", "j1.mod", "j2.mod", "z9.mod"])
    }

    // MARK: - Verdicts de compatibilité

    /// Fusion, pas remplacement : un verdict précédent d'un mod non répondu
    /// reste ; un verdict contredit (smapi.io ne sait plus rien) est retiré ;
    /// tout verdict hors du parc envoyé est purgé — un mod désinstallé n'a
    /// plus de verdict à porter.
    @Test func verdictsMergeContradictRemovesAndPurgeRemoves() {
        let previous = ["kept.mod": verdict,
                        "contradicted.mod": verdict,
                        "gone.mod": verdict]
        let app = SmapiVerdicts.apply(
            [mod("kept.mod", metadata: metadata(status: "workaround",
                                                summary: "à la main")),
             mod("contradicted.mod", metadata: metadata(nexusID: 191))],
            entries: [entry("kept.mod"), entry("contradicted.mod")],
            installedNames: [:],
            anchors: [:], pathoschildIndex: [:],
            previousRows: [], previousVerdicts: previous)

        #expect(app.verdicts["kept.mod"]?.status == .workaround)
        #expect(app.verdicts["contradicted.mod"] == nil)
        #expect(app.verdicts["gone.mod"] == nil)
        #expect(app.verdicts.count == 1)
    }

    // MARK: - Le rapport

    /// Ce que l'appelant journalise : compte des réponses manquantes, compte
    /// des lignes retirées. La phrase reste au ViewModel.
    @Test func reportCountsMissingAnswersAndDroppedRows() {
        let app = SmapiVerdicts.apply(
            [mod("answered.mod", suggested: suggestion("2.0"))],
            entries: [entry("answered.mod"), entry("silent.mod")],
            installedNames: [:],
            anchors: [:], pathoschildIndex: [:],
            previousRows: [row("gone.mod", name: "Parti", installed: "1", latest: "2")],
            previousVerdicts: [:])

        #expect(app.report.unansweredCount == 0)
        #expect(app.report.droppedCount == 1)
        #expect(app.report.resumeTriggered.isEmpty)
    }
}
