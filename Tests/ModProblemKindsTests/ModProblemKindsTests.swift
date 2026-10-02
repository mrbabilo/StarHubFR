import Foundation
import Testing
@testable import StarHubTHCore

/// Les natures de problème derrière le cadrage « Problèmes » : une puce
/// filtre, elle ne recatégorise pas — un mod qui cumule deux natures reste
/// une ligne.
@Suite struct ModProblemKindsTests {

    private func anomaly(errorCount: Int = 0, warningCount: Int = 0,
                         dependency: Bool = false, unloadable: Bool = false,
                         duplicate: ModAnomaly.Duplicate? = nil,
                         compatibility: ModCompatibility.Status? = nil) -> ModAnomaly {
        ModAnomaly(severity: errorCount > 0 || dependency || unloadable ? .error : .warning,
                   errorCount: errorCount, warningCount: warningCount,
                   hasDependencyIssue: dependency, isUnloadable: unloadable,
                   duplicate: duplicate, compatibility: compatibility)
    }

    @Test func emptyAnomalyYieldsNoKinds() {
        #expect(ModProblemKinds.of(anomaly: nil, hasNexusState: false).isEmpty)
        #expect(ModProblemKinds.of(anomaly: anomaly(), hasNexusState: false).isEmpty)
    }

    @Test func eachFieldMapsToItsKind() {
        #expect(ModProblemKinds.of(anomaly: anomaly(errorCount: 2), hasNexusState: false) == [.errors])
        #expect(ModProblemKinds.of(anomaly: anomaly(warningCount: 1), hasNexusState: false) == [.warnings])
        #expect(ModProblemKinds.of(anomaly: anomaly(dependency: true), hasNexusState: false) == [.dependencies])
        #expect(ModProblemKinds.of(anomaly: anomaly(unloadable: true), hasNexusState: false) == [.unloadable])
        #expect(ModProblemKinds.of(anomaly: anomaly(duplicate: .dormant(folders: ["A", ".A"])), hasNexusState: false) == [.duplicates])
        #expect(ModProblemKinds.of(anomaly: anomaly(compatibility: .broken), hasNexusState: false) == [.compatibility])
        #expect(ModProblemKinds.of(anomaly: nil, hasNexusState: true) == [.nexus])
    }

    /// Le cas signalé : un mod cumule les natures, il ne doit apparaître
    /// qu'une fois sous chaque puce qui le concerne.
    @Test func cumulativeModCarriesEveryKind() {
        let a = anomaly(errorCount: 3, dependency: true,
                        duplicate: .active(folders: ["X", "Y"]),
                        compatibility: .abandoned)
        #expect(ModProblemKinds.of(anomaly: a, hasNexusState: true)
            == [.errors, .dependencies, .duplicates, .compatibility, .nexus])
    }

    /// Toutes les natures portent une clé de libellé.
    @Test func everyKindHasALabelKey() {
        for kind in ModProblemKind.allCases {
            #expect(!kind.l10nKey.isEmpty)
        }
        #expect(ModProblemKind.allCases.count == 7)
    }
}
