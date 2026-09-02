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

    /// H-T6b : une ligne SMAPI « failed »/« skipped » nomme un vrai mod du
    /// parc — l'action doit ouvrir SA fiche, pas la liste ni un onglet
    /// générique.
    @Test func failedAndSkippedModsOpenTheirModFiche() {
        let issues = HealthIssueResolver.smapiIssues(Self.diagnostics())
        #expect(issues.first { $0.title == "SVE" }?.actions == [.openMod(query: "SVE")])
        #expect(issues.first { $0.title == "Automate" }?.actions == [.openMod(query: "Automate")])
    }

    /// Le VRAI parseur (`SmapiDiagnostics.parse`, pas une fixture à la main)
    /// nomme un mod `skipped` « <nom> <version> » — le titre le garde, mais
    /// la cible de l'action doit désigner le mod NU, celui que connaît
    /// `ModFocusResolver` : sans le nettoyage de version, cette ligne
    /// n'ouvrait jamais sa fiche (trouvé en revue — aucune fixture posée à la
    /// main dans les autres tests ne porte de nom versionné, donc aucune
    /// n'aurait pu l'exercer).
    @Test func skippedModActionTargetsTheBareNameNotTheVersionedTitle() {
        let log = """
        [00:00:02 ERROR SMAPI]    Skipped mods
        [00:00:02 ERROR SMAPI]       - AnotherMod 1.0 because it requires mods which aren't installed (Some.Library)
        """
        let d = SmapiDiagnostics.parse(logContent: log)
        #expect(d.skipped.contains { $0.name == "AnotherMod 1.0" })

        let issues = HealthIssueResolver.smapiIssues(d)
        let row = issues.first { $0.title == "AnotherMod 1.0" }
        #expect(row?.actions == [.openMod(query: "AnotherMod")])
    }

    /// Contre-épreuve : un mod dont le nom se termine par un mot ordinaire
    /// (pas une version) ne doit pas perdre ce mot — seul un dernier segment
    /// qui COMMENCE par un chiffre est retiré.
    @Test func skippedModNameEndingInAWordKeepsItsFullName() {
        let log = """
        [00:00:02 ERROR SMAPI]    Skipped mods
        [00:00:02 ERROR SMAPI]       - Content Patcher Animations 1.2 because it requires mods which aren't installed (Some.Lib)
        """
        let d = SmapiDiagnostics.parse(logContent: log)
        let issues = HealthIssueResolver.smapiIssues(d)
        let row = issues.first { $0.title == "Content Patcher Animations 1.2" }
        #expect(row?.actions == [.openMod(query: "Content Patcher Animations")])
    }

    /// La dépendance manquante défensive nomme aussi un vrai mod : même
    /// cible que failed/skipped.
    @Test func missingDependencyDefensiveCaseOpensTheModFiche() {
        let issues = HealthIssueResolver.smapiIssues(Self.diagnostics())
        #expect(issues.first { $0.title == "RSV" }?.actions == [.openMod(query: "RSV")])
    }

    /// `externalConflicts` nomme un outil externe (RivaTuner…), jamais un mod
    /// du parc : `ModFocusResolver` n'y trouverait rien, la fiche n'a pas de
    /// sens — la seule cible utile reste le journal.
    @Test func externalConflictOpensLogsNotAModFiche() {
        var d = Self.diagnostics()
        d.externalConflicts = ["RivaTuner Statistics Server"]
        let issues = HealthIssueResolver.smapiIssues(d)
        #expect(issues.first { $0.title == "RivaTuner Statistics Server" }?.actions
                == [.openLogs(searchText: "RivaTuner Statistics Server")])
    }

    /// `brokenMods`, lui, nomme un vrai mod marqué cassé par SMAPI : la fiche
    /// a un sens, contrairement à `externalConflicts` ci-dessus.
    @Test func brokenModOpensItsModFiche() {
        var d = Self.diagnostics()
        d.brokenMods = ["Old Broken Mod"]
        let issues = HealthIssueResolver.smapiIssues(d)
        #expect(issues.first { $0.title == "Old Broken Mod" }?.actions
                == [.openMod(query: "Old Broken Mod")])
    }

    /// Une notice bénigne qui NOMME un mod (`notice.mod` non nil) ouvre sa
    /// fiche, comme n'importe quelle autre ligne SMAPI qui désigne un mod
    /// réel. Ici SANS second bouton : l'exemple de la fixture se réduit à son
    /// ellipse de troncature, donc il n'y a rien à chercher dans le journal —
    /// un bouton de plus n'y mènerait nulle part (voir `benignActions`).
    @Test func benignNoticeWithAModOpensItsFiche() {
        let issues = HealthIssueResolver.smapiIssues(Self.diagnostics())
        #expect(issues.first { $0.title == "CJB" }?.actions == [.openMod(query: "CJB")])
    }

    /// Une notice bénigne SANS mod (Galaxy…) ne peut viser aucune fiche :
    /// repli sur les journaux, recherche sur l'exemple brut conservé par le
    /// parseur.
    @Test func benignNoticeWithoutAModOpensLogsOnItsSample() {
        var d = Self.diagnostics()
        d.benignNotices = [.init(kind: .galaxyAuth, mod: nil, count: 1,
                                 sample: "GOG Galaxy 64 couldn't be initialized")]
        let issues = HealthIssueResolver.smapiIssues(d)
        #expect(issues.first { $0.severity == .info }?.actions
                == [.openLogs(searchText: "GOG Galaxy 64 couldn't be initialized")])
    }

    /// Repli au repli : sans mod ET sans exemple, la recherche porte au moins
    /// sur le genre de notice — jamais une action vide.
    @Test func benignNoticeWithoutAModOrSampleFallsBackToItsKind() {
        var d = Self.diagnostics()
        d.benignNotices = [.init(kind: .galaxyAuth, mod: nil, count: 1, sample: "")]
        let issues = HealthIssueResolver.smapiIssues(d)
        let notice = issues.first { $0.severity == .info }
        #expect(notice?.title == "galaxyAuth")
        #expect(notice?.actions == [.openLogs(searchText: "galaxyAuth")])
    }

    /// `SmapiLogDiagnostics.evidence(from:)` tronque au-delà de 160
    /// caractères et ajoute un « … » — absent de la ligne réelle du journal.
    /// `LogsView` filtre par sous-chaîne exacte : chercher le texte AVEC son
    /// ellipse ne trouverait donc jamais rien. La cible doit le retirer.
    @Test func benignNoticeSampleTruncationMarkerIsStrippedFromTheSearch() {
        var d = Self.diagnostics()
        d.benignNotices = [.init(kind: .apiIntegration, mod: nil, count: 1,
                                 sample: "Some very long evidence line…")]
        let issues = HealthIssueResolver.smapiIssues(d)
        let notice = issues.first { $0.title == "apiIntegration" }
        #expect(notice?.actions == [.openLogs(searchText: "Some very long evidence line")])
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

    /// H-T6b : le bouton d'une ligne de conflit doit ouvrir la fiche d'un des
    /// deux mods en cause, pas la liste entière (`Mods`). `ModConflictPair`
    /// n'indexe que des `folderName` — l'action doit en porter un, jamais un
    /// nom résolu (le résolveur de fiche attend un dossier ou un nom, jamais
    /// un libellé composé « A · B »).
    @Test func conflictActionOpensOneOfTheTwoModsByFolderName() {
        // `ModConflictPair` trie ses deux dossiers à la construction :
        // "cp.folder" < "sve.folder", donc `.first == "cp.folder"`.
        let issues = HealthIssueResolver.conflictIssues([ModConflictPair("sve.folder", "cp.folder")])
        #expect(issues.first?.actions == [.openMod(query: "cp.folder")])
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

    /// H-T6b : une collision oppose au moins deux mods — le bouton ne peut en
    /// désigner qu'UN, le premier par ordre alphabétique (même tri que le
    /// titre affiché), jamais l'onglet Mods générique.
    @Test func collisionActionOpensTheFirstModAlphabetically() {
        let a = KeybindScanner.ModScan(id: "a.Mod1", name: "Zebra Mod", isActive: true,
                                       tree: tree(["HotkeyOne": .string("F8 + LeftControl")]))
        let b = KeybindScanner.ModScan(id: "b.Mod2", name: "Alpha Mod", isActive: true,
                                       tree: tree(["HotkeyOne": .string("F8 + LeftControl")]))
        let report = KeybindScanner.report(mods: [a, b])
        let issues = HealthIssueResolver.keybindIssues(report)
        let collision = issues.first { $0.detail == nil }
        #expect(collision?.actions == [.openMod(query: "Alpha Mod")])
    }

    /// Même règle pour un conflit avec un contrôle par défaut du jeu.
    @Test func gameConflictActionOpensTheOffendingMod() {
        let a = KeybindScanner.ModScan(id: "a.Mod1", name: "Mod 1", isActive: true,
                                       tree: tree(["Hotkey": .string("W")]))
        let report = KeybindScanner.report(mods: [a])
        let issues = HealthIssueResolver.keybindIssues(report)
        #expect(issues.first { $0.detail == "moveUpButton" }?.actions
                == [.openMod(query: "Mod 1")])
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

// MARK: - H-T6c — une notice sans mod porte un titre lisible

@Test func aModlessBenignNoticeCarriesATranslatableTitleKey() {
    // Vraie ligne du journal de l'auteur : la seule notice bénigne sans mod
    // qui subsiste. Sans clé, l'écran affichait le rawValue de l'enum
    // (« galaxyAuth ») comme titre de ligne — un nom de symbole, en anglais,
    // au milieu d'une UI traduite.
    let log = "[17:40:41 ERROR game] Galaxy auth failure: FAILURE_REASON_GALAXY_SERVICE_NOT_SIGNED_IN"
    let d = SmapiDiagnostics.parse(logContent: log)
    let issues = HealthIssueResolver.smapiIssues(d)
    #expect(issues.count == 1)
    #expect(issues.first?.titleKey == L10n.Health.benignTitleGalaxy)
}

@Test func aBenignNoticeNamingItsModHasNoTitleKey() {
    // Contre-épreuve : quand la notice nomme un mod, le titre EST ce nom —
    // une donnée, jamais une clé à traduire.
    let log = "[17:40:22 TRACE Farm Type Manager (FTM)] API not found: Expanded Preconditions Utility (EPU)."
    let d = SmapiDiagnostics.parse(logContent: log)
    let issues = HealthIssueResolver.smapiIssues(d)
    #expect(issues.first?.title == "Farm Type Manager (FTM)")
    #expect(issues.first?.titleKey == nil)
}

@Test func everyBenignKindHasItsOwnTitleKey() {
    // Un `switch` exhaustif dériverait en silence si un genre était ajouté
    // sans clé : ce test verrouille l'unicité, donc l'exhaustivité.
    let keys = SmapiDiagnostics.BenignNotice.Kind.allCases.map(\.l10nKey)
    #expect(Set(keys).count == keys.count)
}

// MARK: - Une ligne peut offrir DEUX chemins

@Test func aBenignNoticeNamingAModOffersBothItsFicheAndTheLog() {
    // Demande de l'auteur : sur une information, l'accès au journal s'ajoute
    // à l'accès au mod — la fiche dit ce qu'est le mod, le journal dit ce
    // qui s'est passé. Les deux répondent à des questions différentes.
    let log = "[17:40:22 TRACE Farm Type Manager (FTM)] API not found: Expanded Preconditions Utility (EPU)."
    let d = SmapiDiagnostics.parse(logContent: log)
    let issues = HealthIssueResolver.smapiIssues(d)
    #expect(issues.first?.actions == [
        .openMod(query: "Farm Type Manager (FTM)"),
        .openLogs(searchText: "API not found: Expanded Preconditions Utility (EPU).")
    ])
}

@Test func aBenignNoticeWithoutAModStillOffersOnlyTheLog() {
    // Contre-épreuve : sans mod il n'y a pas de fiche à ouvrir — une seule
    // action, pas un bouton mort à côté.
    let log = "[17:40:41 ERROR game] Galaxy auth failure: FAILURE_REASON_GALAXY_SERVICE_NOT_SIGNED_IN"
    let d = SmapiDiagnostics.parse(logContent: log)
    #expect(HealthIssueResolver.smapiIssues(d).first?.actions.count == 1)
}

@Test func aCriticalRowKeepsASingleAction() {
    // Le doublement vise les INFORMATIONS. Une ligne critique garde son
    // chemin unique : deux boutons sur une urgence diluent le geste à faire.
    let log = """
    [17:39:53 TRACE SMAPI]    Automate (from Mods/Automate/Automate.dll)...
    [17:39:53 ERROR SMAPI]    Failed: something broke
    """
    let d = SmapiDiagnostics.parse(logContent: log)
    let critical = HealthIssueResolver.smapiIssues(d).filter { $0.severity == .critical }
    #expect(critical.allSatisfy { $0.actions.count == 1 })
}
