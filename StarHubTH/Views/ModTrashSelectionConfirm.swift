import Foundation

/// I-T21 lot 1 — les lignes de la confirmation : cinq noms puis « et N
/// autres », dix dépendants au plus, puis les refusés.
enum ModTrashSelectionConfirm {
    static func message(_ plan: ModTrashSelection.Plan, _ localization: LocalizationStore) -> String {
        var lines: [String] = []
        let names = plan.trashable.map(\.name)
        var list = names.prefix(5).joined(separator: ", ")
        if names.count > 5 {
            list += " " + String(format: localization.L(L10n.Mods.trashSelectionMore), Int64(names.count - 5))
        }
        lines.append(list)
        if !plan.dependents.isEmpty {
            var deps = plan.dependents.prefix(10).joined(separator: ", ")
            if plan.dependents.count > 10 {
                deps += " " + String(format: localization.L(L10n.Mods.trashSelectionMore),
                                     Int64(plan.dependents.count - 10))
            }
            lines.append(String(format: localization.L(L10n.Mods.trashSelectionDependents), deps))
        }
        if !plan.refused.isEmpty {
            lines.append(String(format: localization.L(L10n.Mods.trashSelectionRefused),
                                plan.refused.map(\.name).joined(separator: ", ")))
        }
        return lines.joined(separator: "\n\n")
    }
}
