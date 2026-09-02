import Testing
@testable import StarHubTHCore

@Suite("HealthIssue")
struct HealthIssueTests {
    /// Le tri de l'écran dépend entièrement de cet ordre : critique en haut.
    @Test func severitiesOrderCriticalFirst() {
        #expect(HealthIssue.Severity.critical > .warning)
        #expect(HealthIssue.Severity.warning > .info)
    }

    /// L'identité doit venir du contenu : les modèles SMAPI portent un
    /// `id = UUID()` régénéré à chaque lecture du journal, inutilisable ici.
    @Test func identityComesFromContent() {
        let a = HealthIssue(id: "smapi-failed-SVE", severity: .critical,
                            source: .smapi, title: "SVE", detail: "raison",
                            action: .openTab("Logs"))
        let b = HealthIssue(id: "smapi-failed-SVE", severity: .critical,
                            source: .smapi, title: "SVE", detail: "raison",
                            action: .openTab("Logs"))
        #expect(a == b)
        #expect(a.id == b.id)
    }

    private static func issue(_ severity: HealthIssue.Severity, _ title: String) -> HealthIssue {
        HealthIssue(id: "\(severity)-\(title)", severity: severity, source: .smapi,
                    title: title, detail: nil, action: nil)
    }

    /// Revue globale de branche, bloquant 1 : une notice `.info` reste
    /// affichée dans la liste (voir `SystemAlertsView`) mais n'est PAS un
    /// « problème actionnable » — `SmapiLogDiagnostics.problemCount` l'exclut
    /// déjà pour cette même raison. Sans ce compte séparé, une pastille sonne
    /// sur un parc sain (mesuré : 7 notices bénignes, 0 échec, 0 conflit).
    @Test func actionableCountExcludesInfoButKeepsCriticalAndWarning() {
        let issues = [Self.issue(.info, "bénin 1"), Self.issue(.info, "bénin 2"),
                      Self.issue(.warning, "avertissement"), Self.issue(.critical, "critique")]
        #expect(issues.actionableCount == 2)
    }

    @Test func actionableCountIsZeroWhenOnlyInfo() {
        let issues = [Self.issue(.info, "a"), Self.issue(.info, "b")]
        #expect(issues.actionableCount == 0)
    }

    @Test func actionableCountOfEmptyListIsZero() {
        let issues: [HealthIssue] = []
        #expect(issues.actionableCount == 0)
    }
}
