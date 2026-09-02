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
        for issue in d.skipped {
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
