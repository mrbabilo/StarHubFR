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

    /// Revue globale de branche, bloquant 2 : personne n'avait vérifié si un
    /// même mod peut apparaître à la fois dans `failed` ET `skipped`. Garde
    /// posée par SYMÉTRIE avec celle de `missingDeps` ci-dessus, sans
    /// attendre un journal qui le prouve. `skipped` porte le nom SUIVI de sa
    /// version (« NEU Mod 1.0 »), `failed` ne porte que le nom du mod
    /// (« NEU Mod ») — un match exact entre les deux ensembles de noms ne
    /// suffit pas, d'où le préfixe. Construit par le VRAI parseur, comme
    /// `failedModWithMissingDependencyProducesOneCriticalLine` ci-dessus.
    @Test func modInBothFailedAndSkippedProducesOneCriticalLine() {
        let log = """
        [00:00:00 TRACE SMAPI]    NEU Mod (from Mods/NEU/NEU.dll, ID: neu.mod)...
        [00:00:01 ERROR NEU Mod] Failed: requires mods which aren't installed (Some.Framework)
        [00:00:02 ERROR SMAPI]    Skipped mods
        [00:00:02 ERROR SMAPI]       - NEU Mod 1.0 because it requires mods which aren't installed (Some.Framework)
        """
        let d = SmapiDiagnostics.parse(logContent: log)
        // Le journal confirme bien l'hypothèse : le même mod est promu dans
        // failed ET skipped, sous deux noms différents.
        #expect(d.failed.contains { $0.name == "NEU Mod" })
        #expect(d.skipped.contains { $0.name == "NEU Mod 1.0" })

        let issues = HealthIssueResolver.smapiIssues(d)
        let neu = issues.filter { $0.title == "NEU Mod" || $0.title == "NEU Mod 1.0" }
        // Une seule ligne critique pour ce mod, jamais deux sous deux titres.
        #expect(neu.count == 1)
    }

    /// Contre-épreuve de la garde ci-dessus : un `hasPrefix` NU (sans
    /// reconnaître que seul le DERNIER segment de `skipped` est la version)
    /// sur-matche et supprime silencieusement un mod `skipped` légitime dont
    /// le nom commence par celui d'un mod `failed` différent — un sous-
    /// comptage, pire que le double-comptage que la garde corrige, parce que
    /// rien à l'écran ne signale la ligne manquante. Cas réel plausible sur
    /// le parc de l'auteur (« Content Patcher » / « Content Patcher
    /// Animations »).
    @Test func differentModsSharingANamePrefixBothProduceCriticalLines() {
        let log = """
        [00:00:00 TRACE SMAPI]    Content Patcher (from Mods/CP/CP.dll, ID: pathoschild.contentpatcher)...
        [00:00:01 ERROR Content Patcher] Failed: something broke
        [00:00:02 ERROR SMAPI]    Skipped mods
        [00:00:02 ERROR SMAPI]       - Content Patcher Animations 1.2 because it requires mods which aren't installed (Some.Lib)
        """
        let d = SmapiDiagnostics.parse(logContent: log)
        #expect(d.failed.contains { $0.name == "Content Patcher" })
        #expect(d.skipped.contains { $0.name == "Content Patcher Animations 1.2" })

        let issues = HealthIssueResolver.smapiIssues(d)
        let critical = issues.filter { $0.severity == .critical }
        // Deux mods DISTINCTS en échec : deux lignes, jamais une seule.
        #expect(critical.contains { $0.title == "Content Patcher" })
        #expect(critical.contains { $0.title == "Content Patcher Animations 1.2" })
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

    /// Revue globale de branche, bloquant 4 : les lignes de raccourcis
    /// affichent des noms de mods, les lignes de conflit affichaient des
    /// `folderName` bruts (`ModConflictPair`) — deux vocabulaires dans la
    /// même liste. `displayName` doit résoudre dossier → nom de mod, avec
    /// repli sur le dossier si le mod est introuvable (mod désinstallé entre
    /// la détection et l'affichage).
    @Test func conflictTitleUsesResolvedModNamesNotFolderNames() {
        let names = ["sve.folder": "Stardew Valley Expanded", "cp.folder": "Content Patcher"]
        let issues = HealthIssueResolver.conflictIssues(
            [ModConflictPair("sve.folder", "cp.folder")],
            displayName: { names[$0] ?? $0 })
        #expect(issues.first?.title == "Content Patcher · Stardew Valley Expanded")
    }

    /// Sans résolveur (défaut), le comportement d'avant est conservé —
    /// aucun appelant existant ne doit changer de sortie.
    @Test func conflictTitleFallsBackToFolderNameWithoutResolver() {
        let issues = HealthIssueResolver.conflictIssues([ModConflictPair("A", "B")])
        #expect(issues.first?.title == "A · B")
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

    /// Ronde de correction 1 — `report.collisions` est indexé PAR combo :
    /// les deux mêmes mods peuvent se disputer deux touches différentes
    /// (banal sur ~900 mods). Sans le combo dans l'id, ces deux lignes
    /// distinctes partageraient la même identité — le piège `ForEach`
    /// documenté dans CLAUDE.md (une identité dupliquée fait fuiter l'état
    /// d'une ligne vers une autre).
    @Test func collisionIdentityDiffersOnDifferentKeyBetweenSameMods() {
        let a = KeybindScanner.ModScan(
            id: "a.Mod1", name: "Mod 1", isActive: true,
            tree: tree(["HotkeyOne": .string("F8 + LeftControl"),
                        "HotkeyTwo": .string("F9 + LeftControl")]))
        let b = KeybindScanner.ModScan(
            id: "b.Mod2", name: "Mod 2", isActive: true,
            tree: tree(["HotkeyOne": .string("F8 + LeftControl"),
                        "HotkeyTwo": .string("F9 + LeftControl")]))
        let report = KeybindScanner.report(mods: [a, b])
        // Les deux mêmes mods, sur deux combos distincts : deux collisions
        // réelles, sinon le test ne prouve rien.
        #expect(report.collisions.count == 2)

        let issues = HealthIssueResolver.keybindIssues(report)
        #expect(issues.count == 2)
        #expect(Set(issues.map(\.id)).count == 2)
    }

    /// Ronde de correction 1 — `gameConflicts` n'était exercée par aucun
    /// test : toute fixture à deux boutons (les collisions ci-dessus) ne
    /// peut structurellement pas y entrer, `report(mods:)` n'indexant les
    /// contrôles du jeu que pour un combo à bouton unique. Bouton "W" choisi
    /// dans `GameControlDefaults.controls` (`moveUpButton`).
    @Test func gameControlConflictProducesAWarningRow() {
        let a = KeybindScanner.ModScan(id: "a.Mod1", name: "Mod 1", isActive: true,
                                       tree: tree(["Hotkey": .string("W")]))
        let report = KeybindScanner.report(mods: [a])
        // Sinon le test serait creux, exactement le défaut corrigé ici.
        #expect(!report.gameConflicts.isEmpty)

        let issues = HealthIssueResolver.keybindIssues(report)
        #expect(issues.contains {
            $0.source == .keybind && $0.severity == .warning
                && $0.detail == "moveUpButton"
        })
    }

    /// Étend l'invariant `problemCount` (déjà prouvé ci-dessus sur les
    /// seules collisions) aux DEUX familles à la fois : une fixture qui
    /// produit à la fois une collision entre mods et un conflit avec un
    /// contrôle par défaut du jeu.
    @Test func keybindRowCountMatchesProblemCountAcrossBothFamilies() {
        let a = KeybindScanner.ModScan(
            id: "a.Mod1", name: "Mod 1", isActive: true,
            tree: tree(["Shortcut": .string("F8 + LeftControl"),
                        "Hotkey": .string("W")]))
        let b = KeybindScanner.ModScan(
            id: "b.Mod2", name: "Mod 2", isActive: true,
            tree: tree(["Shortcut": .string("F8 + LeftControl")]))
        let report = KeybindScanner.report(mods: [a, b])
        #expect(!report.collisions.isEmpty)
        #expect(!report.gameConflicts.isEmpty)

        let issues = HealthIssueResolver.resolve(
            diagnostics: nil, keybindReport: report, conflicts: [])
        #expect(issues.filter { $0.source == .keybind }.count == report.problemCount)
    }
}
