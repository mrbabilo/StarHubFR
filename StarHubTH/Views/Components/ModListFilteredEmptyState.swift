import SwiftUI

/// Explains why the current mod-list framing is empty and offers one escape.
struct ModListFilteredEmptyState: View {
    let cause: ModListEmptyCause?
    let filters: ModListFilters
    @ObservedObject var localization: LocalizationStore
    let clear: () -> Void

    var body: some View {
        VStack(spacing: AppDesign.Spacing.lg) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(AppDesign.Font.emptyStateGlyph)
                .foregroundColor(AppDesign.Color.dimmedSecondary(AppDesign.Opacity.disabled))
            Text(message)
                .multilineTextAlignment(.center)
                .font(AppDesign.Font.rowTitle)
                .foregroundColor(.secondary)
            Button(action: clear) {
                Label(localization.L(L10n.Mods.clearFilters), systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered).focusRing(cornerRadius: 5)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var message: String {
        guard let cause else { return localization.L(L10n.Mods.noActiveFilterResults) }
        switch cause {
        case .search(let term):
            return String(format: localization.L(L10n.Mods.noModFound), term)
        case .combined:
            return localization.L(L10n.Mods.noActiveFilterResults)
        default:
            return String(format: localization.L(L10n.Mods.noFilterResults), filterLabel(for: cause))
        }
    }

    private func filterLabel(for cause: ModListEmptyCause) -> String {
        switch cause {
        case .scope(let scope):
            switch scope {
            case .all: return localization.L(L10n.Mods.filterAll)
            case .enabled: return localization.L(L10n.Mods.enabled)
            case .disabled: return localization.L(L10n.Mods.disabled)
            case .issues: return localization.L(L10n.Mods.filterIssues)
            case .updates: return localization.L(L10n.Mods.filterUpdates)
            }
        case .category:
            switch filters.category {
            case .all: return localization.L(L10n.Mods.categoryFilter)
            case .category(let category): return category.localizedName(localization.L)
            case .inferredTag(let tag): return localization.L(L10n.ModTag.key(for: tag))
            case .uncategorized: return localization.L(L10n.Mods.categoryFilterUncategorized)
            }
        case .config: return localization.L(L10n.Mods.configFilterLabel)
        case .favorites: return localization.L(L10n.Mods.filterFavorites)
        case .blacklisted: return localization.L(L10n.Mods.filterBlacklisted)
        case .translation:
            switch filters.frenchTranslation {
            case .off: return localization.L(L10n.Mods.frTranslationFilterLabel)
            case .available: return localization.L(L10n.Mods.frTranslationAvailable)
            case .partial: return localization.L(L10n.Mods.frTranslationPartial)
            case .missing: return localization.L(L10n.Mods.frTranslationMissing)
            case .stale: return localization.L(L10n.Mods.frTranslationStale)
            }
        case .impact:
            switch filters.impactScope {
            case .off: return localization.L(L10n.Mods.impactFilterLabel)
            case .high: return localization.L(L10n.Mods.impactFilterHigh)
            case .medium: return localization.L(L10n.Mods.impactFilterMedium)
            }
        case .search(let term): return term
        case .combined: return localization.L(L10n.Mods.filterAll)
        }
    }
}
