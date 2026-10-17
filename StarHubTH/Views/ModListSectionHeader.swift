import SwiftUI

/// I-T21 lot 2 — le bandeau d'une section : chevron (replier), nom, compte,
/// menu. « Tout activer » vise les membres de la section **dans le cadrage
/// courant** (X57) — `section.mods` en est déjà le reflet.
struct ModListSectionHeader: View {
    let page: ModListPageSection
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject var listState: ModListState
    let onToggleCollapse: () -> Void

    private var title: String {
        let base = page.section.title ?? localization.L(
            page.section.key == .uncategorized ? L10n.Mods.groupUncategorized : L10n.Mods.groupUngrouped)
        return page.continued ? String(format: localization.L(L10n.Mods.groupContinued), base) : base
    }

    var body: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Button(action: onToggleCollapse) {
                Image(systemName: page.section.collapsed ? "chevron.right" : "chevron.down")
                    .frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusRing()
            .accessibilityLabel(title)
            Text(title).font(AppDesign.Font.headline(.semibold)).lineLimit(1)
            Text(String(format: localization.L(L10n.Mods.groupCount),
                        Int64(page.section.mods.count), Int64(page.section.pausedCount)))
                .font(AppDesign.Font.footnote).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            ModGroupHeaderMenu(section: page.section, viewModel: viewModel, localization: localization, listState: listState)
        }
        .padding(.vertical, AppDesign.Spacing.xs)
    }
}
