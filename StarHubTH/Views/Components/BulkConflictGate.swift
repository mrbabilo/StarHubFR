import SwiftUI

/// A5-T8 — l'alerte des gestes groupés qui rendraient actives des paires en
/// conflit, branchée au niveau racine (`MainView`) comme celle des empreintes :
/// une page d'onglet mourrait au changement de page pendant que le geste
/// resterait suspendu. L'état vit dans `BulkConflictGateStore`.
///
/// Même patron que `conflictActivationGate` : l'alerte n'active rien
/// d'elle-même — confirmer reprend le geste, annuler le clôt sans renommer.
extension View {
    func bulkConflictGate(vm: StarHubTHViewModel) -> some View {
        let store = vm.bulkConflictGate
        let localization = vm.localization
        return alert(
            localization.L(L10n.Conflicts.title),
            isPresented: Binding(get: { store.pending != nil },
                                 // Esc vaut annulation — idempotent après un confirm.
                                 set: { if !$0 { store.cancel() } })
        ) {
            Button(localization.L(L10n.Mods.compatEnableConfirm)) { store.confirm() }
            Button(localization.L(L10n.ModInstall.cancel), role: .cancel) { store.cancel() }
        } message: {
            if let pending = store.pending {
                Text(BulkConflictSummary.text(pending, vm: vm))
            }
        }
    }
}

/// Le texte du message : une tête selon le geste, puis une ligne par paire —
/// trois au plus, une alerte qui déroulerait vingt lignes serait tronquée par
/// l'OS (même borne que `FingerprintSummary`). Une paire prévue par les
/// fichiers Content Patcher (A5-T4) dit quels assets elle se dispute.
enum BulkConflictSummary {
    @MainActor
    static func text(_ pending: BulkConflictGateStore.Pending, vm: StarHubTHViewModel) -> String {
        let localization = vm.localization
        let limit = 3
        let names = Dictionary(vm.mods.flattenedMods.map { ($0.folderName, $0.name) },
                               uniquingKeysWith: { first, _ in first })
        var lines = pending.pairs.prefix(limit).map { pair in
            let line = String(format: localization.L(L10n.Conflicts.bulkPairLine),
                              names[pair.first] ?? pair.first, names[pair.second] ?? pair.second)
            let assets = ContentPatcherLoadTargets.assets(of: pair, in: vm.contentPatcherLoadIndex.pairs)
            guard !assets.isEmpty else { return line }
            return line + "\n" + String(format: localization.L(L10n.Conflicts.bulkAssetsLine),
                                        assets.joined(separator: ", "))
        }
        if pending.pairs.count > limit {
            lines.append(String(format: localization.L(L10n.Conflicts.bulkMore), pending.pairs.count - limit))
        }
        let head = switch pending.subject {
        case .mods(let count): String(format: localization.L(L10n.Conflicts.bulkModsMessage), count)
        case .profile(let name): String(format: localization.L(L10n.Conflicts.bulkProfileMessage), name)
        }
        return head + "\n\n" + lines.joined(separator: "\n")
    }
}
