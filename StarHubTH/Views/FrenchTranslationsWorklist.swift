import SwiftUI

/// R3 (audit UX du 2026-10-16) — le segment « À finir » de la page
/// Traductions FR : les traductions commencées et pas finies, ou à revoir,
/// du plus gros reste au plus petit (`TranslationWorklist`). Avant, la seule
/// liste triée par reste vivait dans le diagnostic d'un profil.
struct FrenchTranslationsWorklist: View {
    @ObservedObject var localization: LocalizationStore
    let items: [TranslationWorkItem]
    /// Mods traduisibles sans aucun français : comptés, pas listés.
    let untranslated: Int
    /// Mods que la passe de couverture n'a pas encore lus.
    let unmeasured: Int
    let open: (String) -> Void
    let showNexus: () -> Void
    /// Préférence de lecture seulement : perdue, la liste reprend l'ordre par clés.
    @AppStorage("frtrWorklistOrder") private var order: TranslationWorklist.Order = .remainingKeys

    var body: some View {
        LazyVStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            if unmeasured > 0 {
                Label(String(format: localization.L(L10n.FrTranslations.worklistMeasuring), unmeasured),
                      systemImage: "hourglass")
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
            if untranslated > 0 {
                HStack(spacing: AppDesign.Spacing.sm) {
                    Text(String(format: localization.L(L10n.FrTranslations.worklistUntranslated), untranslated))
                        .foregroundColor(.secondary)
                    Button(localization.L(L10n.FrTranslations.worklistSearchNexus), action: showNexus)
                        .buttonStyle(.link).focusRing(cornerRadius: 4).pointingHandCursor()
                }
                .font(AppDesign.Font.footnote)
            }
            if items.isEmpty, unmeasured == 0 {
                Text(localization.L(L10n.FrTranslations.worklistEmpty))
                    .font(AppDesign.Font.body).foregroundColor(.secondary)
                    .padding(.top, AppDesign.Spacing.md)
            }
            if !items.isEmpty {
                Picker(localization.L(L10n.FrTranslations.sortLabel), selection: $order) {
                    Text(localization.L(L10n.FrTranslations.sortKeys)).tag(TranslationWorklist.Order.remainingKeys)
                    Text(localization.L(L10n.FrTranslations.sortPercent)).tag(TranslationWorklist.Order.remainingPercent)
                    Text(localization.L(L10n.FrTranslations.sortName)).tag(TranslationWorklist.Order.name)
                }
                .pickerStyle(.menu).fixedSize().font(AppDesign.Font.footnote)
            }
            ForEach(items.sorted(by: order.precedes)) { row($0) }
        }
        .padding(AppDesign.Spacing.lg)
    }

    private func row(_ item: TranslationWorkItem) -> some View {
        HStack(spacing: AppDesign.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppDesign.Spacing.sm) {
                    Text(item.name).font(AppDesign.Font.body(.medium)).lineLimit(1)
                    if !item.isEnabled { pill(localization.L(L10n.FrTranslations.paused), .secondary) }
                    if item.isStale { pill(localization.L(L10n.Mods.frTranslationStale), AppDesign.Color.warning) }
                }
                if let coverage = item.coverage {
                    Text(String(format: localization.L(L10n.Profiles.translationRowCounts),
                                Int64(coverage.translated), Int64(coverage.total), Int64(item.missingCount)))
                        .font(AppDesign.Font.iconXS).foregroundColor(.secondary)
                }
            }
            Spacer()
            if let coverage = item.coverage {
                // Chasse fixe, comme la pastille de la liste des mods.
                Text("\(coverage.displayPercent) %")
                    .font(.system(size: AppDesign.Font.scaled(11), weight: .medium, design: .monospaced))
                    .foregroundColor(AppDesign.Color.accent)
            }
            Button(localization.L(L10n.Profiles.translationOpen)) { open(item.folderName) }
                .buttonStyle(.bordered).focusRing(cornerRadius: 5).controlSize(.small).pointingHandCursor()
        }
        .cardSurface(padding: AppDesign.Spacing.sm)
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(AppDesign.Font.iconXS).foregroundColor(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.15)).cornerRadius(4)
    }
}
