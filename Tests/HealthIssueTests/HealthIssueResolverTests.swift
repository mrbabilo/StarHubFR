import Testing
@testable import StarHubTHCore

@Suite("HealthIssueResolver — SMAPI")
struct HealthIssueResolverSmapiTests {

    static func diagnostics() -> SmapiDiagnostics {
        var d = SmapiDiagnostics()
        d.failed = [.init(name: "SVE", reason: "manque une dépendance")]
        d.skipped = [.init(name: "Automate", reason: "version incompatible")]
        d.missingDeps = [.init(mod: "RSV", missing: "SpaceCore")]
        d.benignNotices = [.init(kind: .optionalModMissing, mod: "CJB",
                                 count: 1, sample: "…")]
        return d
    }

    /// Un mod qui n'est pas chargé est critique : le joueur ne l'a pas.
    @Test func failedAndSkippedModsAreCritical() {
        let issues = HealthIssueResolver.smapiIssues(Self.diagnostics())
        let critical = issues.filter { $0.severity == .critical }
        #expect(critical.contains { $0.title == "SVE" })
        #expect(critical.contains { $0.title == "Automate" })
    }

    /// Le parseur range déjà les dépendances *optionnelles* en notice bénigne :
    /// ce qui reste dans `missingDeps` est dur, donc critique.
    @Test func missingHardDependencyIsCritical() {
        let issues = HealthIssueResolver.smapiIssues(Self.diagnostics())
        #expect(issues.contains { $0.severity == .critical && $0.title == "RSV" })
    }

    /// « Bénin » est le mot du parseur lui-même — ni panne, ni geste à faire.
    /// Une seule notice dans la fixture : le compte doit rester exact, pas
    /// seulement « au moins une ligne info ».
    @Test func benignNoticesAreInformation() {
        let issues = HealthIssueResolver.smapiIssues(Self.diagnostics())
        let info = issues.filter { $0.severity == .info }
        #expect(info.count == 1)
        #expect(info.first?.title == "CJB")
    }

    @Test func noDiagnosticsYieldsNoIssues() {
        #expect(HealthIssueResolver.smapiIssues(nil).isEmpty)
    }

    /// Deux relectures du même journal doivent donner les mêmes identités,
    /// sans quoi les lignes sautent d'un rafraîchissement à l'autre.
    @Test func identitiesAreStableAcrossTwoResolutions() {
        let first = HealthIssueResolver.smapiIssues(Self.diagnostics()).map(\.id)
        let second = HealthIssueResolver.smapiIssues(Self.diagnostics()).map(\.id)
        #expect(first == second)
        #expect(Set(first).count == first.count)  // pas de doublon d'identité
    }

    /// `externalConflicts` et `brokenMods` comptent dans `problemCount` du
    /// parseur au même titre que `failed`/`skipped` (voir
    /// SmapiLogDiagnostics.swift) : le résolveur doit les traduire aussi,
    /// sans quoi l'écran sous-estime les problèmes de chargement avérés.
    @Test func externalConflictsAndBrokenModsAreCritical() {
        var d = Self.diagnostics()
        d.externalConflicts = ["RivaTuner Statistics Server"]
        d.brokenMods = ["Old Broken Mod"]
        let issues = HealthIssueResolver.smapiIssues(d)
        let critical = issues.filter { $0.severity == .critical }
        #expect(critical.contains { $0.title == "RivaTuner Statistics Server" })
        #expect(critical.contains { $0.title == "Old Broken Mod" })
    }

    /// `missingDeps` est un SOUS-ENSEMBLE de `failed`/`skipped` — le parseur
    /// les y « promeut » (`SmapiDiagnostics.missingDeps`, doc et
    /// `problemCount`, qui ne l'additionne pas séparément). Une fixture
    /// écrite à la main peut placer un mod dans `missingDeps` sans le mettre
    /// dans `failed`/`skipped`, un état que le VRAI parseur ne produit
    /// jamais — c'est pour ça que ce test construit ses diagnostics via
    /// `SmapiDiagnostics.parse(logContent:)`, avec le journal de
    /// `promotesMissingDependenciesFromFailedAndSkipped`
    /// (Tests/SmapiLogDiagnosticsTests/SmapiLogDiagnosticsTests.swift), pour
    /// prouver qu'un mod en échec avec dépendance manquante ne produit
    /// qu'UNE seule ligne critique, pas deux.
    @Test func failedModWithMissingDependencyProducesOneCriticalLine() {
        let log = """
        [00:00:00 TRACE SMAPI]    NEU Mod (from Mods/NEU/NEU.dll, ID: neu.mod)...
        [00:00:01 ERROR NEU Mod] Failed: requires mods which aren't installed (Some.Framework)
        [00:00:02 ERROR SMAPI]    Skipped mods
        [00:00:02 ERROR SMAPI]       - AnotherMod 1.0 because it requires mods which aren't installed (Some.Library)
        """
        let d = SmapiDiagnostics.parse(logContent: log)
        // Le journal confirme bien l'hypothèse : chaque mod est promu dans
        // les deux listes.
        #expect(d.failed.contains { $0.name == "NEU Mod" })
        #expect(d.missingDeps.contains { $0.mod == "NEU Mod" })

        let issues = HealthIssueResolver.smapiIssues(d)
        let critical = issues.filter { $0.severity == .critical }

        let neu = critical.filter { $0.title == "NEU Mod" }
        #expect(neu.count == 1)
        #expect(neu.first?.detail?.contains("Some.Framework") == true)

        let another = critical.filter { $0.title == "AnotherMod 1.0" }
        #expect(another.count == 1)
        #expect(another.first?.detail?.contains("Some.Library") == true)

        // Deux mods en échec, deux lignes — jamais quatre.
        #expect(critical.count == 2)
    }
}
