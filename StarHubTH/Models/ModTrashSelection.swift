import Foundation

/// I-T21 lot 1 — ce que « Mettre à la corbeille » fait d'une sélection
/// multiple. Les refusés (sonde, mods de SMAPI) sont nommés, jamais supprimés ;
/// les dépendants **actifs restants** (dépendance obligatoire visant un
/// `UniqueID` sélectionné, composants de pack compris, casse ignorée) sont
/// nommés dans la confirmation. Règle de `ProbePerformanceActions.pauseBlockers`
/// étendue à un lot.
public enum ModTrashSelection {
    public enum Reason: Equatable, Sendable { case probe, smapiBundled }

    public struct Refused: Equatable, Sendable {
        public let name: String
        public let reason: Reason
        public init(name: String, reason: Reason) {
            self.name = name
            self.reason = reason
        }
    }

    public struct Plan: Equatable, Sendable {
        public let trashable: [ModItem]
        public let refused: [Refused]
        public let dependents: [String]
    }

    public static func plan(selected: [ModItem], all: [ModItem]) -> Plan {
        var trashable: [ModItem] = []
        var refused: [Refused] = []
        for mod in selected {
            if mod.isStarHubProbe { refused.append(.init(name: mod.name, reason: .probe)) }
            else if mod.isSmapiBundled { refused.append(.init(name: mod.name, reason: .smapiBundled)) }
            else { trashable.append(mod) }
        }
        let leaving = Set(trashable.map(\.folderName))
        let ids = Set(trashable.flatMap { [$0] + ($0.children ?? []) }
            .map { $0.uniqueId.lowercased() }.filter { !$0.isEmpty })
        var dependents = Set<String>()
        for head in all where !leaving.contains(head.folderName) {
            for item in head.isGroup ? (head.children ?? []) : [head] where item.isEnabled {
                if item.dependencies.contains(where: { $0.isRequired && ids.contains($0.uniqueId.lowercased()) }) {
                    dependents.insert(item.name)
                }
            }
        }
        return Plan(trashable: trashable, refused: refused, dependents: dependents.sorted())
    }
}
