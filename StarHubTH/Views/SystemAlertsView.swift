import SwiftUI

// MARK: - System Alerts View

/// Liste unifiée des problèmes de santé du parc — erreurs SMAPI, conflits de
/// raccourcis, conflits de mods — triée par gravité (tâche 7, H-T6).
///
/// `viewModel.healthIssues` porte déjà la résolution et le tri (voir
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
    var viewModel: StarHubTHViewModel
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
        // Capturée UNE fois par rendu (revue globale, bloquant 7) ; depuis
        // F3, `viewModel.healthIssues` est stockée — recalculée aux événements,
        // jamais à l'accès. La capture locale reste le geste obvious.
        let issues = viewModel.healthIssues
        VStack(alignment: .leading, spacing: 0) {
            header(issues)
            segmentPicker(issues)
            Divider()
            // `switch`, pas des onglets montés : le rapport des raccourcis
            // lance une analyse à son apparition — monté d'office, il
            // rescannerait le parc à chaque visite des alertes.
            switch viewModel.navigationStore.alertsSegment {
            case .alerts:
                alertsList(issues)
            case .keybinds:
                BackToTopScrollView(localization) {
                    KeybindReportSection(vm: viewModel, localization: localization, currentTab: $currentTab)
                        .padding(AppDesign.Spacing.lg)
                }
            case .conflicts:
                BackToTopScrollView(localization) {
                    VStack(spacing: AppDesign.Spacing.lg) {
                        ModConflictSection(vm: viewModel, localization: localization)
                        // A5-T7 — hors pastille : un recouvrement n'est pas un conflit.
                        PerformanceOverlapSection(viewModel: viewModel, localization: localization)
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
        let shown = severityFilter.map { f in issues.filter { $0.severity == f } } ?? issues
        if issues.isEmpty {
            emptyState
        } else {
            BackToTopScrollView(localization) {
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
        Picker("", selection: Binding(get: { viewModel.navigationStore.alertsSegment },
                                      set: { viewModel.navigationStore.alertsSegment = $0 })) {
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
        // R2 — `actionableCount`, comme la pastille et l'en-tête : les
        // notices `.info` restent dans leur tuile, pas dans ce chiffre.
        case .alerts:    (key, count) = (L10n.Health.tabAlerts, issues.actionableCount)
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
        return PageContextBar(icon: worst == nil ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                              context: issues.isEmpty ? nil
                                  : String(format: localization.L(L10n.Health.problemCount),  // E8 : pluriels justes
                                           localization.plural(L10n.Health.problems, issues.actionableCount),
                                           localization.plural(L10n.Health.criticals, issues.filter { $0.severity == .critical }.count)),
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
            logSourceLine
        }
    }

    /// R2 — le journal dont dérivent les lignes SMAPI, son âge s'il est
    /// périmé, et le chemin vers son rapport complet (Diagnostic, onglet
    /// Santé). Rien sans journal lu : raccourcis et conflits s'en passent.
    @ViewBuilder
    private var logSourceLine: some View {
        if let source = SmapiLogSource(logDate: viewModel.smapiLogDate, isStale: viewModel.smapiLogStale,
                                       locale: Locale(identifier: localization.currentLanguage)) {
            SplitRow {
                Text(String(format: localization.L(L10n.Health.logSource), source.date)
                     + (source.staleAge.map { " — " + String(format: localization.L(L10n.Health.logStaleAge), $0) } ?? ""))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(source.staleAge == nil ? AppDesign.Color.secondary : AppDesign.Color.warning)
            } trailing: {
                Button(localization.L(L10n.Health.logOpenHealth)) {
                    // Le segment d'abord : il survit au changement d'onglet.
                    viewModel.navigationStore.diagnosticsSegment = .health
                    currentTab = .logs
                }
                .buttonStyle(.link).clickableCursor().focusRing(cornerRadius: 4)
                .font(AppDesign.Font.footnote)
            }
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
                ModFolderRenameSection(vm: viewModel, localization: localization, folderName: name) { renameSheet = nil }
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
            // Un conflit offre deux fiches (N-09 S7) : un menu nommé par mod,
            // plutôt que deux « Voir la fiche » indiscernables.
            let mods = issue.actions.filter { if case .openMod = $0 { true } else { false } }
            if mods.count > 1 {
                ModPairDetailMenu(folders: mods.compactMap { if case .openMod(let f) = $0 { f } else { nil } },
                                  name: { ModFocusResolver.resolve($0, in: viewModel.scanStore.mods)?.name ?? $0 },
                                  navigation: viewModel.navigationStore, localization: localization)
            }
            ForEach(mods.count > 1 ? issue.actions.filter { !mods.contains($0) } : issue.actions) { action in
                actionButtons(for: action)
            }
        }
        .padding(.vertical, AppDesign.Spacing.sm)
        .padding(.trailing, AppDesign.Spacing.md)
    }

    /// R7 — sans Premium, « Réinstaller » grisé, bouton Nexus à côté (règle de la fiche).
    @ViewBuilder
    private func actionButtons(for action: HealthIssue.Action) -> some View {
        let premiumNexusId: Int? = if case .reinstallFromNexus(let id) = action, viewModel.nexusDirectDownloadUnavailable { id } else { nil }
        Group {
            Button(actionLabel(for: action)) { perform(action) }.focusRing(cornerRadius: 4)
                .disabled(premiumNexusId != nil)
                .help(premiumNexusId != nil ? localization.L(L10n.Mods.premiumOnlyHint) : "")
            if let premiumNexusId {
                Button {
                    NSWorkspace.shared.open(MissingDependencies.filesPage(nexusId: premiumNexusId))
                } label: {
                    Label(localization.L(L10n.Mods.translationOpenNexus), systemImage: "arrow.up.right.square")
                }.focusRing(cornerRadius: 4)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .buttonStyle(.borderless)
        .controlSize(.small)
        .pointingHandCursor()
    }

    /// Le libellé doit dire OÙ le bouton mène : l'ancien `openTab(String)`
    /// menait au mieux à un onglet générique (« Voir les journaux » ouvrait
    /// la vue générale, « Voir les mods » la liste entière) — jamais l'erreur
    /// ni le mod fautif eux-mêmes (H-T6b).
    private func actionLabel(for action: HealthIssue.Action) -> String {
        switch action {
        case .openMod, .openModDependencies: return localization.L(L10n.Health.actionOpenMod)
        case .openModConfig: return localization.L(L10n.Health.actionOpenSetting)
        case .openLogs: return localization.L(L10n.Health.actionOpenLogs)
        case .revealInFinder: return localization.L(L10n.Health.actionRevealInFinder)
        case .renameFolder: return localization.L(L10n.Health.actionRenameFolder)
        // A1-T2 — les deux gestes qui ramènent le mod dans le jeu : le
        // libellé dit lequel (backup local, ou Nexus).
        case .repairManifest: return localization.L(L10n.Health.actionRepairManifest)
        case .reinstallFromNexus: return localization.L(L10n.Health.actionReinstallNexus)
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
            viewModel.navigationStore.openModDetail(folderName: query, door: .alert(dependency: false))
        case .openModDependencies(let query):
            viewModel.navigationStore.openModDetail(folderName: query, door: .alert(dependency: true))
        case .openModConfig(let folderName, let keyPath):
            if viewModel.openModConfig(forFolder: folderName, keyPath: keyPath) { currentTab = .mods }
        case .openLogs(let searchText):
            // Onglet Journal, filtre et page d'un coup (D4-T4 §3a) : sans le
            // segment, la page s'ouvrirait sur Santé, sans filtre visible.
            viewModel.navigationStore.openLog(search: searchText)
        case .revealInFinder(let paths):
            // Les deux dossiers sélectionnés **ensemble** : c'est ce qui montre
            // lequel porte le point de tête, donc lequel est en pause. Ouvrir
            // « le » dossier choisirait au hasard entre les deux prétendants.
            NSWorkspace.shared.activateFileViewerSelecting(
                paths.map { URL(fileURLWithPath: $0) })
        case .renameFolder(let name):
            renameSheet = RenameFolderSheet(name: name)
        case .repairManifest(let folderName):
            // Le rescan qui suit la copie fait disparaître la ligne — ou la
            // laisse si le manifeste du backup est cassé lui aussi.
            viewModel.restoreManifest(folderName: folderName)
        case .reinstallFromNexus(let nexusId):
            viewModel.downloadModFromNexus(nexusId: nexusId)
        }
    }
}

/// La barre de répartition : un segment par gravité, proportionnel. Les
/// tuiles au-dessus portent les chiffres ; la barre donne la proportion.
