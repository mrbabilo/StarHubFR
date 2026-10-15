import SwiftUI

extension KeybindReportSection {
    /// Plan de raccourcis (spec 2026-10-15 §4) — ouvre la feuille dès qu'un
    /// rapport est là : c'est sur lui que le plan se calcule. Pendant un scan,
    /// le rapport publié est l'ancien : grisé jusqu'au nouveau.
    var planButton: some View {
        Button(action: { showsPlan = true }) {
            Label(localization.L(L10n.KeybindPlan.propose), systemImage: "wand.and.stars")
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .pointingHandCursor()
        .disabled(service.report == nil || service.isScanning || noGameDir)
        .help(localization.L(L10n.KeybindPlan.proposeHint))
    }

    /// Posée à la racine de `body`, jamais sur une branche conditionnelle :
    /// le rescan qui suit l'application bascule `isScanning`, qui démonte le
    /// verdict et les sections — une feuille attachée là se fermerait seule.
    var planSheet: some View {
        KeybindPlanSheet(viewModel: vm, localization: localization)
    }

    /// L'en-tête d'un groupe : glyphe de gravité, couleur du sens, titre.
    func groupLabel(_ format: String, _ count: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: icon).foregroundColor(tint)
            Text(String(format: localization.L(format), count))
                .font(AppDesign.Font.body(.semibold))
        }
    }
}
