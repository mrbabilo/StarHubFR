import SwiftUI

struct MainView: View {
     @Bindable var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    // Observé séparément (même patron que `smapiInstaller`/`bisection` dans
    // HomeView) : `report` est publié par `KeybindScanService`, un
    // `ObservableObject` distinct — sans cet abonnement, la pastille ne se
    // redessinerait jamais quand le scan termine (tâche 7).
    @ObservedObject private var keybindScanService: KeybindScanService
    @State private var currentTab: SidebarDestination = .home

    init(vm: StarHubTHViewModel, localization: LocalizationStore) {
        self.localization = localization
        self.vm = vm
        self.keybindScanService = vm.keybindScanService
    }

    // History Management
    @State private var tabHistory: [SidebarDestination] = [.home]
    @State private var forwardHistory: [SidebarDestination] = []
    @State private var isNavigatingBackOrForward = false
    
    @AppStorage("appColorScheme") private var appColorScheme: String = "System"
    @AppStorage("launchProfile") private var launchProfile: String = "SMAPI"
    
    @State private var isProfileHovered = false
    @State private var showDownloadedInstall = false
    /// La feuille d'installation rouverte sur l'archive suivante d'un dépôt
    /// multiple — le canal `vm.pendingDropPresentation` est posé par le
    /// bouton « Archive suivante » de la fenêtre de bilan. ⚠️ Son onDismiss
    /// ne discard RIEN : ce sont les fichiers originaux de l'utilisateur.
    @State private var showDropInstall = false
    @State private var showCommandPalette = false
    @Environment(\.openWindow) private var openWindow

    /// L'alerte « nouvelle release de StarHubFR » n'est présentée que si
    /// aucune feuille d'installation n'occupe la fenêtre : deux `.sheet`
    /// simultanés et l'un se perd en silence (spec §7.4).
    private var canPresentReleaseAlert: Bool {
        !showDownloadedInstall && !showDropInstall
    }

    /// Aucune feuille ni voile modal à l'écran : une superposition présentée
    /// dessous serait invisible, et laisserait un état ouvert que personne ne
    /// voit — la famille de bugs de `releaseCheckInFlight`.
    ///
    /// Bâtie **sur** `canPresentReleaseAlert` plutôt qu'en recopiant sa liste :
    /// deux conditions jumelles divergeraient au premier ajout de feuille. S'y
    /// ajoutent l'alerte de release elle-même (à l'écran dès qu'un tag est
    /// disponible et que le gate la laisse passer) et l'application de profil,
    /// dont le voile vit dans ce ZStack : la palette se dessinerait par-dessus
    /// et laisserait naviguer pendant que les dossiers bougent.
    private var canPresentPalette: Bool {
        canPresentReleaseAlert
            && vm.availableAppRelease == nil
            && vm.profileApplyProgress == nil
    }
    

    private var navigationTitleText: String {
        if currentTab == .saves && vm.navigationStore.viewingSaveTimeline != nil { return localization.L(L10n.Saves.timeline) }
        if currentTab == .saves && vm.navigationStore.editingSave != nil { return vm.navigationStore.editingSave!.playerName }
        if currentTab == .mods && vm.navigationStore.editingModConfig != nil { return vm.navigationStore.editingModConfig!.name }
        if currentTab == .mods && vm.navigationStore.viewingModDetail != nil { return vm.navigationStore.viewingModDetail!.name }
        // Le titre de base — exhaustif, **jamais de `default:`** : une
        // destination ajoutée sans titre est une erreur de build, pas une
        // fenêtre qui s'intitule « Accueil » sans qu'on le remarque.
        switch currentTab {
        case .mods:           return localization.L(L10n.Mods.mods)
        case .installBackups: return localization.L(L10n.ModInstall.manageBackups)
        case .configBackups:  return localization.L(L10n.ModConfigBackups.title)
        case .maintenance:    return localization.L(L10n.Maintenance.title)
        case .profiles:       return localization.L(L10n.Profiles.title)
        case .updates:        return localization.L(L10n.Main.modUpdates)
        case .systemAlerts:   return localization.L(L10n.Main.systemAlerts)
        case .discover:       return localization.L(L10n.Main.discover)
        case .quarantine:     return localization.L(L10n.Main.quarantine)
        case .frenchTranslations: return localization.L(L10n.FrTranslations.title)
        case .saves:          return localization.L(L10n.Saves.saves)
        case .settings:       return localization.L(L10n.Settings.settings)
        case .logs:           return localization.L(L10n.Logs.logs)
        case .appChangelog:   return localization.L(L10n.Main.appChangelog)
        case .home:           return localization.L(L10n.Main.home)
        }
    }
    
