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
/// La feuille de la page : le renommage du dossier disputé par deux mods
/// (X60). Porte le nom **logique** : c'est lui que les deux prétendants ont en
/// commun. Les deux panoramas (raccourcis, conflits), autrefois des feuilles,
/// sont des onglets (`AlertsSegment`).
private struct RenameFolderSheet: Identifiable {
    let name: String
    var id: String { name }
}

struct SystemAlertsView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination

    /// H-T6b — la liste triée répond à « qu'est-ce qui casse, emmène-moi
    /// là » ; le rapport des raccourcis et le panorama des conflits répondent
    /// à « montre-moi tout ». D'abord feuilles, trop chargées pour une
    /// popup : ils sont devenus des onglets (audit UX 2026-10-02).
    @State private var renameSheet: RenameFolderSheet?
    /// Filtre posé par une tuile de gravité ; `nil` = tout.
    @State private var severityFilter: HealthIssue.Severity?

    var body: some View {
        // Capturée UNE fois par rendu (revue globale, bloquant 7) :
        // `vm.healthIssues` est une propriété CALCULÉE qui retrie et
        // reconstruit un `Set` sur le parc entier (~966 mods chez l'auteur)
        // — la relire à chaque usage (vide, liste, tuiles, sous-titre)
        // referait ce travail plusieurs fois par rendu SwiftUI, fréquent.
        let issues = vm.healthIssues
        VStack(alignment: .leading, spacing: 0) {
            header(issues)
            segmentPicker(issues)
            Divider()
            // `switch`, pas des onglets montés : le rapport des raccourcis
            // lance une analyse à son apparition — monté d'office, il
            // rescannerait le parc à chaque visite des alertes.
            switch vm.navigationStore.alertsSegment {
            case .alerts:
                alertsList(issues)
            case .keybinds:
                ScrollView {
                    KeybindReportSection(vm: vm, localization: localization, currentTab: $currentTab)
                        .padding(AppDesign.Spacing.lg)
                }
            case .conflicts:
                ScrollView {
                    VStack(spacing: AppDesign.Spacing.lg) {
                        ModConflictSection(vm: vm, localization: localization)
                        // A5-T7 — hors pastille : un recouvrement n'est pas un conflit.
                        PerformanceOverlapSection(vm: vm, localization: localization)
                    }
                    .padding(AppDesign.Spacing.lg)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppDesign.Color.windowBg)
        .sheet(item: $renameSheet) { target in
            renameSheetContent(target.name)
        }
    }

    /// L'état vide ne concerne que la liste : un parc sans alerte garde ses
    /// onglets Raccourcis et Conflits, justement ce qu'on vient vérifier.
    @ViewBuilder
    private func alertsList(_ issues: [HealthIssue]) -> some View {
        // Capturée UNE fois par rendu (revue globale, bloquant 7) :
        // `vm.healthIssues` est une propriété CALCULÉE qui retrie et
        // reconstruit un `Set` sur le parc entier (~966 mods chez l'auteur).
        let shown = severityFilter.map { f in issues.filter { $0.severity == f } } ?? issues
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

    /// Les trois onglets, chacun avec le compte de ses alertes — les chiffres
    /// que portaient les anciens boutons d'en-tête.
    private func segmentPicker(_ issues: [HealthIssue]) -> some View {
        Picker("", selection: Binding(get: { vm.navigationStore.alertsSegment },
                                      set: { vm.navigationStore.alertsSegment = $0 })) {
            ForEach(AlertsSegment.allCases, id: \.self) { segment in
                Text(segmentLabel(segment, issues)).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, AppDesign.Spacing.lg)
        .padding(.bottom, AppDesign.Spacing.sm)
        .background(AppDesign.Color.windowBg)
    }

    private func segmentLabel(_ segment: AlertsSegment, _ issues: [HealthIssue]) -> String {
        let (key, count): (String, Int)
        switch segment {
        case .alerts:    (key, count) = (L10n.Health.tabAlerts, issues.count)
        case .keybinds:  (key, count) = (L10n.Keybinds.title, issues.count { $0.source == .keybind })
        case .conflicts: (key, count) = (L10n.Conflicts.title, issues.count { $0.source == .modConflict })
        }
        let title = localization.L(key)
        return count > 0 ? "\(title) (\(count))" : title
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

    /// Le renommage, en feuille : la section ne porte aucun contrôle de
    /// fermeture propre — pied « OK », même patron que
    /// `ProfileDiagnosticsView`.
    private func renameSheetContent(_ name: String) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                ModFolderRenameSection(vm: vm, localization: localization, folderName: name) { renameSheet = nil }
                    .padding(AppDesign.Spacing.lg)
            }
            Divider()
            HStack {
                Spacer()
                Button(localization.L(L10n.Main.ok)) { renameSheet = nil }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(AppDesign.Spacing.md)
        }
        .frame(minWidth: 560, idealWidth: 680, minHeight: 360, idealHeight: 480)
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
            renameSheet = RenameFolderSheet(name: name)
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
