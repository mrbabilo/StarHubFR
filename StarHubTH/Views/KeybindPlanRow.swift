import SwiftUI

/// Une ligne du plan de raccourcis : la case d'inclusion, le mod et son
/// réglage avec le motif du déplacement, l'ancienne et la nouvelle
/// combinaison, la famille éditable. `SplitRow` : sous 560 pt, les touches
/// et la famille passent sous le nom au lieu de le tronquer à rien.
///
/// Décocher n'écarte que **ce** déplacement (`PlannedMove.id` porte
/// l'alternative) : il n'est ni sauvegardé ni écrit, le reste du plan ne
/// bouge pas.
struct KeybindPlanRow: View {
    let move: PlannedMove
    @Binding var isIncluded: Bool
    /// Une correction de l'utilisateur existe pour ce mod : « Non classé »
    /// a quelque chose à retirer.
    let hasCorrection: Bool
    let localize: KeybindPlanText.Localize
    let chooseFamily: (KeybindFamily?) -> Void

    var body: some View {
        SplitRow(spacing: AppDesign.Spacing.sm) {
            Toggle(isOn: $isIncluded) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(localize(L10n.KeybindPlan.includeHint))
            VStack(alignment: .leading, spacing: 1) {
                Text(move.modName)
                    .font(AppDesign.Font.body(.medium))
                    .lineLimit(1).truncationMode(.middle)
                Text(move.keyPath.joined(separator: ".") + " · " + KeybindPlanText.why(move.reason, localize))
                    .font(AppDesign.Font.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        } trailing: {
            KeybindKeyChip(text: move.from.display).monospacedDigit()
            Image(systemName: "arrow.right")
                .font(AppDesign.Font.caption).foregroundColor(.secondary)
                .accessibilityHidden(true)
            KeybindKeyChip(text: move.to.display).monospacedDigit()
            KeybindPlanFamilyMenu(current: move.family, hasCorrection: hasCorrection,
                                  localize: localize, choose: chooseFamily)
        }
        // Exclu : encore lisible (on peut le recocher), mais en retrait.
        .opacity(isIncluded ? 1 : 0.55)
    }
}

/// Un réglage que le plan laisse en place, avec sa raison en clair. Un mod
/// non classé garde le menu de famille : c'est d'ici que l'utilisateur le
/// classe (spec §1, « famille éditable dans la proposition »).
struct KeybindPlanUnmovableRow: View {
    let setting: UnmovableSetting
    let hasCorrection: Bool
    let localize: KeybindPlanText.Localize
    let chooseFamily: (KeybindFamily?) -> Void

    var body: some View {
        SplitRow(spacing: AppDesign.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(setting.modName + " · " + setting.keyPath.joined(separator: "."))
                    .font(AppDesign.Font.caption(.medium))
                    .lineLimit(1).truncationMode(.middle)
                Text(KeybindPlanText.unmovable(setting.reason, localize))
                    .font(AppDesign.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            if setting.reason == .noFamily {
                KeybindPlanFamilyMenu(current: nil, hasCorrection: hasCorrection,
                                      localize: localize, choose: chooseFamily)
            }
        }
    }
}

extension UnmovableSetting {
    /// Identité de ligne : deux alternatives d'un même réglage peuvent être
    /// refusées pour deux raisons différentes (une touche tenue, l'autre
    /// famille pleine) — `id` seul se répéterait dans le `ForEach`.
    var rowID: String { id + "#" + String(describing: reason) }
}

/// Le menu de famille d'un mod. La famille vaut pour **tout** le mod
/// (`KeybindFamilyStore` est indexé par dossier) : la changer recalcule
/// chacune de ses lignes.
///
/// « Non classé » retire la correction mémorisée — le magasin ne sait pas
/// forcer « aucune famille » : la famille devinée revient. Sans correction,
/// il n'y a rien à retirer : grisé.
struct KeybindPlanFamilyMenu: View {
    let current: KeybindFamily?
    let hasCorrection: Bool
    let localize: KeybindPlanText.Localize
    let choose: (KeybindFamily?) -> Void

    var body: some View {
        Menu {
            ForEach(KeybindFamily.allCases, id: \.self) { family in
                Button { choose(family) } label: { entry(family) }
            }
            Divider()
            Button { choose(nil) } label: { entry(nil) }
                .disabled(!hasCorrection)
        } label: {
            Text(KeybindPlanText.family(current, localize))
                .font(AppDesign.Font.caption)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(localize(L10n.KeybindPlan.familyHint))
    }

    @ViewBuilder private func entry(_ family: KeybindFamily?) -> some View {
        if family == current {
            Label(KeybindPlanText.family(family, localize), systemImage: "checkmark")
        } else {
            Text(KeybindPlanText.family(family, localize))
        }
    }
}