    /// Le consommage des foci en attente + l'historique de navigation.
    /// Extrait du `.onChange` en même temps que `destinationView`, pour
    /// la même raison.
    private func handleTabChange() {
            vm.navigationStore.setEditingSave(nil)
            vm.navigationStore.viewingSaveTimeline = nil
            vm.navigationStore.setEditingModConfig(nil)
            vm.navigationStore.setViewingModDetail(nil)

            // …sauf ce qu'une intention en attente demande d'ouvrir. Les
            // trois n'ont pas le même sort — la traduction survit (la vue la
            // consomme plus tard pour l'onglet), les deux autres s'effacent —
            // et trois fonctionnalités s'y sont cassé les dents. La règle
            // vit désormais dans `TabChangePlan` (Core, 11 tests, six
            // sabotages) : elle était ici, hors de portée d'un test.
            let plan = TabChangePlan.decide(
                entering: currentTab,
                pending: .init(translationFocus: vm.navigationStore.pendingTranslationFocus,
                               configFocus: vm.navigationStore.pendingConfigFocus,
                               modDetailFocus: vm.navigationStore.pendingModDetailFocus),
                mods: vm.scanStore.mods)
            if plan.clearsConfigFocus { vm.navigationStore.pendingConfigFocus = nil }
            if plan.clearsModDetailFocus { vm.navigationStore.pendingModDetailFocus = nil }
            if plan.clearsPendingDetailTab { vm.navigationStore.pendingDetailTab = nil }
            // Conditionnel : les cinq `nil` sont déjà passés, et une
            // affectation `nil` de plus rejouerait deux `didSet`.
            if let detail = plan.openModDetail { vm.navigationStore.setViewingModDetail(detail) }
            if let config = plan.openModConfig { vm.navigationStore.setEditingModConfig(config) }

            if !isNavigatingBackOrForward {
                if tabHistory.last != currentTab {
                    tabHistory.append(currentTab)
                    forwardHistory.removeAll()
                }
            } else {
                isNavigatingBackOrForward = false
            }
    }

    /// La vue de détail de l'onglet courant. Extraite du `body` le
    /// 2026-09-10 : l'ajout du paramètre `localization` à chaque
    /// destination a fait franchir au `body` le seuil de saturation du
    /// type-checker (piège documenté CLAUDE.md) — découper en sous-vues
    /// est le remède.
    @ViewBuilder
    private var destinationView: some View {
                    switch currentTab {
                    case .mods:
                        if let mod = vm.navigationStore.editingModConfig {
                            // L'onglet visuel par défaut : c'est celui qui montre
                            // les réglages du mod, l'onglet de code étant le repli
                            // pour ce que l'écran ne sait pas rendre.
                            ModConfigEditorView(vm: vm, localization: localization, mod: mod)
                        } else if let mod = vm.navigationStore.viewingModDetail {
                            ModDetailView(vm: vm, localization: localization, mod: mod)
                                .id(mod.folderName)
                        } else {
                            ModListView(vm: vm, localization: localization, currentTab: $currentTab)
                        }
                    case .configBackups:
                        ModConfigBackupsView(vm: vm, localization: localization)
                    case .maintenance:
                        MaintenanceView(vm: vm, localization: localization)
                    case .installBackups:
                        ModInstallBackupsView(vm: vm, localization: localization)
                    case .saves:
                        if let save = vm.navigationStore.viewingSaveTimeline {
                            SaveTimelineView(vm: vm, localization: localization, save: save)
                        } else if let save = vm.navigationStore.editingSave {
                            SaveEditorView(vm: vm, localization: localization, save: save, currentTab: $currentTab)
                        } else {
                            SavesView(vm: vm, localization: localization)
                        }
                    case .profiles:
                        ModProfilesView(vm: vm, localization: localization, currentTab: $currentTab)
                    case .updates:
                        UpdatesView(vm: vm, localization: localization, currentTab: $currentTab)
                    case .systemAlerts:
                        SystemAlertsView(vm: vm, localization: localization, currentTab: $currentTab)
                    case .quarantine:
                        QuarantineView(vm: vm, localization: localization)
                    case .discover:
                        DiscoverView(vm: vm, localization: localization, currentTab: $currentTab)
                    case .frenchTranslations:
                        FrenchTranslationsView(vm: vm, localization: localization, currentTab: $currentTab)
                    case .settings:
                        SettingsView(vm: vm, localization: localization)
                    case .logs:
                        LogsView(vm: vm, localization: localization)
                    case .appChangelog:
                        AppChangelogView(vm: vm, localization: localization)
                    case .home:
                        HomeView(vm: vm, localization: localization, currentTab: $currentTab)
                    }
    }

