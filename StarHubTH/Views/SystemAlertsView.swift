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
    /// Le renommage du dossier disputé par deux mods (X60). Porte le nom
    /// **logique** : c'est lui que les deux prétendants ont en commun.
    case renameFolder(String)

    var id: String {
        switch self {
        case .keybindReport: return "keybindReport"
        case .modConflicts: return "modConflicts"
        case .renameFolder(let name): return "rename:\(name)"
        }
    }
}

struct SystemAlertsView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination

    /// H-T6b — `KeybindReportSection` et `ModConflictSection` n'avaient plus
    /// aucun appelant depuis que tâche 7 a remplacé leurs trois sections par
    /// une liste unifiée : le rapport complet des raccourcis (mods scannés,
    /// non reconnus, « Rescanner ») et le panorama des conflits avaient donc
    /// disparu de l'app. Ils reviennent en feuilles : la liste triée garde
    /// son rôle (« qu'est-ce qui casse, emmène-moi là »), les panoramas
    /// répondent à l'autre question (« montre-moi tout »).
    @State private var sheet: SystemAlertsSheet?
    /// Filtre posé par une tuile de gravité ; `nil` = tout.
    @State private var severityFilter: HealthIssue.Severity?

    var body: some View {
        // Capturée UNE fois par rendu (revue globale, bloquant 7) :
        // `vm.healthIssues` est une propriété CALCULÉE qui retrie et
        // reconstruit un `Set` sur le parc entier (~966 mods chez l'auteur)
        // — la relire à chaque usage (vide, liste, tuiles, sous-titre)
        // referait ce travail plusieurs fois par rendu SwiftUI, fréquent.
        let issues = vm.healthIssues
        let shown = severityFilter.map { f in issues.filter { $0.severity == f } } ?? issues
        VStack(alignment: .leading, spacing: 0) {
            header(issues)
            Divider()

            if issues.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                        summary(issues)
                        LazyVStack(alignment: .leading, spacing: 0) {
                            // Identité dérivée du contenu : `HealthIssue.id` est
                            // stable par construction (tâches 1-3) — jamais
                            // `id: \.self` ni l'index sur cette liste.
                            ForEach(shown) { issue in
                                row(for: issue)
                                if issue.id != shown.last?.id { Divider() }
                            }
                        }
                        .cardSurface(padding: 0)
                    }
                    .padding(AppDesign.Spacing.lg)
                }
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
        let worst = issues.map(\.severity).max()
        // Le sous-titre compte `actionableCount` — une notice `.info` ne
        // compte jamais comme problème (revue globale, bloquant 1 : 7 notices
        // bénignes sur un parc sain annonçaient « 7 problèmes »).
        return PageHeader(icon: worst == nil ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                          title: localization.L(L10n.Main.systemAlerts),
                          subtitle: issues.isEmpty ? nil
                              : String(format: localization.L(L10n.Health.problemCount),
                                       Int64(issues.actionableCount),
                                       Int64(issues.filter { $0.severity == .critical }.count)),
                          tint: tint(for: worst)) {
            panoramaButton(localization.L(L10n.Keybinds.title), icon: "keyboard",
                           count: issues.count { $0.source == .keybind }) { sheet = .keybindReport }
            panoramaButton(localization.L(L10n.Conflicts.title), icon: "arrow.triangle.merge",
                           count: issues.count { $0.source == .modConflict }) { sheet = .modConflicts }
            recheckLogButton
        }
        .padding(.horizontal, AppDesign.Spacing.lg)
        .padding(.vertical, AppDesign.Spacing.md)
        .background(AppDesign.Color.windowBg)
    }

    /// La couleur d'une gravité — vert quand il n'y a rien : un état réussi,
    /// pas une absence d'information. Toujours doublée d'un glyphe ou d'un mot.
    private func tint(for severity: HealthIssue.Severity?) -> Color {
        switch severity {
        case .critical: return AppDesign.Color.error
        case .warning: return AppDesign.Color.warning
        case .info: return AppDesign.Color.info
        case nil: return AppDesign.Color.success
        }
    }

    /// Trois tuiles qui filtrent la liste, puis la barre de répartition : ce
    /// qui est cassé se voit avant de lire une ligne.
    private func summary(_ issues: [HealthIssue]) -> some View {
        let counts = Dictionary(grouping: issues, by: \.severity).mapValues(\.count)
        return VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            WrapHStack(spacing: AppDesign.Spacing.sm, lineSpacing: AppDesign.Spacing.sm) {
                severityTile(.critical, icon: "exclamationmark.octagon.fill",
                             label: L10n.Health.tileCritical, count: counts[.critical] ?? 0)
                severityTile(.warning, icon: "exclamationmark.triangle.fill",
                             label: L10n.Health.tileWarning, count: counts[.warning] ?? 0)
                severityTile(.info, icon: "info.circle.fill",
                             label: L10n.Health.tileInfo, count: counts[.info] ?? 0)
            }
            SeverityBar(segments: [HealthIssue.Severity.critical, .warning, .info].map {
                SeverityBar.Segment(count: counts[$0] ?? 0, color: tint(for: $0))
            })
            .accessibilityLabel(localization.L(L10n.Health.distributionLabel))
        }
    }

    private func severityTile(_ severity: HealthIssue.Severity, icon: String,
                              label: String, count: Int) -> some View {
        MetricTile(icon: icon, value: count, label: localization.L(label),
                   tint: tint(for: severity), isSelected: severityFilter == severity,
                   help: localization.L(L10n.Health.tileFilterHint)) {
            withMotion(.snappy) { severityFilter = severityFilter == severity ? nil : severity }
        }
        .disabled(count == 0 && severityFilter != severity)
    }

    /// Bouton de barre d'outils ouvrant l'un des deux panoramas — même style
    /// que `recheckLogButton`, pour que les trois lisent comme un seul groupe
    /// d'actions plutôt que deux styles différents côte à côte.
    private func panoramaButton(_ label: String, icon: String, count: Int,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppDesign.Spacing.xs) {
                Label(label, systemImage: icon)
                if count > 0 {
                    Text("\(count)")
                        .font(AppDesign.Font.footnote(.bold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .padding(.horizontal, 4)
                        .background(AppDesign.Color.accent, in: Capsule())
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
                    KeybindReportSection(vm: vm, localization: localization, currentTab: $currentTab)
                        .padding(AppDesign.Spacing.lg)
                case .modConflicts:
                    VStack(spacing: AppDesign.Spacing.lg) {
                        ModConflictSection(vm: vm, localization: localization)
                        // A5-T7 — hors pastille : un recouvrement n'est pas un conflit.
                        PerformanceOverlapSection(vm: vm, localization: localization)
                    }
                    .padding(AppDesign.Spacing.lg)
                case .renameFolder(let name):
                    ModFolderRenameSection(vm: vm, localization: localization, folderName: name) { sheet = nil }
                        .padding(AppDesign.Spacing.lg)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button(localization.L(L10n.Main.ok)) { sheet = nil }
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
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint(for: issue.severity))
                .frame(width: 3)
                .padding(.vertical, 2)
                .accessibilityHidden(true)
            // Cas courant de `SeverityBadge` : le libellé est résolu depuis
            // la gravité elle-même (voir doc de tête du composant) — ce n'est
            // pas le cas « libellé différent » de son second initialiseur.
            SeverityBadge(severity: issue.severity, L: localization.L)
                .frame(width: 130, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                // `titleKey` n'est posé que quand le titre est un libellé
                // d'interface et non une donnée (notice bénigne sans mod) —
                // voir `HealthIssue.titleKey`.
                Text(issue.titleKey.map { localization.L($0) } ?? issue.title)
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
            // Une information en offre DEUX (fiche + journal) : les libellés
            // gardent leur largeur, c'est le titre qui cède. « Voir dans les
            // journaux » est le plus long des deux en français ; le voir
            // tronqué ou replié dirait moins que le titre tronqué à côté.
            ForEach(issue.actions) { action in
                Button(actionLabel(for: action)) { perform(action) }
                    .lineLimit(1)
                    .fixedSize()
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .pointingHandCursor()
            }
        }
        .padding(.vertical, AppDesign.Spacing.sm)
        .padding(.trailing, AppDesign.Spacing.md)
    }

    /// Le libellé doit dire OÙ le bouton mène : l'ancien `openTab(String)`
    /// menait au mieux à un onglet générique (« Voir les journaux » ouvrait
    /// la vue générale, « Voir les mods » la liste entière) — jamais l'erreur
    /// ni le mod fautif eux-mêmes (H-T6b).
    private func actionLabel(for action: HealthIssue.Action) -> String {
        switch action {
        case .openMod: return localization.L(L10n.Health.actionOpenMod)
        case .openLogs: return localization.L(L10n.Health.actionOpenLogs)
        case .revealInFinder: return localization.L(L10n.Health.actionRevealInFinder)
        case .renameFolder: return localization.L(L10n.Health.actionRenameFolder)
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
            vm.navigationStore.pendingModDetailFocus = query
            // Une alerte parle de l'état du mod, pas de sa description.
            vm.navigationStore.pendingDetailTab = .health
            currentTab = .mods
        case .openLogs(let searchText):
            // Onglet Journal, filtre et page d'un coup (D4-T4 §3a) : sans le
            // segment, la page s'ouvrirait sur Santé, sans filtre visible.
            vm.navigationStore.openLog(search: searchText)
        case .revealInFinder(let paths):
            // Les deux dossiers sélectionnés **ensemble** : c'est ce qui montre
            // lequel porte le point de tête, donc lequel est en pause. Ouvrir
            // « le » dossier choisirait au hasard entre les deux prétendants.
            NSWorkspace.shared.activateFileViewerSelecting(
                paths.map { URL(fileURLWithPath: $0) })
        case .renameFolder(let name):
            sheet = .renameFolder(name)
        }
    }

    // MARK: - État vide

    /// État vide : bouclier vert qui s'installe, message rassurant, et ce qui
    /// a été vérifié. Le journal date de la dernière partie — pas de bouton
    /// dédié ici, le « Revérifier » de l'en-tête couvre déjà ce cas.
    private var emptyState: some View {
        VStack(spacing: AppDesign.Spacing.md) {
            Spacer()
            AllClearGlyph()
            Text(localization.L(L10n.Updates.noAlerts))
                .font(AppDesign.Font.headline(.semibold))
            Text(localization.L(L10n.Health.allClearHint))
                .font(AppDesign.Font.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .padding(AppDesign.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Relit le journal SMAPI sans rescaner le parc — la page ne montre que
    /// ce que dit le journal, c'est lui seul qu'il faut relire.
    @ViewBuilder
    private var recheckLogButton: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Button(action: { vm.refreshSmapiLog() }) {
                Label(localization.L(L10n.Updates.recheckLog), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()
            .disabled(vm.isRefreshingSmapiLog)
            if vm.isRefreshingSmapiLog {
                ProgressView().controlSize(.small)
            }
        }
    }
}

/// La barre de répartition : un segment par gravité, proportionnel. Les
/// tuiles au-dessus portent les chiffres ; la barre donne la proportion.
private struct SeverityBar: View {
    struct Segment: Equatable {
        let count: Int
        let color: Color
    }
    let segments: [Segment]

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.count }, 1)
        let visible = segments.filter { $0.count > 0 }
        GeometryReader { geo in
            let gaps = CGFloat(max(visible.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, seg in
                    Capsule()
                        .fill(seg.color.gradient)
                        .frame(width: max(6, (geo.size.width - gaps) * CGFloat(seg.count) / CGFloat(total)))
                }
            }
        }
        .frame(height: 6)
        .animation(Motion.animation(.smooth), value: segments.map(\.count))
    }
}

/// Le glyphe de l'état « rien à signaler », qui s'installe en douceur à
/// l'arrivée (aucune animation sous « Réduire les animations »).
private struct AllClearGlyph: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AppDesign.Color.success.opacity(AppDesign.Opacity.light))
                .frame(width: 96, height: 96)
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: AppDesign.Font.scaled(44)))
                .foregroundStyle(AppDesign.Color.success.gradient)
        }
        .scaleEffect(shown ? 1 : 0.85)
        .opacity(shown ? 1 : 0)
        .onAppear { withMotion(.spring(duration: 0.5, bounce: 0.3)) { shown = true } }
        .accessibilityHidden(true)
    }
}
