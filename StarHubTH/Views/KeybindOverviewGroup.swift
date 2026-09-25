import SwiftUI

/// C4-T13 — « tous les raccourcis » : chaque réglage de raccourci des mods
/// actifs, filtrable (tous / liés / en conflit / non assignés) et
/// cherchable. Les groupes de `KeybindReportSection` ne montrent que les
/// problèmes ; ici, l'inventaire — ce que Keybind Radar fait en jeu.
///
/// Le groupe compte des **réglages**, pas des combinaisons : « Conflits entre
/// mods (19) » plus haut compte des touches, « En conflit » ici compte les
/// réglages qui les portent (66 sur le parc réel). Le mot « réglages » est
/// dans les deux libellés de ce groupe pour que les deux chiffres ne se
/// lisent pas comme une contradiction.
///
/// Les compteurs par filtre ne sont pas dans le contrôle segmenté : quatre
/// segments français avec leur nombre (« Non assignés (68) ») tronquent en
/// fenêtre étroite. Le nombre de lignes affichées est posé dessous.
struct KeybindOverviewGroup: View {
    @ObservedObject var localization: LocalizationStore
    let bindings: [KeybindScanner.SettingBinding]
    @Binding var isExpanded: Bool
    /// Le geste de l'engrenage, composé par `KeybindReportSection`.
    let openConfig: (String) -> Void

    @State private var filter: KeybindScanner.OverviewFilter = .all
    @State private var query = ""

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            let shown = KeybindScanner.overview(bindings, filter: filter, query: query)
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                controls
                Text(String(format: localization.L(L10n.Keybinds.filterCount), shown.count))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                if shown.isEmpty {
                    Text(localization.L(L10n.Keybinds.noMatch))
                        .font(AppDesign.Font.caption).foregroundColor(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(shown) { row($0) }
                    }
                }
            }
            .padding(.top, AppDesign.Spacing.xs)
        } label: {
            Text(String(format: localization.L(L10n.Keybinds.allHeader), bindings.count))
                .font(AppDesign.Font.body(.semibold))
        }
    }

    /// Côte à côte si la carte le permet, empilés sinon : le segmenté garde
    /// sa largeur idéale (`fixedSize`, jamais tronqué) et le volet de détail
    /// descend à 560 pt — la ligne entière n'y tient pas toujours.
    /// `SplitRow` (un `Layout`) et non un `ViewThatFits` : le ✕ qui apparaît au
    /// premier caractère élargit la rangée, et une bascule entre deux
    /// branches recréait le champ en pleine frappe.
    private var controls: some View {
        SplitRow(spacing: AppDesign.Spacing.sm) { filterPicker } trailing: { searchField }
    }

    private var filterPicker: some View {
        Picker("", selection: $filter) {
            Text(localization.L(L10n.Keybinds.filterAll)).tag(KeybindScanner.OverviewFilter.all)
            Text(localization.L(L10n.Keybinds.filterBound)).tag(KeybindScanner.OverviewFilter.bound)
            Text(localization.L(L10n.Keybinds.filterConflicts)).tag(KeybindScanner.OverviewFilter.conflicts)
            Text(localization.L(L10n.Keybinds.filterUnassigned)).tag(KeybindScanner.OverviewFilter.unassigned)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(AppDesign.Font.caption)
            TextField(localization.L(L10n.Keybinds.searchPlaceholder), text: $query)
                .textFieldStyle(.plain)
                .font(AppDesign.Font.caption)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain).iconHelp(localization.L(L10n.Discovery.clearSearch))
            }
        }
        .padding(.horizontal, AppDesignCore.Spacing.sm)
        .padding(.vertical, AppDesignCore.Spacing.xs)
        .background(AppDesign.Color.textBg)
        .cornerRadius(AppDesignCore.Radius.sm)
        .frame(minWidth: 160)
    }

    /// Touches, puis mod et réglage. La colonne des touches a une largeur
    /// fixe pour que les lignes s'alignent ; « LeftControl + LeftShift + F8 »
    /// y tronque au milieu plutôt que de décaler la suite.
    private func row(_ binding: KeybindScanner.SettingBinding) -> some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Group {
                if binding.hasConflict {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppDesign.Font.iconXS)
                        .foregroundColor(.orange)
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                        .help(localization.L(L10n.Keybinds.conflictHelp))
                        .accessibilityLabel(localization.L(L10n.Keybinds.conflictHelp))
                } else {
                    Color.clear.frame(width: 18, height: 18)
                }
            }
            keys(binding)
                .frame(width: 170, alignment: .leading)
            Text("\(binding.modName) · \(binding.keyPath.joined(separator: "."))")
                .font(AppDesign.Font.caption).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            KeybindConfigButton(localization: localization) { openConfig(binding.modID) }
        }
    }

    @ViewBuilder private func keys(_ binding: KeybindScanner.SettingBinding) -> some View {
        if binding.isUnassigned {
            Text(localization.L(L10n.Keybinds.unassignedValue))
                .font(AppDesign.Font.caption).italic().foregroundColor(.secondary)
        } else {
            Text(binding.combos.map(\.display).joined(separator: ", "))
                .font(AppDesign.Font.caption(.medium))
                .lineLimit(1).truncationMode(.middle)
        }
    }
}
