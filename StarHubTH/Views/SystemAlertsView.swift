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
/// Les deux panoramas (raccourcis, conflits) passent par **un seul**
/// modificateur `.sheet(item:)`, porté par cette valeur — même contrainte que
/// `SaveEditorConfirmation`/`SaveTimelineConfirmation` (`SavesView.swift`,
/// `SaveTimelineView.swift`) : deux `.sheet` empilés sur la même vue ne se
/// présentent pas tous les deux.
private enum SystemAlertsSheet: Identifiable {
    case keybindReport
    case modConflicts

    var id: String {
        switch self {
        case .keybindReport: return "keybindReport"
        case .modConflicts: return "modConflicts"
        }
    }
}

struct SystemAlertsView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @Binding var currentTab: String

    /// H-T6b — `KeybindReportSection` et `ModConflictSection` n'avaient plus
    /// aucun appelant depuis que tâche 7 a remplacé leurs trois sections par
    /// une liste unifiée : le rapport complet des raccourcis (mods scannés,
    /// non reconnus, « Rescanner ») et le panorama des conflits avaient donc
    /// disparu de l'app. Ils reviennent en feuilles : la liste triée garde
    /// son rôle (« qu'est-ce qui casse, emmène-moi là »), les panoramas
    /// répondent à l'autre question (« montre-moi tout »).
    @State private var sheet: SystemAlertsSheet?

    var body: some View {
        // Capturée UNE fois par rendu (revue globale, bloquant 7) :
        // `vm.healthIssues` est une propriété CALCULÉE qui retrie et
        // reconstruit un `Set` sur le parc entier (~966 mods chez l'auteur)
        // — la lire 4 fois (isEmpty, ForEach, footer, filtre critiques)
        // referait ce travail 4 fois par rendu SwiftUI, fréquent.
        let issues = vm.healthIssues
        VStack(alignment: .leading, spacing: 0) {
            header(issues)
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
        // Un seul `.sheet` pour les deux panoramas (voir `SystemAlertsSheet`).
        .sheet(item: $sheet) { which in
            sheetContent(which)
        }
    }

    // MARK: - Header

    private func header(_ issues: [HealthIssue]) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Text(vm.L(L10n.Main.systemAlerts))
                .font(AppDesign.Font.viewTitle)
            Spacer()
            // Comptes dérivés de la liste DÉJÀ capturée, jamais de
            // `vm.activeConflictCount` : celui-ci relit `vm.healthIssues`,
            // propriété calculée qui retrie le parc entier (~966 mods).
            panoramaButton(vm.L(L10n.Keybinds.title), icon: "keyboard",
                           count: issues.count { $0.source == .keybind }) { sheet = .keybindReport }
            panoramaButton(vm.L(L10n.Conflicts.title), icon: "arrow.triangle.merge",
                           count: issues.count { $0.source == .modConflict }) { sheet = .modConflicts }
            recheckLogButton
        }
        .padding(.horizontal, AppDesign.Spacing.lg)
        .padding(.vertical, AppDesign.Spacing.md)
        .background(AppDesign.Color.windowBg)
    }

    /// Bouton de barre d'outils ouvrant l'un des deux panoramas — même style
    /// que `recheckLogButton`, pour que les trois lisent comme un seul groupe
    /// d'actions plutôt que deux styles différents côte à côte.
    private func panoramaButton(_ label: String, icon: String, count: Int,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppDesign.Spacing.xs) {
                Label(label, systemImage: icon)
                // Capsule cachée à zéro, bouton toujours visible — même règle
                // que `SidebarItem` : la destination existe même quand elle
                // ne compte rien, et un panorama vide reste consultable.
                if count > 0 {
                    Text("\(count)")
                        .font(AppDesign.Font.footnote(.bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .padding(.horizontal, 4)
                        .background(AppDesign.Color.primary)
                        .clipShape(Capsule())
                }
            }
            .font(AppDesign.Font.caption(.medium))
            .foregroundColor(AppDesign.Color.primary)
            .padding(.horizontal, AppDesign.Spacing.md)
            .padding(.vertical, AppDesign.Spacing.xs)
            .background(AppDesign.Color.primary.opacity(AppDesign.Opacity.light))
            .cornerRadius(AppDesign.Radius.sm)
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHandCursor()
    }

    /// Le panorama demandé, en feuille : les deux sections ne portent aucun
    /// contrôle de fermeture propre (elles vivaient nues dans l'ancien écran
    /// à trois sections) — celle-ci leur ajoute un pied « OK », même patron
    /// que `ProfileDiagnosticsView`.
    @ViewBuilder
    private func sheetContent(_ which: SystemAlertsSheet) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                switch which {
                case .keybindReport:
                    KeybindReportSection(vm: vm, currentTab: $currentTab)
                        .padding(AppDesign.Spacing.lg)
                case .modConflicts:
                    ModConflictSection(vm: vm)
                        .padding(AppDesign.Spacing.lg)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button(vm.L(L10n.Main.ok)) { sheet = nil }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(AppDesign.Spacing.md)
        }
        // Les deux panoramas alignent des noms de mods tronqués à une ligne
        // (`lineLimit(1)` + `truncationMode(.middle)`), et une ligne de conflit
        // en montre DEUX côte à côte : la largeur décide de ce qui se lit.
        // Le parc de l'auteur porte des noms de 30+ caractères
        // (« Valley Bonds: One Piece Framework »).
        .frame(minWidth: 760, idealWidth: 980, minHeight: 560, idealHeight: 720)
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
                // `titleKey` n'est posé que quand le titre est un libellé
                // d'interface et non une donnée (notice bénigne sans mod) —
                // voir `HealthIssue.titleKey`.
                Text(issue.titleKey.map { vm.L($0) } ?? issue.title)
                    .font(AppDesign.Font.body)
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
            ForEach(issue.actions) { action in
                Button(actionLabel(for: action)) { perform(action) }
                    .buttonStyle(.plain)
                    .foregroundColor(AppDesign.Color.accent)
                    .pointingHandCursor()
            }
        }
        .padding(.vertical, AppDesign.Spacing.sm)
    }

    /// Le libellé doit dire OÙ le bouton mène : l'ancien `openTab(String)`
    /// menait au mieux à un onglet générique (« Voir les journaux » ouvrait
    /// la vue générale, « Voir les mods » la liste entière) — jamais l'erreur
    /// ni le mod fautif eux-mêmes (H-T6b).
    private func actionLabel(for action: HealthIssue.Action) -> String {
        switch action {
        case .openMod: return vm.L(L10n.Health.actionOpenMod)
        case .openLogs: return vm.L(L10n.Health.actionOpenLogs)
        }
    }

    /// Pose la cible sur le ViewModel puis bascule d'onglet — jamais
    /// l'inverse : `MainView` remet à `nil` les états de détail dans son
    /// `onChange(of: currentTab)`, donc poser `viewingModDetail` avant de
    /// changer d'onglet serait effacé aussitôt (piège documenté dans
    /// `CLAUDE.md`, patron B3-T4). `pendingModDetailFocus` traverse ce
    /// changement et se reconsomme DANS le même `onChange`.
    private func perform(_ action: HealthIssue.Action) {
        switch action {
        case .openMod(let query):
            vm.pendingModDetailFocus = query
            // Une alerte parle de l'état du mod, pas de sa description.
            vm.pendingDetailTab = .state
            currentTab = "Mods"
        case .openLogs(let searchText):
            vm.pendingLogFocus = searchText
            currentTab = "Logs"
        }
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
