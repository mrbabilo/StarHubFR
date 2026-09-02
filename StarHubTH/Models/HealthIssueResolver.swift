import Foundation

/// Agrège en une liste triée ce que l'app sait déjà de la santé du parc.
///
/// Pure et testée parce que le compte affiché en pied doit être **honnête** :
/// un compteur faux est pire qu'absent.
public enum HealthIssueResolver {

    public static func smapiIssues(_ diagnostics: SmapiDiagnostics?) -> [HealthIssue] {
        guard let d = diagnostics else { return [] }
        var issues: [HealthIssue] = []

        // `missingDeps` est un SOUS-ENSEMBLE de `failed`/`skipped` — le
        // parseur les y « promeut » (voir le commentaire sur
        // `missingDeps` dans SmapiLogDiagnostics.swift, et son `problemCount`
        // qui ne l'additionne pas séparément). Émettre une ligne par entrée
        // doublerait donc le compte affiché en pied de liste pour un même
        // mod. On enrichit à la place le détail de la ligne `failed`/
        // `skipped` d'origine, et on ne garde une ligne propre que pour le
        // cas défensif où le mod n'apparaît dans aucune des deux (ne devrait
        // jamais arriver côté parseur, mais l'info ne doit pas disparaître
        // si ça arrive quand même).
        let failedNames = Set(d.failed.map(\.name))
        let skippedNames = Set(d.skipped.map(\.name))

        for issue in d.failed {
            issues.append(HealthIssue(id: "smapi-failed-\(issue.name)",
                                      severity: .critical, source: .smapi,
                                      title: issue.name,
                                      detail: enrichedDetail(reason: issue.reason,
                                                             mod: issue.name,
                                                             missingDeps: d.missingDeps),
                                      action: .openTab("Logs")))
        }
        // Garde par SYMÉTRIE avec celle de `missingDeps` juste en dessous :
        // jamais vérifié sur un vrai journal (aucun n'en montre le cas), donc
        // posé par précaution plutôt qu'après coup. `skipped` porte le nom
        // SUIVI de sa version (« NEU Mod 1.0 ») alors que `failed` ne porte
        // que le nom du mod (« NEU Mod ») — un match exact entre les deux
        // ensembles de noms ne suffit pas, il faut reconnaître le suffixe de
        // version. Un `hasPrefix` NU sur-matcherait et supprimerait en
        // silence un mod `skipped` DIFFÉRENT dont le nom commence par celui
        // d'un mod `failed` (« Content Patcher » / « Content Patcher
        // Animations ») — un sous-comptage pire que le double-comptage visé
        // ici, parce que rien à l'écran ne signale la ligne manquante.
        // `isSameMod` ne retire donc que le DERNIER segment (la version) de
        // `skipped` avant de comparer.
        for issue in d.skipped where !failedNames.contains(where: {
            Self.isSameMod(failedName: $0, skippedName: issue.name)
        }) {
            issues.append(HealthIssue(id: "smapi-skipped-\(issue.name)",
                                      severity: .critical, source: .smapi,
                                      title: issue.name,
                                      detail: enrichedDetail(reason: issue.reason,
                                                             mod: issue.name,
                                                             missingDeps: d.missingDeps),
                                      action: .openTab("Logs")))
        }
        // Cas défensif seulement : un mod dont la dépendance manquante n'a
        // été promue dans aucune des deux listes ci-dessus.
        for dep in d.missingDeps where !failedNames.contains(dep.mod) && !skippedNames.contains(dep.mod) {
            issues.append(HealthIssue(id: "smapi-dep-\(dep.mod)-\(dep.missing)",
                                      severity: .critical, source: .smapi,
                                      title: dep.mod, detail: dep.missing,
                                      action: .openTab("Logs")))
        }
        // Conflits externes et mods marqués « broken » par SMAPI : des
        // problèmes de chargement avérés au sens de `problemCount`
        // (SmapiLogDiagnostics.swift), donc au même titre que failed/skipped.
        for name in d.externalConflicts {
            issues.append(HealthIssue(id: "smapi-conflict-\(name)",
                                      severity: .critical, source: .smapi,
                                      title: name, detail: nil,
                                      action: .openTab("Logs")))
        }
        for name in d.brokenMods {
            issues.append(HealthIssue(id: "smapi-broken-\(name)",
                                      severity: .critical, source: .smapi,
                                      title: name, detail: nil,
                                      action: .openTab("Logs")))
        }
        for notice in d.benignNotices {
            issues.append(HealthIssue(id: "smapi-benign-\(notice.kind.rawValue)-\(notice.mod ?? "-")",
                                      severity: .info, source: .smapi,
                                      title: notice.mod ?? notice.kind.rawValue,
                                      detail: notice.sample.isEmpty ? nil : notice.sample,
                                      action: .openTab("Logs")))
        }
        return issues
    }

