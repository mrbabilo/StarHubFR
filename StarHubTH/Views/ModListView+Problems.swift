import SwiftUI

extension ModListView {
    /// Les natures d'un mod du cadrage — l'anomalie de sa ligne plus l'état
    /// Nexus (audit UX 2026-10-02, 2ᵉ passe). `ModListScoping` et la puce
    /// lisent la même définition.
    func problemKinds(of mod: ModItem) -> Set<ModProblemKind> {
        ModProblemKinds.of(anomaly: vm.anomaly(for: mod),
                           hasNexusState: vm.nexusPageState(for: mod) != nil)
    }

    /// Les puces et leurs comptes, une passe sur la liste cadrée — les
    /// comptes restent ceux du cadrage même quand une puce filtre.
    func problemKindCounts(in scoped: [ModItem]) -> [(kind: ModProblemKind, count: Int)] {
        let counts = Dictionary(grouping: scoped.flatMap { Array(problemKinds(of: $0)) }, by: { $0 })
            .mapValues(\.count)
        return ModProblemKind.allCases.map { ($0, counts[$0] ?? 0) }.filter { $0.1 > 0 }
    }
}
