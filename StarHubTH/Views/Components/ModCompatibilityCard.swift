import SwiftUI

/// La compatibilité, en tête de l'onglet Aperçu : le verdict de smapi.io et ce
/// que l'auteur en dit dans sa description (`CompatibilityNote`), réunis au
/// lieu d'être, l'un dans Santé, l'autre sous toute la description.
///
/// Inconnu de smapi.io — deux tiers du parc — se dit en clair, sans coche.
/// Un verdict qui demande une décision renvoie à Santé, où vivent ses liens.
struct ModCompatibilityCard: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let live: ModItem
    /// La note de l'auteur, déjà extraite des blocs de la description.
    let note: CompatibilityNote?
    let onShowHealth: () -> Void

    private enum Verdict { case ok, attention(ModCompatibility.Status), unknown }

    private var verdict: Verdict {
        if let warning = viewModel.compatibilityWarning(for: live) { return .attention(warning.verdict.status) }
        return live.components.contains { viewModel.modCompatibility[$0.uniqueId] != nil } ? .ok : .unknown
    }

    var body: some View {
        let verdict = verdict
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            HStack(alignment: .center, spacing: AppDesign.Spacing.md) {
                IconTile(icon: icon(verdict), tint: tint(verdict), size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.L(L10n.ModCompat.cardTitle))
                        .font(AppDesign.Font.headline(.semibold))
                    Text(line(verdict))
                        .font(AppDesign.Font.footnote)
                        .foregroundStyle(lineColor(verdict))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AppDesign.Spacing.sm)
                if case .attention = verdict {
                    Button(localization.L(L10n.ModCompat.seeHealth), action: onShowHealth)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .pointingHandCursor()
                }
            }
            // **Ce que l'auteur dit de la compatibilité** (30 % des fiches,
            // médiane 359 caractères : pas de repli).
            if let note {
                Divider()
                Text(localization.L(L10n.Mods.compatibilityNote))
                    .font(AppDesign.Font.caption(.semibold))
                    .foregroundStyle(.secondary)
                DescriptionBlocksView(blocks: note.blocks, vm: viewModel, localization: localization)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.lg, style: .continuous)
            .stroke(tint(verdict).opacity(0.5), lineWidth: 1))
    }

    private func line(_ verdict: Verdict) -> String {
        switch verdict {
        case .ok:                 return localization.L(L10n.ModCompat.smapiOk)
        case .attention(let s):   return "\(CompatibilityWarning.label(s, localization)) — \(localization.L(L10n.Mods.compatSource))"
        case .unknown:            return localization.L(note == nil ? L10n.ModCompat.smapiUnknownNoNote
                                                                    : L10n.ModCompat.smapiUnknown)
        }
    }

    private func icon(_ verdict: Verdict) -> String {
        switch verdict {
        case .ok:        return "checkmark.seal.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .unknown:   return "questionmark"
        }
    }

    private func tint(_ verdict: Verdict) -> Color {
        switch verdict {
        case .ok:                 return AppDesign.Color.success
        case .attention(let s):   return CompatibilityWarning.tint(s)
        case .unknown:            return .gray
        }
    }

    private func lineColor(_ verdict: Verdict) -> Color {
        if case .attention(let s) = verdict { return CompatibilityWarning.tint(s) }
        return .secondary
    }
}
