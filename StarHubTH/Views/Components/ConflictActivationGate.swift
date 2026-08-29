import SwiftUI

/// L'avertissement avant d'**activer** un mod en conflit avec un mod déjà
/// actif — déclaré par l'utilisateur ou observé dans le journal SMAPI d'une
/// partie précédente. Voir `StarHubTHViewModel.conflictWarning(for:)`.
///
/// **Distinct de `CompatibilityWarning`/`compatibilityGate`** (décision du
/// contrôleur, tâche 9) : celui-là interroge `vm.activationWarning`, un
/// tuple `(component, verdict: ModCompatibility)` taillé pour le verdict de
/// smapi.io et déjà consommé par un dialogue en production — l'étendre
/// aurait fait rippler cet écran pour aucun gain. Ce gate-ci interroge une
/// source différente (`ModConflictVerdicts`) et rend directement le mod
/// actif fautif, pas un couple mod/verdict. Les deux gates cohabitent sur
/// chaque site d'activation (`ModListView`, `ModDetailView`,
/// `DependencyTreeView`) et peuvent apparaître l'un après l'autre pour le
/// même geste — un mod peut être à la fois signalé cassé par smapi.io et en
/// conflit déclaré avec un mod actif.
struct ConflictActivation: Equatable {
    /// Le mod qu'on est en train d'activer.
    let mod: ModItem
    /// Le mod déjà actif avec lequel il forme un conflit.
    let other: ModItem
}

extension View {
    /// Même patron que `compatibilityGate` : `pending` porte l'état de la
    /// confirmation en attente, `nil` la ferme. L'alerte n'active rien
    /// d'elle-même — annuler laisse le mod dans l'état où il était.
    func conflictActivationGate(vm: StarHubTHViewModel,
                                pending: Binding<ConflictActivation?>,
                                onConfirm: @escaping (ModItem) -> Void) -> some View {
        alert(vm.L(L10n.Conflicts.title),
              isPresented: Binding(get: { pending.wrappedValue != nil },
                                   set: { if !$0 { pending.wrappedValue = nil } })) {
            if let state = pending.wrappedValue {
                Button(vm.L(L10n.Mods.compatEnableConfirm)) {
                    let target = state.mod
                    pending.wrappedValue = nil
                    onConfirm(target)
                }
                Button(vm.L(L10n.ModInstall.cancel), role: .cancel) { pending.wrappedValue = nil }
            }
        } message: {
            if let state = pending.wrappedValue {
                Text(String(format: vm.L(L10n.Conflicts.activationWarning), state.mod.name, state.other.name))
            }
        }
    }
}
