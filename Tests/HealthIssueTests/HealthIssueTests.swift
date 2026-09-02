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
                            action: .openMod(query: "SVE"))
        let b = HealthIssue(id: "smapi-failed-SVE", severity: .critical,
                            source: .smapi, title: "SVE", detail: "raison",
                            action: .openMod(query: "SVE"))
        #expect(a == b)
        #expect(a.id == b.id)
    }

    /// L'ancien `openTab(String)` ne portait qu'un onglet, jamais de quoi
    /// désigner le mod ou la ligne de journal en cause — le manque exact que
    /// H-T6b comble. `Action` doit porter une cible utilisable.
    @Test func actionOpenModCarriesTheResolvableQuery() {
        let action = HealthIssue.Action.openMod(query: "Stardew Valley Expanded")
        #expect(action == .openMod(query: "Stardew Valley Expanded"))
        #expect(action != .openMod(query: "Autre mod"))
    }

    @Test func actionOpenLogsCarriesTheSearchText() {
        let action = HealthIssue.Action.openLogs(searchText: "RivaTuner Statistics Server")
        #expect(action == .openLogs(searchText: "RivaTuner Statistics Server"))
        #expect(action != .openLogs(searchText: "autre chose"))
    }

    @Test func openModAndOpenLogsAreNeverEqualEvenWithTheSameString() {
        #expect(HealthIssue.Action.openMod(query: "X") != .openLogs(searchText: "X"))
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
