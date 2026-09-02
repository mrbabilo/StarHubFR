import Foundation

/// Agrège en une liste triée ce que l'app sait déjà de la santé du parc.
///
/// Pure et testée parce que le compte affiché en pied doit être **honnête** :
/// un compteur faux est pire qu'absent.
public enum HealthIssueResolver {

    public static func smapiIssues(_ diagnostics: SmapiDiagnostics?) -> [HealthIssue] {
        guard let d = diagnostics else { return [] }
        var issues: [HealthIssue] = []

        for issue in d.failed {
            issues.append(HealthIssue(id: "smapi-failed-\(issue.name)",
                                      severity: .critical, source: .smapi,
                                      title: issue.name, detail: issue.reason,
                                      action: .openTab("Logs")))
        }
        for issue in d.skipped {
            issues.append(HealthIssue(id: "smapi-skipped-\(issue.name)",
                                      severity: .critical, source: .smapi,
                                      title: issue.name, detail: issue.reason,
                                      action: .openTab("Logs")))
        }
        // Ce qui reste ici est **dur** : le parseur range les dépendances
        // optionnelles en `BenignNotice.optionalModMissing`.
        for dep in d.missingDeps {
            issues.append(HealthIssue(id: "smapi-dep-\(dep.mod)-\(dep.missing)",
                                      severity: .critical, source: .smapi,
                                      title: dep.mod, detail: dep.missing,
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
}
