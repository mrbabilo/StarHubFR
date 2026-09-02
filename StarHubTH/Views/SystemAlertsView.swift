import SwiftUI

// MARK: - System Alerts View

/// Liste unifiée des problèmes de santé du parc — erreurs SMAPI, conflits de
/// raccourcis, conflits de mods — triée par gravité (tâche 7, H-T6).
///
/// `vm.healthIssues` porte déjà la résolution et le tri (voir
/// `StarHubTHViewModel.healthIssues` et `HealthIssueResolver`) : cette vue
/// affiche, elle ne retrie ni ne refiltre jamais cette liste.
///
/// Les erreurs SMAPI restent aussi consultables dans l'onglet Journaux (voir
/// `StarHubTHViewModel.parseSMAPILog`) : ce panneau n'en est qu'un résumé.
struct SystemAlertsView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @Binding var currentTab: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if vm.healthIssues.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Identité dérivée du contenu : `HealthIssue.id` est
                        // stable par construction (tâches 1-3) — jamais
                        // `id: \.self` ni l'index sur cette liste.
                        ForEach(vm.healthIssues) { issue in
                            row(for: issue)
                            Divider()
                        }
                    }
                    .padding(.horizontal, AppDesign.Spacing.lg)
                }
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppDesign.Color.windowBg)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(vm.L(L10n.Main.systemAlerts))
                .font(AppDesign.Font.viewTitle)
            Spacer()
            recheckLogButton
        }
        .padding(.horizontal, AppDesign.Spacing.lg)
        .padding(.vertical, AppDesign.Spacing.md)
        .background(AppDesign.Color.windowBg)
    }

    // MARK: - Rows

    private func row(for issue: HealthIssue) -> some View {
        HStack(spacing: AppDesign.Spacing.md) {
            // Cas courant de `SeverityBadge` : le libellé est résolu depuis
            // la gravité elle-même (voir doc de tête du composant) — ce n'est
            // pas le cas « libellé différent » de son second initialiseur.
            SeverityBadge(severity: issue.severity, L: vm.L)
                .frame(width: 130, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title).font(AppDesign.Font.body)
                // `detail` est un diagnostic brut venu du journal SMAPI —
                // de la DONNÉE, pas de la copie d'interface : il ne passe
                // jamais par L10n. Bridé à 2 lignes, ces raisons peuvent
                // être longues (noms de mods, messages d'échec).
                if let detail = issue.detail {
                    Text(detail)
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(AppDesign.Color.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: AppDesign.Spacing.sm)
            if case .openTab(let tab) = issue.action {
                Button(vm.L(L10n.Updates.viewLogs)) { currentTab = tab }
                    .buttonStyle(.plain)
                    .foregroundColor(AppDesign.Color.accent)
                    .pointingHandCursor()
            }
        }
        .padding(.vertical, AppDesign.Spacing.sm)
    }

    // MARK: - Footer

    /// Pied honnête : une ligne EST un problème (spec §2/§3 de la tâche) —
    /// le total est `healthIssues.count`, les critiques un filtrage sur la
    /// gravité, jamais une autre arithmétique.
    private var footer: some View {
        Text(String(format: vm.L(L10n.Health.problemCount),
                    Int64(vm.healthIssues.count),
                    Int64(vm.healthIssues.filter { $0.severity == .critical }.count)))
            .font(AppDesign.Font.footnote)
            .foregroundColor(AppDesign.Color.secondary)
            .padding(AppDesign.Spacing.md)
    }

    // MARK: - Empty state

    /// État vide conservé dans son esprit d'origine : coche verte, message
    /// rassurant. Le journal date de la dernière partie — pas de bouton
    /// dédié ici, le « Revérifier » de l'en-tête couvre déjà ce cas.
    private var emptyState: some View {
        VStack {
            Spacer()
            HStack(spacing: AppDesign.Spacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppDesign.Color.success)
                    .font(.system(size: 28))
                Text(vm.L(L10n.Updates.noAlerts))
                    .font(AppDesign.Font.headline)
                    .foregroundColor(AppDesign.Color.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Relit le journal SMAPI sans rescaner le parc — la page ne montre que
    /// ce que dit le journal, c'est lui seul qu'il faut relire.
    @ViewBuilder
    private var recheckLogButton: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Button(action: { vm.refreshSmapiLog() }) {
                Label(vm.L(L10n.Updates.recheckLog), systemImage: "arrow.clockwise")
                    .font(AppDesign.Font.caption(.medium))
                    .foregroundColor(AppDesign.Color.primary)
                    .padding(.horizontal, AppDesign.Spacing.md)
                    .padding(.vertical, AppDesign.Spacing.xs)
                    .background(AppDesign.Color.primary.opacity(AppDesign.Opacity.light))
                    .cornerRadius(AppDesign.Radius.sm)
            }
            .buttonStyle(PlainButtonStyle())
            .pointingHandCursor()
            .disabled(vm.isRefreshingSmapiLog)
            if vm.isRefreshingSmapiLog {
                ProgressView().controlSize(.small)
            }
        }
    }
}
