import SwiftUI

/// N-04 — « À régler » et « Récemment installés », sous les tuiles de
/// l'Accueil. Les tuiles comptent ; ces lignes **nomment** et conduisent.
/// Le choix et l'ordre des lignes vivent dans `HomeAgenda` (Core, testé).
struct HomeAgendaSections: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xl) {
            toFixSection
            recentSection
        }
    }

    // MARK: - À régler

    private var toFixSection: some View {
        let agenda = HomeAgenda.toFix(viewModel.healthIssues)
        return section(localization.L(L10n.Home.agendaTitle)) {
            if agenda.rows.isEmpty {
                // « Un 0 se lit » (I-T9) : la section reste, et dit pourquoi
                // elle est vide.
                calmLine(localization.L(L10n.Home.agendaEmpty), icon: "checkmark.circle.fill")
            } else {
                ForEach(agenda.rows) { issue in
                    HomeAgendaRow(icon: issue.severity == .critical ? "exclamationmark.octagon.fill"
                                                                     : "exclamationmark.triangle.fill",
                                  tint: issue.severity == .critical ? AppDesign.Color.error
                                                                    : AppDesign.Color.warning,
                                  title: issue.titleKey.map { localization.L($0) } ?? issue.title,
                                  subtitle: issue.detail) { open(issue) }
                }
                if agenda.remaining > 0 {
                    Button(localization.plural(L10n.Home.agendaMore, agenda.remaining)) { openAlerts() }
                        .buttonStyle(.link)
                        .padding(.horizontal, AppDesign.Spacing.md)
                        .padding(.vertical, AppDesign.Spacing.sm)
                }
            }
        }
    }

    /// Le geste des Alertes système (`SystemAlertsView.perform`), réduit à
    /// ce qui **ouvre** : une écriture (renommer, réparer, réinstaller) se
    /// fait aux Alertes, où sa feuille et ses gardes vivent.
    private func open(_ issue: HealthIssue) {
        let navigation = viewModel.navigationStore
        switch HomeAgenda.destination(of: issue) {
        case .openMod(let query)?:
            navigation.openModDetail(folderName: query, door: .alert(dependency: false))
        case .openModDependencies(let query)?:
            navigation.openModDetail(folderName: query, door: .alert(dependency: true))
        case .openModConfig(let folderName, let keyPath)?:
            if viewModel.openModConfig(forFolder: folderName, keyPath: keyPath) { currentTab = .mods }
        case .openLogs(let searchText)?:
            navigation.openLog(search: searchText)
        default:
            openAlerts()
        }
    }

    /// La liste des alertes, pas l'onglet mémorisé (comme la tuile).
    private func openAlerts() {
        viewModel.navigationStore.alertsSegment = .alerts
        currentTab = .systemAlerts
    }

    // MARK: - Récemment installés

    private var recentSection: some View {
        let recent = HomeAgenda.recentlyInstalled(viewModel.scanStore.mods)
        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: localization.currentLanguage)
        return section(localization.L(L10n.Home.recentTitle)) {
            if recent.isEmpty {
                calmLine(localization.L(L10n.Home.recentEmpty), icon: "clock")
            } else {
                ForEach(recent) { mod in
                    HomeAgendaRow(icon: mod.isGroup ? "shippingbox.fill" : "puzzlepiece.extension.fill",
                                  tint: .secondary, title: mod.name,
                                  subtitle: mod.effectiveInstallDate.map { relative.localizedString(for: $0, relativeTo: Date()) }) {
                        // L'Aperçu, où vit « Ce qui a changé » (T20).
                        viewModel.navigationStore.openModDetail(folderName: mod.folderName, door: .listRow)
                    }
                }
            }
        }
    }

    // MARK: - Mise en page

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(title)
                .font(AppDesign.Font.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) { rows() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(padding: AppDesign.Spacing.xs)
        }
    }

    private func calmLine(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(AppDesign.Font.body)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppDesign.Spacing.md)
            .padding(.vertical, AppDesign.Spacing.sm)
    }
}

/// Une ligne qui conduit : glyphe, titre, sous-titre, chevron. Toute la
/// ligne est la cible.
private struct HomeAgendaRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppDesign.Spacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppDesign.Font.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppDesign.Font.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: AppDesign.Spacing.sm)
                Image(systemName: "chevron.right")
                    .font(AppDesign.Font.iconXS)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AppDesign.Spacing.md)
            .padding(.vertical, AppDesign.Spacing.sm)
            .contentShape(.rect)
        }
        .buttonStyle(.plain).focusRing()
        .accessibilityElement(children: .combine)
    }
}
