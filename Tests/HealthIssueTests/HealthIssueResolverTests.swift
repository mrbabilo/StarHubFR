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
    @Test func benignNoticesAreInformation() {
        let issues = HealthIssueResolver.smapiIssues(Self.diagnostics())
        #expect(issues.contains { $0.severity == .info })
    }

    @Test func noDiagnosticsYieldsNoIssues() {
        #expect(HealthIssueResolver.smapiIssues(nil).isEmpty)
    }

    /// Deux relectures du même journal doivent donner les mêmes identités,
    /// sans quoi les lignes sautent d'un rafraîchissement à l'autre.
    ///
    /// Renforcé par rapport au brief : les modèles source (`Issue`,
    /// `MissingDep`, `BenignNotice`) portent tous un `id = UUID()` régénéré à
    /// chaque construction, donc deux `diagnostics()` fraîchement construits
    /// portent déjà des UUID différents pour un contenu identique. Si le
    /// résolveur utilisait ces UUID (directement ou dérivés, ex.
    /// `id.uuidString`), `first` et `second` ci-dessous divergeraient
    /// forcément — le test échouerait vraiment, il ne passe pas par accident.
    @Test func identitiesAreStableAcrossTwoResolutions() {
        let first = HealthIssueResolver.smapiIssues(Self.diagnostics()).map(\.id)
        let second = HealthIssueResolver.smapiIssues(Self.diagnostics()).map(\.id)
        #expect(first == second)
        #expect(Set(first).count == first.count)  // pas de doublon d'identité
    }
}
