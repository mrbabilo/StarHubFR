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
        let staying = all.filter { !leaving.contains($0.folderName) }
        // Un `UniqueID` qu'une autre copie **active** fournit encore n'est pas
        // perdu (58 id partagés au parc) : ses dépendants ne perdent rien.
        let stillProvided = Set(staying.flatMap { $0.isGroup ? ($0.children ?? []) : [$0] }
            .filter(\.isEnabled).map { $0.uniqueId.lowercased() })
        let ids = Set(trashable.flatMap { [$0] + ($0.children ?? []) }
            .map { $0.uniqueId.lowercased() }.filter { !$0.isEmpty && !stillProvided.contains($0) })
        var dependents = Set<String>()
        for head in staying {
            for item in head.isGroup ? (head.children ?? []) : [head] where item.isEnabled {
                if item.dependencies.contains(where: { $0.isRequired && ids.contains($0.uniqueId.lowercased()) }) {
                    dependents.insert(item.name)
                }
            }
        }
        return Plan(trashable: trashable, refused: refused, dependents: dependents.sorted())
    }

    /// Faux quand toute la sélection est refusée : le bouton se grise, sans
    /// ouvrir une confirmation de zéro mod.
    public static func hasTrashable(_ selected: [ModItem]) -> Bool {
        selected.contains { !$0.isStarHubProbe && !$0.isSmapiBundled }
    }

    /// « Nom : erreur » pour chaque mod resté en place (spec §3.2), dans
    /// l'ordre du lot.
    public static func failures(_ trashable: [ModItem], failed: [(physical: String, error: Error)]) -> [String] {
        trashable.compactMap { mod in
            failed.first { $0.physical == mod.physicalFolderName }
                .map { "\(mod.name) : \($0.error.localizedDescription)" }
        }
    }
}