    /// Les boutons d'historique (retour/avant). Extraits du `body` le
    /// 2026-09-10 avec `destinationView` pour la même raison : saturation
    /// du type-checker.
    private var navHistoryButtons: some View {
                    HStack(spacing: 8) {
                    Button(action: {
                        if vm.navigationStore.editingSave != nil {
                            vm.navigationStore.setEditingSave(nil)
                        } else if vm.navigationStore.viewingSaveTimeline != nil {
                            vm.navigationStore.viewingSaveTimeline = nil
                        } else if vm.navigationStore.editingModConfig != nil {
                            vm.navigationStore.setEditingModConfig(nil)
                        } else if vm.navigationStore.viewingModDetail != nil {
                            vm.navigationStore.setViewingModDetail(nil)
                        } else if tabHistory.count > 1 {
                            isNavigatingBackOrForward = true
                            let current = tabHistory.removeLast()
                            forwardHistory.append(current)
                            currentTab = tabHistory.last ?? .home
                        }
                    }) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(localization.L(L10n.Main.navBack))
                    .help(localization.L(L10n.Main.navBack))
                    .disabled(vm.navigationStore.editingSave == nil && vm.navigationStore.viewingSaveTimeline == nil && vm.navigationStore.editingModConfig == nil && vm.navigationStore.viewingModDetail == nil && tabHistory.count <= 1)
                    
                    Button(action: {
                        if let next = forwardHistory.popLast() {
                            isNavigatingBackOrForward = true
                            tabHistory.append(next)
                            currentTab = next
                        }
                    }) {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel(localization.L(L10n.Main.navForward))
                    .help(localization.L(L10n.Main.navForward))
                    .disabled(forwardHistory.isEmpty)
                }
    }

    /// La colonne latérale. Extraite du `body` le 2026-09-10, dans la
    /// même série que `destinationView` : saturation du type-checker.
    private var sidebarColumn: some View {
                VStack(spacing: 0) {
    
                    // Account Header Card — compact identity + active profile +
                    // key metadata (mods active/total, SMAPI status). Replaces the
                    // old bulky 48px avatar and the floating SystemStatusFooter:
                    // everything the user needs at-a-glance is now in one card.
                    AccountHeaderCard(
                        vm: vm,
                        localization: localization,
                        isActive: currentTab == .home,
                        isHovered: isProfileHovered,
                        onTap: { currentTab = .home }
                    )
                    .onHover { isProfileHovered = $0 }
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
    
                    // En fenêtre basse, ce sont les groupes qui défilent :
                    // l'ancienne pile plein-fixe écrêtait d'abord le bas de la
                    // colonne — poids de `Mods/`, thème, langue — sous la hauteur
                    // disponible. Patron des pages de liste : haut fixe, milieu
                    // défilant, pied épinglé.
                    ScrollView(.vertical) {
                        SidebarNavGroups(vm: vm, localization: localization, currentTab: $currentTab)
                            .padding(.horizontal, 10)
                    }
    
                    SidebarPinnedFooter(vm: vm, localization: localization, appColorScheme: $appColorScheme)
                }
                .frame(minWidth: 240, idealWidth: 240, maxWidth: 240, maxHeight: .infinity, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                sidebarColumn

        } detail: {
            // ── CONTENT AREA ─────────────────────────────────────────
            Group {
                // ⚠️ Exhaustif, et **jamais de `default:`** : c'est le
                // compilateur qui garantit qu'aucune destination ne se
                // retrouve sans page. Avant le 2026-09-09 cette répartition
                // comparait des chaînes, et un identifiant mal écrit rendait
                // une page blanche en silence. Même règle que
                // `SettingsSectionOrder.sectionView`.
                destinationView
            }
            .navigationTitle(navigationTitleText)
            .onChange(of: currentTab) { _, _ in handleTabChange() }
            .toolbar { ToolbarItem(placement: .navigation) { navHistoryButtons } }
            .frame(minWidth: 560, minHeight: 400)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        
            // Application d'un profil : le voile couvre toute la fenêtre, pas
            // seulement la page des profils — « Gérer » applique le profil puis
            // bascule sur la page des mods, et l'utilisateur y attendrait
            // devant une liste figée sans savoir pourquoi.
            if let progress = vm.profileApplyProgress {
                switch progress.phase {
                case .movingFolders:
                    ModalProgressOverlay(label: localization.L(L10n.Profiles.applyingMoving),
                                         done: progress.done,
                                         total: progress.total)
                case .rescanning:
                    // Le rescane publie déjà son propre avancement pour le
                    // voile de démarrage : on le montre plutôt que de laisser
                    // la barre pleine du temps d'avant.
                    ModalProgressOverlay(label: localization.L(L10n.Profiles.applyingScanning),
                                         done: vm.scanStore.scanProgress?.done ?? 0,
                                         total: vm.scanStore.scanProgress?.total ?? 0)
                }
            }

            // La palette ⌘K — au sommet du ZStack, donc au-dessus du voile
            // d'application de profil. Elle ne s'y ouvre pas pour autant :
            // `canPresentPalette` le refuse (voir plus haut).
            if showCommandPalette {
                CommandPaletteView(vm: vm, localization: localization, isPresented: $showCommandPalette)
                    .zIndex(10)
            }
        } // End of outer ZStack
        // No launch overlay here any more: the splash is its own window
        // (`LaunchSplashController`) and this window stays hidden until the
        // app is ready, so there's never a half-loaded UI to cover up.
        .frame(minWidth: 820, minHeight: 520)
        .preferredColorScheme(colorScheme)
        .environment(\.locale, Locale(identifier: localization.currentLanguage))
        .onReceive(NotificationCenter.default.publisher(for: .jumpToMod)) { notification in
            if let modName = notification.object as? String {
                vm.selectedModID = ModFocusResolver.resolve(modName, in: vm.scanStore.mods)?.folderName
                // Hand the request to the list itself: it may not be on screen
                // yet (tabs are created on demand), so it picks this up on
                // appear and scopes itself to the mod.
                vm.navigationStore.pendingModFocus = modName
                currentTab = .mods
            }
        }
        // Le menu « Aller » et la palette demandent un onglet ; c'est ici, où
        // vit `currentTab`, qu'il s'applique (patron B3-T4).
        .onChange(of: vm.pendingTabRequest) { _, requested in
            guard let requested else { return }
            vm.consumePendingTabRequest()
            currentTab = requested
        }
        // ⌘K depuis le menu. **Refus assumé quand une feuille est ouverte** :
        // la superposition se dessinerait sous elle — invisible, alors que la
        // palette se croirait ouverte. On vide le canal sans rien ouvrir.
        //
        // ⚠️ **Bascule, pas ouverture.** ⌘K doit refermer ce qu'il a ouvert
        // (spec §7). Un `guard canPresentPalette` seul ne le permettait pas :
        // le garde tombait dès la palette ouverte, le canal se vidait, et
        // rien ne se passait — ⌘K ouvrait sans jamais refermer.
        .onChange(of: vm.paletteRequested) { _, requested in
            guard requested else { return }
            vm.consumePaletteRequest()
            if showCommandPalette {
                showCommandPalette = false
            } else if canPresentPalette {
                showCommandPalette = true
            }
        }
        .alert(isPresented: Binding(get: { vm.alertStore.shown }, set: { vm.alertStore.shown = $0 })) {
            Alert(
                title: Text(localization.L(L10n.Main.alert)),
                message: Text(vm.alertStore.message),
                dismissButton: .default(Text(localization.L(L10n.Main.ok)))
            )
        }
        // A1-T8 — au niveau racine : l'état suspendu dans le VM doit survivre au changement d'onglet.
        .saveFingerprintPauseGate(vm: vm)
        // R2 — une application de profil morte en route : reprendre ou
        // garder l'état actuel. Patron confirmationDialog de ModProfilesView
        // (suppression de profil) ; présenté une seule fois la fenêtre
        // révélée (surfaceApplyRecoveryIfNeeded).
        .confirmationDialog(
            vm.applyRecoveryDialogText ?? "",
            isPresented: Binding(
                get: { vm.pendingApplyRecovery != nil },
                set: { if !$0 { vm.dismissApplyRecovery() } }
            ),
            titleVisibility: .visible
        ) {
            if vm.recoveryProfileExists {
                Button(localization.L(L10n.VM.profileRecoveryResume)) { vm.resumeInterruptedApply() }
                Button(localization.L(L10n.VM.profileRecoveryKeep), role: .cancel) { vm.keepCurrentDiskState() }
            } else {
                Button(localization.L(L10n.VM.profileRecoveryDismiss), role: .cancel) { vm.dismissApplyRecovery() }
            }
        }
        .onChange(of: vm.pendingDownloadedZip) { _, newValue in
            showDownloadedInstall = (newValue != nil)
        }
        .sheet(isPresented: $showDownloadedInstall, onDismiss: {
            if let url = vm.pendingDownloadedZip {
                // Le fichier **et** le dossier qui l'isolait : le
                // téléchargement le pose sous son vrai nom, dans un dossier à
                // lui, pour que deux fichiers homonymes ne se croisent pas.
                NexusFileDownload.discardDownloaded(at: url)
            }
            vm.pendingDownloadedZip = nil
            vm.pendingNexusSource = nil
            // La feuille fermée, le créneau de téléchargement est libre :
            // la file nxm:// peut dérouler le lien suivant, s'il y en a.
            vm.drainQueuedNexusDownloads()
        }) {
            ModInstallView(vm: vm, localization: localization, currentTab: $currentTab, isPresented: $showDownloadedInstall, preloadedZip: vm.pendingDownloadedZip)
        }
        // Le bilan d'installation vit dans SA fenêtre — ouverte dès qu'un
        // report est posé (réouverture idempotente, contenu remplacé).
        .onChange(of: vm.pendingInstallReport) { _, report in
            guard report != nil else { return }
            openWindow(id: AppWindowID.installReport)
        }
        // « Archive suivante » de la fenêtre de bilan : la feuille se
        // rouvre sur l'archive posée (chemin preloadedZip existant).
        .onChange(of: vm.pendingDropPresentation) { _, url in
            guard url != nil else { return }
            showDropInstall = true
        }
        .sheet(isPresented: $showDropInstall, onDismiss: {
            // PAS de discard ici : fichiers originaux de l'utilisateur.
            vm.clearDropPresentation()
        }) {
            ModInstallView(vm: vm, localization: localization, currentTab: $currentTab,
                           isPresented: $showDropInstall,
                           preloadedZip: vm.pendingDropPresentation)
        }
        // « Voir la fiche » depuis la fenêtre de bilan : la décision vit
        // ici, où seul vit `currentTab` (patron B3-T4).
        .onChange(of: vm.reportDetailFocus) { _, folder in
            guard let folder else { return }
            if currentTab == .mods,
               let target = ModFocusResolver.resolve(folder, in: vm.scanStore.mods) {
                vm.navigationStore.setViewingModDetail(target)
                vm.navigationStore.pendingDetailTab = .state
            } else {
                vm.navigationStore.pendingModDetailFocus = folder
                vm.navigationStore.pendingDetailTab = .state
                currentTab = .mods
            }
            // Amener la fenêtre principale devant : la fiche s'y pose, la
            // fenêtre de bilan reste ouverte derrière.
            openWindow(id: AppWindowID.main)
            vm.consumeReportDetailFocus()
        }
        // L'alerte release attend son tour : posée par le check au lancement,
        // elle rattrape à la fermeture de chaque feuille. `item:` plutôt que
        // `isPresented:` — la release à afficher EST l'état, et un corps
        // conditionnel pouvait s'évaluer vide une frame (les boutons vident
        // `availableAppRelease` avant que le drapeau ne retombe). Le gate de
        // priorité vit dans le `get` : une feuille d'installation ouverte
        // rend `nil`, et l'alerte revient d'elle-même à sa fermeture.
        .sheet(item: Binding(
            get: { canPresentReleaseAlert ? vm.availableAppRelease : nil },
            set: { newValue in
                // Fermeture par Esc ou clic hors cadre = acquittement aussi.
                // ⚠️ Seulement si l'alerte était bien présentable : quand
                // c'est le gate qui vient de la retirer (une feuille s'est
                // ouverte par-dessus), acquitter tairait un tag que
                // l'utilisateur n'a jamais vu.
                guard newValue == nil, canPresentReleaseAlert,
                      let release = vm.availableAppRelease else { return }
                vm.acknowledgeRelease(release)
            }
        )) { release in
            AppUpdateAlertView(vm: vm, localization: localization, release: release)
        }
    }
    

    var colorScheme: ColorScheme? {
        switch appColorScheme {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
    }
}
