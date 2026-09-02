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

@Suite("HealthIssueResolver — agrégation")
struct HealthIssueResolverAggregateTests {

    /// Reprend exactement le patron de `Tests/KeybindTests/KeybindScannerTests.swift`
    /// (`ConfigJSONTree.Object` n'a pas de littéral de dictionnaire — un
    /// `.object([...])` direct ne compile pas) plutôt que de le réécrire.
    private func tree(_ pairs: [String: ConfigJSONTree.Value]) -> ConfigJSONTree.Value {
        .object(ConfigJSONTree.Object(pairs.map { ($0.key, $0.value) }))
    }

    /// Le tri EST la fonctionnalité : sans lui, l'écran ne dit pas par où
    /// commencer, ce qui était le défaut d'origine.
    @Test func criticalIssuesComeFirst() {
        var d = SmapiDiagnostics()
        d.benignNotices = [.init(kind: .galaxyAuth, mod: nil, count: 1, sample: "")]
        d.failed = [.init(name: "SVE", reason: "r")]
        let issues = HealthIssueResolver.resolve(
            diagnostics: d, keybindReport: nil,
            conflicts: [ModConflictPair("A", "B")])
        #expect(issues.first?.severity == .critical)
        #expect(issues.last?.severity == .info)
        // Décroissant, sans exception.
        #expect(zip(issues, issues.dropFirst()).allSatisfy { $0.severity >= $1.severity })
    }

    /// Une paire de mods en conflit actif empêche le jeu de charger
    /// correctement : critique, et une ligne par paire.
    @Test func eachConflictPairIsItsOwnCriticalRow() {
        let issues = HealthIssueResolver.resolve(
            diagnostics: nil, keybindReport: nil,
            conflicts: [ModConflictPair("A", "B"), ModConflictPair("C", "D")])
        #expect(issues.count == 2)
        #expect(issues.allSatisfy { $0.severity == .critical && $0.source == .modConflict })
    }

    /// Invariant : le nombre de lignes « raccourci » vaut exactement
    /// `problemCount`, que la barre latérale affiche déjà.
    ///
    /// Le rapport est produit par un **vrai scan**, comme dans
    /// `Tests/KeybindTests/KeybindScannerTests.swift` — assembler un
    /// `KeybindReport` à la main demanderait de connaître ses onze champs et
    /// se périmerait au premier ajout.
    @Test func keybindRowsMatchTheReportProblemCount() {
        let a = KeybindScanner.ModScan(id: "a.Mod1", name: "Mod 1", isActive: true,
                                       tree: tree(["Shortcut": .string("F8 + LeftControl")]))
        let b = KeybindScanner.ModScan(id: "b.Mod2", name: "Mod 2", isActive: true,
                                       tree: tree(["Shortcut": .string("F8 + LeftControl")]))
        let report = KeybindScanner.report(mods: [a, b])
        #expect(report.problemCount > 0)   // sinon le test ne prouve rien

        let issues = HealthIssueResolver.resolve(
            diagnostics: nil, keybindReport: report, conflicts: [])
        #expect(issues.filter { $0.source == .keybind }.count == report.problemCount)
        #expect(issues.filter { $0.source == .keybind }.allSatisfy { $0.severity == .warning })
    }

    @Test func everythingEmptyYieldsNoIssues() {
        #expect(HealthIssueResolver.resolve(diagnostics: nil, keybindReport: nil,
                                            conflicts: []).isEmpty)
    }

    /// `allSatisfy { severity >= severity }` (ci-dessus) passerait même si le
    /// tri mélangeait les deux groupes critiques entre eux — SMAPI et
    /// conflits ont la même gravité. Ce test prouve la STABILITÉ réelle :
    /// à gravité égale, l'ordre de sortie est EXACTEMENT l'ordre de
    /// production (`smapiIssues` puis `keybindIssues` puis `conflictIssues`,
    /// chacun dans son propre ordre d'entrée), pas seulement globalement
    /// décroissant.
    @Test func tiesPreserveExactProductionOrderAcrossSources() {
        var d = SmapiDiagnostics()
        d.failed = [.init(name: "Z-Mod", reason: "r1"), .init(name: "A-Mod", reason: "r2")]
        let issues = HealthIssueResolver.resolve(
            diagnostics: d, keybindReport: nil,
            conflicts: [ModConflictPair("Y", "X"), ModConflictPair("B", "C")])
        // Quatre lignes, toutes critiques, dans l'ordre de production :
        // les deux SMAPI (ordre de `d.failed`), puis les deux paires de
        // conflit (ordre de `conflicts`) — jamais entrelacées.
        #expect(issues.map(\.title) == ["Z-Mod", "A-Mod", "X · Y", "B · C"])
    }
}