    public static func keybindIssues(_ report: KeybindScanner.KeybindReport?) -> [HealthIssue] {
        guard let report else { return [] }
        var issues: [HealthIssue] = []
        for collision in report.collisions {
            let mods = collision.uses.map(\.modName).sorted().joined(separator: ", ")
            // `report.collisions` est indexé PAR combo : les deux mêmes mods
            // peuvent se disputer deux touches différentes (banal sur ~900
            // mods) — sans le combo dans l'id, ces deux lignes distinctes
            // partageraient la même identité (piège `ForEach`, CLAUDE.md).
            // `KeybindCombo.buttons` est déjà dédupliqué et trié
            // (`KeybindCombo.init?`), donc cette représentation est stable
            // entre deux résolutions.
            let comboKey = collision.combo.buttons.joined(separator: "+")
            issues.append(HealthIssue(id: "keybind-collision-\(comboKey)-\(mods)",
                                      severity: .warning, source: .keybind,
                                      title: mods, detail: nil,
                                      action: .openTab("Mods")))
        }
        for conflict in report.gameConflicts {
            let mods = conflict.uses.map(\.modName).sorted().joined(separator: ", ")
            issues.append(HealthIssue(id: "keybind-game-\(conflict.control.name)-\(mods)",
                                      severity: .warning, source: .keybind,
                                      title: mods, detail: conflict.control.name,
                                      action: .openTab("Mods")))
        }
        return issues
    }

    /// `ModConflictPair.first`/`.second` sont des `folderName` — pas des noms
    /// de mods. Les lignes voisines (raccourcis, SMAPI) affichent déjà des
    /// noms de mods : sans résolution, un conflit nommerait ses mods d'une
    /// troisième façon dans la même liste. `displayName` porte cette
    /// résolution — le ViewModel est seul à connaître `[ModItem]`, mais la
    /// RÈGLE (dossier → nom, repli sur le dossier si le mod est introuvable)
    /// reste ici, en un seul endroit, comme l'ancien `ModConflictSection.
    /// displayName(_:)` qu'elle remplace. Identité (`id`) construite sur les
    /// `folderName` bruts, jamais sur le nom résolu : elle doit rester stable
    /// même si un nom affiché change.
    public static func conflictIssues(_ conflicts: [ModConflictPair],
                                      displayName: (String) -> String = { $0 }) -> [HealthIssue] {
        conflicts.map { pair in
            HealthIssue(id: "conflict-\(pair.first)-\(pair.second)",
                        severity: .critical, source: .modConflict,
                        title: "\(displayName(pair.first)) · \(displayName(pair.second))",
                        detail: nil,
                        action: .openTab("Mods"))
        }
    }

    /// Tri **stable** par gravité décroissante : à gravité égale, l'ordre de
    /// production (`smapiIssues` puis `keybindIssues` puis `conflictIssues`)
    /// est conservé, sinon les lignes sauteraient d'un rafraîchissement à
    /// l'autre. La clé secondaire `-offset` encode cette préservation
    /// explicitement — elle ne dépend pas de la stabilité, non garantie par
    /// la doc, de `Array.sorted`.
    public static func resolve(diagnostics: SmapiDiagnostics?,
                               keybindReport: KeybindScanner.KeybindReport?,
                               conflicts: [ModConflictPair],
                               displayName: (String) -> String = { $0 }) -> [HealthIssue] {
        let all = smapiIssues(diagnostics)
            + keybindIssues(keybindReport)
            + conflictIssues(conflicts, displayName: displayName)
        return all.enumerated()
            .sorted { ($0.element.severity, -$0.offset) > ($1.element.severity, -$1.offset) }
            .map(\.element)
    }

    /// `skippedIssue(fromLine:)` (SmapiLogDiagnostics.swift) construit son
    /// nom comme `<nom du mod> <version> because …` : tout avant le DERNIER
    /// espace est le nom, jamais plus. Retirer un préfixe suffirait à faire
    /// disparaître un mod dont le nom en contient un autre en entier
    /// (« Content Patcher Animations » contient « Content Patcher »).
    private static func isSameMod(failedName: String, skippedName: String) -> Bool {
        if failedName == skippedName { return true }
        guard let lastSpace = skippedName.lastIndex(of: " ") else { return false }
        return skippedName[skippedName.startIndex..<lastSpace] == failedName
    }

    /// Ajoute le nom de la dépendance manquante au détail, sauf s'il y
    /// figure déjà — le parseur reformule souvent la raison d'un `failed`
    /// pour l'y inclure (`"requires X (not installed)"`), et un ajout
    /// systématique répéterait alors la même information deux fois sur la
    /// même ligne.
    private static func enrichedDetail(reason: String, mod: String,
                                       missingDeps: [SmapiDiagnostics.MissingDep]) -> String {
        var detail = reason
        for dep in missingDeps where dep.mod == mod && !detail.contains(dep.missing) {
            detail += " (\(dep.missing))"
        }
        return detail
    }
}
