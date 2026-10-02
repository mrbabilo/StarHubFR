import Testing
@testable import StarHubTHCore

@Suite struct ModHealthChecklistTests {
    private typealias C = ModHealthChecklist

    private func status(_ check: C.Check, _ inputs: C.Inputs) -> C.Status? {
        C.entries(inputs).first { $0.check == check }?.status
    }

    /// Un mod sain mais inconnu de smapi.io, sans rapport de raccourcis ni page
    /// Nexus : rien à regarder, et rien d'affirmé non plus.
    @Test func unmeasuredIsNeitherHealthyNorCounted() {
        let inputs = C.Inputs()
        #expect(status(.compatibility, inputs) == .unmeasured)
        #expect(status(.keybinds, inputs) == .unmeasured)
        #expect(status(.nexusPage, inputs) == .notApplicable)
        let verdict = C.verdict(C.entries(inputs))
        #expect(verdict.status == .ok)
        #expect(verdict.attention == 0)
    }

    @Test func measuredAndCleanReadsOk() {
        var inputs = C.Inputs()
        inputs.knownToCompatibilityList = true
        inputs.keybindConflicts = 0
        inputs.hasNexusPage = true
        #expect(C.entries(inputs).allSatisfy { $0.status == .ok })
    }

    /// Le journal suit le compte de l'anomalie (version installée), pas
    /// l'historique de toutes les versions.
    @Test func logCountsInstalledVersionFromTheAnomaly() {
        var inputs = C.Inputs()
        inputs.anomaly = ModAnomaly(severity: .error, errorCount: 2, warningCount: 1,
                                    hasDependencyIssue: false, isUnloadable: false)
        let log = C.entries(inputs).first { $0.check == .log }
        #expect(log?.status == .error)
        #expect(log?.count == 3)
        #expect(status(.loading, inputs) == .ok)
    }

    @Test func loadingGradesDependencyDuplicateAndDormantCopies() {
        var inputs = C.Inputs()
        inputs.anomaly = ModAnomaly(severity: .error, errorCount: 0, warningCount: 0,
                                    hasDependencyIssue: true, isUnloadable: false)
        #expect(status(.loading, inputs) == .error)
        inputs.anomaly = ModAnomaly(severity: .warning, errorCount: 0, warningCount: 0,
                                    hasDependencyIssue: false, isUnloadable: false,
                                    duplicate: .active(folders: ["A", "B"]))
        #expect(status(.loading, inputs) == .warning)
        inputs.anomaly = ModAnomaly(severity: .warning, errorCount: 0, warningCount: 0,
                                    hasDependencyIssue: false, isUnloadable: false,
                                    duplicate: .dormant(folders: ["A", ".B"]))
        #expect(status(.loading, inputs) == .info)
    }

    @Test func compatibilitySeverityFollowsTheBanner() {
        var inputs = C.Inputs()
        inputs.compatibilityWarning = .broken
        #expect(status(.compatibility, inputs) == .error)
        inputs.compatibilityWarning = .unofficial
        #expect(status(.compatibility, inputs) == .warning)
    }

    /// Le verdict prend le pire, et compte toutes les lignes à regarder —
    /// information comprise, puisqu'elle mène aussi à sa section.
    @Test func verdictIsTheWorstAndCountsEveryAttentionRow() {
        var inputs = C.Inputs()
        inputs.performanceOverlaps = 1
        inputs.declaredConflicts = 2
        inputs.nexusPage = .removed
        let verdict = C.verdict(C.entries(inputs))
        #expect(verdict.status == .error)
        #expect(verdict.attention == 3)
    }

    @Test func keybindConflictsFromAReportAreAWarning() {
        var inputs = C.Inputs()
        inputs.keybindConflicts = 2
        let row = C.entries(inputs).first { $0.check == .keybinds }
        #expect(row?.status == .warning)
        #expect(row?.count == 2)
    }
}
