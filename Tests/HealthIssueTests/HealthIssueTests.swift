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
}
