import SwiftUI

/// Les écarts clé à clé de deux `config.json` (`ConfigJSONDiff`), en trois
/// familles. Sorti de `ProfileConfigCompareView` (2026-10-16) pour servir
/// aussi la comparaison d'une sauvegarde avec le fichier actuel.
struct ConfigDiffList: View {
    @ObservedObject var localization: LocalizationStore
    let diffs: [ConfigKeyDiff]
    let nameA: String
    let nameB: String

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                section(String(format: localization.L(L10n.Mods.profileConfigDiffOnlyA), nameA),
                        items: diffs.filter { $0.kind == .onlyInA })
                section(localization.L(L10n.Mods.profileConfigDiffDiffers), items: diffs.filter { $0.kind == .valueDiffers })
                section(String(format: localization.L(L10n.Mods.profileConfigDiffOnlyB), nameB),
                        items: diffs.filter { $0.kind == .onlyInB })
            }
        }
    }

    /// Une famille : en-tête + lignes. La sous-liste vient en paramètre —
    /// trier les diffs par libellé localisé serait trier des données par
    /// habillage. Une famille vide ne montre pas son en-tête : un titre
    /// seul sous lequel rien ne vient se lit comme un écran cassé.
    private func section(_ title: String, items: [ConfigKeyDiff]) -> some View {
        Group {
            if !items.isEmpty {
                HStack {
                    Text(title)
                        .font(AppDesign.Font.footnote(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 6)
                ForEach(items) { diff in
                    if diff.kind == .valueDiffers {
                        comparisonRow(diff)
                    } else {
                        row(diff)
                    }
                    Divider().padding(.leading, 20)
                }
            }
        }
    }

    /// Une valeur d'un seul côté : le chemin en monospace, la valeur
    /// dessous, sélectionnable — copier à la main reste possible même en
    /// lecture seule.
    private func row(_ diff: ConfigKeyDiff) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(diff.path)
                .font(AppDesign.Font.monoIconXS)
                .foregroundColor(.secondary)
            Text((diff.valueA ?? diff.valueB) ?? "")
                .font(AppDesign.Font.caption)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    /// Les deux valeurs côte à côte, étiquetées par profil — c'est ce qui
    /// permet de juger laquelle vient d'où.
    private func comparisonRow(_ diff: ConfigKeyDiff) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(diff.path)
                .font(AppDesign.Font.monoIconXS)
                .foregroundColor(.secondary)
            HStack(alignment: .top, spacing: 12) {
                labelledValue(nameA, diff.valueA ?? "", color: .primary)
                labelledValue(nameB, diff.valueB ?? "", color: .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}
