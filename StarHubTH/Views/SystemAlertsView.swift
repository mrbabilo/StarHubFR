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
        // Capturée UNE fois par rendu (revue globale, bloquant 7) :
        // `vm.healthIssues` est une propriété CALCULÉE qui retrie et
        // reconstruit un `Set` sur le parc entier (~966 mods chez l'auteur)
        // — la lire 4 fois (isEmpty, ForEach, footer, filtre critiques)
        // referait ce travail 4 fois par rendu SwiftUI, fréquent.
        let issues = vm.healthIssues
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if issues.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Identité dérivée du contenu : `HealthIssue.id` est
                        // stable par construction (tâches 1-3) — jamais
                        // `id: \.self` ni l'index sur cette liste.
                        ForEach(issues) { issue in
                            row(for: issue)
                            Divider()
                        }
                    }
                    .padding(.horizontal, AppDesign.Spacing.lg)
                }
                footer(for: issues)
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
                Button(vm.L(actionLabelKey(forTab: tab))) { currentTab = tab }
                    .buttonStyle(.plain)
                    .foregroundColor(AppDesign.Color.accent)
                    .pointingHandCursor()
            }
        }
        .padding(.vertical, AppDesign.Spacing.sm)
    }

    /// Le libellé doit dire OÙ le bouton mène : « Voir les journaux » pour
    /// une ligne SMAPI ouvrait déjà le bon onglet, mais les lignes raccourci
    /// et conflit portent aussi ce libellé alors qu'elles ouvrent l'onglet
    /// Mods — l'utilisateur clique « Voir les journaux » et atterrit dans la
    /// liste des mods (revue globale de branche, bloquant 3).
    private func actionLabelKey(forTab tab: String) -> String {
        tab == "Logs" ? L10n.Updates.viewLogs : L10n.Updates.viewMods
    }

    // MARK: - Footer

    /// Pied honnête : le total est `issues.actionableCount` — critique +
    /// avertissement, jamais `.count` brut (revue globale, bloquant 1). Une
    /// notice `.info` reste visible dans la liste au-dessus mais ne compte
    /// pas ici : sinon 7 notices bénignes sur un parc sain (0 échec, 0
    /// conflit, mesuré sur le journal réel de l'auteur) annonceraient
    /// « 7 problèmes » en pied de page. Les critiques restent un filtrage
    /// direct sur la gravité.
    private func footer(for issues: [HealthIssue]) -> some View {
        Text(String(format: vm.L(L10n.Health.problemCount),
                    Int64(issues.actionableCount),
                    Int64(issues.filter { $0.severity == .critical }.count)))
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
