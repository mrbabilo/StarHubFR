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
    @AppStorage("showThaiTranslationHub") private var showThaiTranslationHub: Bool = false
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
        if currentTab == .saves && vm.viewingSaveTimeline != nil { return localization.L(L10n.Saves.timeline) }
        if currentTab == .saves && vm.editingSave != nil { return vm.editingSave!.playerName }
        if currentTab == .thaiHub && vm.viewingThaiMod != nil { return vm.viewingThaiMod!.name }
        if currentTab == .mods && vm.editingModConfig != nil { return vm.editingModConfig!.name }
        if currentTab == .mods && vm.viewingModDetail != nil { return vm.viewingModDetail!.name }
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
        case .thaiHub:        return localization.L(L10n.ThaiHub.title)
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
            vm.editingSave = nil
            vm.viewingThaiMod = nil
            vm.viewingSaveTimeline = nil
            vm.editingModConfig = nil
            vm.viewingModDetail = nil

            // …sauf une demande de traduction, qui est précisément **ce
            // qui** amène sur cet onglet (B3-T4, depuis la couverture
            // française d'un profil). La poser avant de changer d'onglet
            // ne servait à rien : la remise à zéro ci-dessus l'effaçait
            // aussitôt, et le bouton n'ouvrait que la liste des mods.
            if currentTab == .mods, let folderName = vm.pendingTranslationFocus {
                vm.viewingModDetail = vm.mods.flattenedMods
                    .first { $0.folderName == folderName }
            }

            // T8 — même piège, même cure pour l'éditeur de config,
            // demandé depuis le rapport de raccourcis (Alertes système).
            // Contrairement à la traduction, rien ne se consomme plus
            // tard dans la vue : l'éditeur n'a pas d'onglet à présélectionner,
            // on l'ouvre donc ici et on efface la demande aussitôt — sans
            // quoi chaque retour sur l'onglet la rejouerait.
            if currentTab == .mods, let folderName = vm.pendingConfigFocus {
                vm.pendingConfigFocus = nil
                vm.editingModConfig = vm.mods.flattenedMods
                    .first { $0.folderName == folderName }
            }

            // H-T6b — même piège, même cure pour la fiche mod, demandée
            // depuis l'écran d'alertes système : une ligne SMAPI porte un
            // nom affiché, une ligne de conflit un `folderName` —
            // `ModFocusResolver` accepte les deux.
            if currentTab == .mods, let query = vm.pendingModDetailFocus {
                vm.pendingModDetailFocus = nil
                vm.viewingModDetail = ModFocusResolver.resolve(query, in: vm.mods)
                // Résolution vide : aucune fiche ne s'ouvrira, donc
                // personne ne consommera l'onglet demandé — il faut
                // l'effacer ici, sinon la prochaine fiche ouverte à la
                // main s'ouvrirait sur « État » sans raison.
                if vm.viewingModDetail == nil { vm.pendingDetailTab = nil }
            }

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
                        if let mod = vm.editingModConfig {
                            // L'onglet visuel par défaut : c'est celui qui montre
                            // les réglages du mod, l'onglet de code étant le repli
                            // pour ce que l'écran ne sait pas rendre.
                            ModConfigEditorView(vm: vm, localization: localization, mod: mod)
                        } else if let mod = vm.viewingModDetail {
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
                        if let save = vm.viewingSaveTimeline {
                            SaveTimelineView(vm: vm, localization: localization, save: save)
                        } else if let save = vm.editingSave {
                            SaveEditorView(vm: vm, localization: localization, save: save)
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
                    case .thaiHub:
                        ThaiTranslationHubView(vm: vm, localization: localization)
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
                        if vm.editingSave != nil {
                            vm.editingSave = nil
                        } else if vm.viewingThaiMod != nil {
                            vm.viewingThaiMod = nil
                        } else if vm.viewingSaveTimeline != nil {
                            vm.viewingSaveTimeline = nil
                        } else if vm.editingModConfig != nil {
                            vm.editingModConfig = nil
                        } else if vm.viewingModDetail != nil {
                            vm.viewingModDetail = nil
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
                    .disabled(vm.editingSave == nil && vm.viewingThaiMod == nil && vm.viewingSaveTimeline == nil && vm.editingModConfig == nil && vm.viewingModDetail == nil && tabHistory.count <= 1)
                    
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
                                         done: vm.scanProgress?.done ?? 0,
                                         total: vm.scanProgress?.total ?? 0)
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
                vm.selectedModID = ModFocusResolver.resolve(modName, in: vm.mods)?.folderName
                // Hand the request to the list itself: it may not be on screen
                // yet (tabs are created on demand), so it picks this up on
                // appear and scopes itself to the mod.
                vm.pendingModFocus = modName
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
        .alert(isPresented: $vm.showAlert) {
            Alert(
                title: Text(localization.L(L10n.Main.alert)),
                message: Text(vm.alertMessage),
                dismissButton: .default(Text(localization.L(L10n.Main.ok)))
            )
        }
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
               let target = ModFocusResolver.resolve(folder, in: vm.mods) {
                vm.viewingModDetail = target
                vm.pendingDetailTab = .state
            } else {
                vm.pendingModDetailFocus = folder
                vm.pendingDetailTab = .state
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

// MARK: - Sidebar Nav Groups

/// Les quatre groupes d'entrées de la barre latérale — Bibliothèque, Parties,
/// Santé & secours, Application. Extrait du corps de `MainView` (densité) et
/// posé dans le `ScrollView` de la colonne : en fenêtre basse, ce sont ces
/// lignes qui défilent, pas les réglages du bas.
struct SidebarNavGroups: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination
    @AppStorage("showThaiTranslationHub") private var showThaiTranslationHub = false

    /// Le badge d'une destination — donnée **vivante** du ViewModel, pas de
    /// `SidebarOrder` : il change à chaque scan. `nil` quand l'entrée ne
    /// compte rien.
    private func badge(_ d: SidebarDestination) -> (count: Int, color: Color)? {
        switch d {
        case .updates:
            return (vm.outOfDateMods.count + vm.nexusUpdates.count, .blue)
        case .systemAlerts:
            return (vm.systemAlertCount, .orange)
        case .quarantine:
            return (vm.lastRepairReport?.quarantined.count ?? 0, .purple)
        default:
            return nil
        }
    }

    private func group(_ g: SidebarGroup, header: String,
                       icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarSectionHeader(title: header, icon: icon)
            ForEach(SidebarOrder.entries(in: g,
                                         showThaiHub: showThaiTranslationHub)) { e in
                // `badge: Int?` est déjà optionnel côté SidebarItem — `nil`
                // veut dire « cet item ne compte rien », `0` « il compte, et
                // il n'y a rien ». Pas de branche à écrire.
                let b = badge(e.destination)
                SidebarItem(icon: e.icon, label: localization.L(e.labelKey),
                            tab: e.destination, badge: b?.count,
                            badgeColor: b?.color ?? .blue,
                            currentTab: $currentTab)
            }
        }
    }

    /// Le groupe `.top` (l'Accueil) n'est **pas** rendu ici : il vit dans
    /// `AccountHeaderCard`, en tête de colonne. Il est dans `SidebarOrder`
    /// parce que le menu « Aller » et la palette en ont besoin, pas la barre.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            group(.library, header: localization.L(L10n.Main.groupLibrary),
                  icon: "square.grid.2x2")
            group(.saves, header: localization.L(L10n.Main.groupSaves),
                  icon: "gamecontroller")
            group(.health, header: localization.L(L10n.Main.groupHealth),
                  icon: "cross.case")
            group(.app, header: localization.L(L10n.Main.groupApp), icon: "gearshape")
        }
    }
}

// MARK: - Sidebar Pinned Footer

/// Le pied épinglé de la barre latérale : volet de téléchargement Nexus,
/// poids de `Mods/`, réglages de thème et de langue. Ce bloc doit rester
/// visible quelle que soit la hauteur de la fenêtre — c'est lui que
/// l'ancienne pile plein-fixe laissait écrêter en premier.
struct SidebarPinnedFooter: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var appColorScheme: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Au-dessus du poids de `Mods/` : un lien `nxm://` peut
            // arriver du navigateur quel que soit l'onglet ouvert, et le
            // téléchargement n'avait jusqu'ici pour tout témoin qu'un
            // spinner sur la page des mises à jour.
            NexusDownloadFooter(vm: vm, localization: localization)

            ModsWeightFooter(vm: vm, localization: localization)

            // Bottom bar: theme switcher (left) + language switcher (right).
            HStack {
                ThemeToggle(vm: vm, localization: localization, appColorScheme: $appColorScheme)
                Spacer()
                LanguageFlagToggle(vm: vm, localization: localization)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

// MARK: - Sidebar Section Header
/// Compact language switcher shown at the bottom of the sidebar: two flag
/// buttons (🇫🇷 / 🇬🇧) with the active language highlighted. Setting
/// `localization.currentLanguage` swaps the bundle live (same path as before), so the UI
/// re-localizes immediately.
struct LanguageFlagToggle: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        HStack(spacing: 2) {
            flagButton(flag: "🇫🇷", code: "fr", help: localization.L(L10n.Settings.languageFrench))
            flagButton(flag: "🇬🇧", code: "en", help: localization.L(L10n.Settings.languageEnglish))
        }
        .padding(3)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }

    private func flagButton(flag: String, code: String, help: String) -> some View {
        let isActive = localization.currentLanguage == code
        return Button {
            if localization.currentLanguage != code { localization.setLanguage(code) }
        } label: {
            Text(flag)
                .font(.system(size: 15))
                .grayscale(isActive ? 0 : 0.9)
                .opacity(isActive ? 1 : 0.55)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.22) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Compact appearance switcher shown at the bottom-left of the sidebar: System
/// / Light / Dark, mirroring the language flag toggle on the right. Writes the
/// same `appColorScheme` AppStorage the app reads for `preferredColorScheme`.
struct ThemeToggle: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var appColorScheme: String

    var body: some View {
        HStack(spacing: 2) {
            themeButton(icon: "circle.lefthalf.filled", value: "System", help: localization.L(L10n.Settings.themeSystem))
            themeButton(icon: "sun.max.fill", value: "Light", help: localization.L(L10n.Settings.themeLight))
            themeButton(icon: "moon.fill", value: "Dark", help: localization.L(L10n.Settings.themeDark))
        }
        .padding(3)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }

    private func themeButton(icon: String, value: String, help: String) -> some View {
        let isActive = appColorScheme == value
        return Button {
            if appColorScheme != value { appColorScheme = value }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isActive ? .accentColor : .secondary)
                .opacity(isActive ? 1 : 0.6)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
        .accessibilityLabel(help)
    }
}

struct SidebarSectionHeader: View {
    let title: String
    var icon: String = ""   // optionnel, vide par défaut (pas de breaking change)

    var body: some View {
        HStack(spacing: AppDesign.Spacing.xs + 2) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(AppDesign.Font.iconXS.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            Text(title)
                .font(AppDesign.Font.caption(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(.leading, AppDesign.Spacing.sm)
        .padding(.top, AppDesign.Spacing.sm)
        .padding(.bottom, 0)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - SMAPI Alerts UI
// MARK: - Updates View (macOS System Settings style)
struct UpdatesView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Out of date mods (Software Update style)
                if !vm.outOfDateMods.isEmpty {
                    // Ces cartes n'avaient aucun en-tête, quand celles de Nexus
                    // en ont un : rien ne disait d'où venait l'information, ni
                    // pourquoi ces mods-là étaient là et pas d'autres.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.system(size: 16))
                            Text(localization.L(L10n.Updates.smapiSection))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        Text(localization.L(L10n.Updates.smapiNote))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(vm.outOfDateMods) { mod in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 16) {
                                // App Icon Fake
                                InitialsAvatar(
                                    text: mod.name,
                                    initialsCount: 2,
                                    size: 56,
                                    fillColor: Color.blue.opacity(0.1),
                                    textColor: .blue.opacity(0.8),
                                    fontSize: 20
                                )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mod.name)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.primary)
                                    // `ModUpdateInfo.version` est la version
                                    // **disponible** — celle que SMAPI annonce
                                    // dans « You can update N mods ». Nue sous
                                    // le nom du mod, elle se lisait comme la
                                    // version installée, c'est-à-dire l'inverse.
                                    Text(String(format: localization.L(L10n.Updates.availableVersion),
                                                mod.version))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    
                                    // Pas « disponible sur Nexus Mods » :
                                    // ces lignes viennent du journal SMAPI, et
                                    // leur lien pointe vers smapi.io. Le mod
                                    // peut n'avoir aucune page Nexus. Le
                                    // pourquoi est dit une fois, plus bas.
                                    Text(localization.L(L10n.Updates.updateAvailable))
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)
                                        .padding(.top, 2)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    Button(action: {
                                        if let url = URL(string: mod.url) { NSWorkspace.shared.open(url) }
                                    }) {
                                        // Il ouvre `smapi.io/mods#…`, où rien
                                        // ne se télécharge : promettre un
                                        // téléchargement était un faux départ.
                                        Text(localization.L(L10n.Updates.openSmapiPage))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 6)
                                            .background(Color.primary.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .pointingHandCursor()
                                }
                            }

                            VStack(alignment: .leading, spacing: 16) {
                                // Le texte d'avant — « apporte de nouvelles
                                // fonctionnalités et des corrections de bugs »
                                // — était inventé : l'app ne sait rien du
                                // contenu de la mise à jour. La phrase le dit
                                // maintenant, au lieu de le supposer.
                                Text(localization.L(L10n.Updates.smapiDescription))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 4) {
                                    Text(localization.L(L10n.Updates.visitWebsite))
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                    // Vrai lien cliquable plutôt qu'un Markdown
                                    // `[url](url)` interpolé que Text rendait en brut.
                                    if let url = URL(string: mod.url) {
                                        Link(url.absoluteString, destination: url)
                                            .font(.system(size: 13))
                                    }
                                }
                                .tint(.blue)
                            }
                            .padding(.top, 8)
                        }
                        .padding(20)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(12)
                    }
                }
                
                // ── Nexus Mods updates ─────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 16))
                        Text(localization.L(L10n.Updates.nexusSection))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                        if vm.isCheckingNexusUpdates {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                vm.checkNexusUpdates()
                            } label: {
                                Text(localization.L(L10n.Updates.nexusCheckButton))
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                    }

                    // Note, plus barrage : la vérification passe par smapi.io,
                    // sans clé ni quota. La clé ne manque qu'au téléchargement
                    // intégré. Tant que ce bloc était la première branche de la
                    // chaîne, il **remplaçait** la liste : sans compte Nexus,
                    // aucune mise à jour n'était visible, quand bien même
                    // l'app en avait trouvé.
                    if !vm.hasNexusApiKey {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "key.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(localization.L(L10n.Updates.nexusApiKeyMissing))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Button {
                                    if let url = URL(string: "https://www.nexusmods.com/users/myaccount?tab=api") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Text(localization.L(L10n.Updates.nexusGetKey))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
                        }
                    }

                    if vm.isCheckingNexusUpdates {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(localization.L(L10n.Updates.nexusChecking))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                if let prog = vm.nexusCheckProgress, prog.total > 0 {
                                    Spacer()
                                    Text("\(prog.done)/\(prog.total)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            // Determinate progress bar when we know the total.
                            if let prog = vm.nexusCheckProgress, prog.total > 0 {
                                let fraction = Double(prog.done) / Double(prog.total)
                                ProgressView(value: fraction)
                                    .progressViewStyle(.linear)
                                    .tint(.accentColor)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: vm.nexusCheckProgress?.done)
                    } else if let err = vm.nexusCheckError, vm.nexusUpdates.isEmpty {
                        // A partial run that still found updates falls
                        // through to the list below instead of here — an
                        // error banner must never hide real data that was
                        // actually gathered.
                        Text(err == "rate_limited"
                             ? localization.L(L10n.Updates.nexusRateLimited)
                             : localization.L(L10n.Updates.nexusError))
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                    } else if vm.nexusUpdates.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        // C'était `logs_system_alerts_section` — « Aucune
                        // alerte système » — sur la page des **mises à jour** :
                        // le libellé d'une autre page, qui répondait à côté de
                        // la question posée. Jumeau du défaut corrigé en
                        // v1.21.0 dans l'autre sens.
                        //
                        // Avec des invérifiables en suspens, « tous à jour »
                        // serait un quitus pour des mods sans verdict : le
                        // texte ne le dit plus, et le bloc sous la liste
                        // nomme les concernés.
                        Text(localization.L(vm.unverifiableMods.isEmpty
                                  ? L10n.Updates.allUpToDate
                                  : L10n.Updates.allVerifiedUpToDate))
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    } else {
                        // Summary line + list of available updates.
                        // Plus de note d'ordre : la liste est alphabétique,
                        // ce qui se voit. La note existait pour un tri par
                        // date de mise en ligne, qui lui ne se voyait pas —
                        // et que le passage à smapi.io avait de toute façon
                        // fait disparaître sans que la phrase suive.
                        Text(String(format: localization.L(L10n.Updates.nexusUpdatesCount),
                                    Int64(vm.nexusUpdates.count)))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        ForEach(vm.nexusUpdates) { update in
                            let isEnabled = vm.modForNexusUpdate(update)?.isEnabled ?? false
                            HStack(alignment: .top, spacing: 16) {
                                InitialsAvatar(
                                    text: update.name,
                                    initialsCount: 2,
                                    size: 44,
                                    fillColor: Color.accentColor.opacity(0.12),
                                    textColor: .accentColor,
                                    fontSize: 16
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(update.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Text(isEnabled ? localization.L(L10n.Updates.enabled) : localization.L(L10n.Updates.disabled))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(isEnabled ? AppDesign.Color.installed : .orange)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background((isEnabled ? AppDesign.Color.installed : Color.orange).opacity(0.12))
                                            .cornerRadius(4)
                                    }
                                    HStack(spacing: 12) {
                                        Label("\(localization.L(L10n.Updates.installedVersion)) \(update.installedVersion)",
                                              systemImage: "tag.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Label("\(localization.L(L10n.Updates.latestVersion)) \(update.latestVersion)",
                                              systemImage: "sparkles")
                                            .font(.system(size: 11))
                                            .foregroundColor(.green)
                                        if let uploaded = update.uploadedTime {
                                            Label(vm.formatUploadedDate(uploaded),
                                                  systemImage: "clock.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary.opacity(0.8))
                                        }
                                    }
                                }

                                Spacer()

                                if let nexusId = Int(update.nexusModId),
                                   vm.downloadingNexusModId == nexusId {
                                    // Le pourcentage à côté du témoin quand
                                    // la taille est connue : la ligne est le
                                    // seul endroit où l'on regarde après avoir
                                    // cliqué, et le pied de barre latérale
                                    // n'est pas toujours dans le champ.
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        if let percent = vm.nexusDownloadProgress?.displayPercent {
                                            Text("\(percent) %")
                                                .font(.system(size: 11).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        Button(action: { vm.cancelNexusDownload() }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 12))
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                        .pointingHandCursor()
                                        .help(localization.L(L10n.Downloads.cancel))
                                    }
                                    .help(localization.L(L10n.VM.nexusDlStarting).replacingOccurrences(of: "%lld", with: String(nexusId)))
                                } else {
                                    if let nexusId = Int(update.nexusModId) {
                                        Button {
                                            vm.downloadModFromNexus(nexusId: nexusId)
                                        } label: {
                                            Label(localization.L(L10n.Mods.premiumUpdate), systemImage: "arrow.down.circle")
                                        }
                                        .buttonStyle(.bordered)
                                        // Désactivé quand on **sait** que le
                                        // compte n'est pas premium : l'API
                                        // refuse alors tout lien direct
                                        // (`403 premium users only`), et
                                        // proposer le bouton revient à promettre
                                        // un échec. Le doute, lui, ne retire
                                        // rien.
                                        .disabled(vm.isDownloadingFromNexus || vm.nexusDirectDownloadUnavailable)
                                        .help(vm.nexusDirectDownloadUnavailable
                                              ? localization.L(L10n.Mods.premiumOnlyHint) : "")
                                    }

                                    Button {
                                        // Open the mod's Files tab directly, where the free
                                        // "Mod Manager Download" (nxm://) button lives.
                                        if var comps = URLComponents(string: update.url) {
                                            comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "tab", value: "files")]
                                            if let url = comps.url { NSWorkspace.shared.open(url) }
                                        }
                                    } label: {
                                        Text(localization.L(L10n.Mods.nexusUpdate))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(Color.primary.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .pointingHandCursor()
                                    .disabled(vm.isDownloadingFromNexus)

                                    // La seule sortie quand l'auteur a oublié
                                    // d'incrémenter son manifest : la
                                    // comparaison de chaînes réclamera cette
                                    // mise à jour à chaque passe, sinon.
                                    Button {
                                        vm.affirmInstalled(uniqueId: update.uniqueId,
                                                           version: update.latestVersion)
                                    } label: {
                                        Text(localization.L(L10n.Updates.nexusAlreadyHave))
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .pointingHandCursor()
                                    .help(localization.L(L10n.Updates.nexusAlreadyHaveHelp))

                                    // R3 — « je sais, pas maintenant ». Troisième
                                    // geste après mettre à jour et « je l'ai
                                    // déjà » : l'update est vraie mais pas
                                    // voulue tout de suite. La ligne disparaît
                                    // d'ici (et du badge), jamais de
                                    // l'inventaire, et revient toute seule
                                    // selon le mode choisi.
                                    Menu {
                                        Button {
                                            vm.snoozeUpdate(update, mode: .oneWeek)
                                        } label: {
                                            Label(localization.L(L10n.Updates.snoozeOneWeek),
                                                  systemImage: "clock")
                                        }
                                        Button {
                                            vm.snoozeUpdate(update, mode: .untilModVersion)
                                        } label: {
                                            Label(localization.L(L10n.Updates.snoozeUntilModVersion),
                                                  systemImage: "sparkles")
                                        }
                                        Button {
                                            vm.snoozeUpdate(update, mode: .untilGameVersion)
                                        } label: {
                                            Label(localization.L(L10n.Updates.snoozeUntilGameVersion),
                                                  systemImage: "gamecontroller")
                                        }
                                    } label: {
                                        Label(localization.L(L10n.Updates.snoozeButton),
                                              systemImage: "moon.zzz.fill")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(Color.primary.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                    .fixedSize()
                                    .pointingHandCursor()
                                    .disabled(vm.isDownloadingFromNexus)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(isEnabled ? Color.primary.opacity(0.04) : Color.orange.opacity(0.06))
                            .cornerRadius(10)
                        }
                    }

                    // Le silence sur ces mods est ce qui a rendu la fenêtre
                    // mensongère : « tous à jour » alors que certains n'avaient
                    // de verdict d'aucune source. Jusqu'à 115 mods du parc réel
                    // sont dans ce cas — d'où le repli : à plat, la liste
                    // noierait les mises à jour réelles au-dessus d'elle.
                    if !vm.unverifiableMods.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 3) {
                                // Indexé par `UniqueID` : deux mods peuvent
                                // porter le même nom, mais la réponse de
                                // smapi.io n'a qu'une entrée par identifiant.
                                // Indexer par rang ferait glisser les lignes
                                // quand la reprise Nexus en retire une.
                                ForEach(vm.unverifiableMods, id: \.uniqueId) { row in
                                    HStack(spacing: 6) {
                                        Text(row.name)
                                            .font(.system(size: 11, weight: .medium))
                                        Text(localization.L(row.blocker.labelKey))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 8)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        } label: {
                            Label(String(format: localization.L(L10n.Updates.unverifiableTitle),
                                         Int64(vm.unverifiableMods.count)),
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                    }

                    // X12 — ce que « Je l'ai déjà » a fait taire.
                    //
                    // **Hors de la chaîne `if/else` ci-dessus**, comme le bloc
                    // des invérifiables : c'est justement quand la page annonce
                    // « tous à jour » que ces mods doivent se voir. Sur
                    // l'installation de référence, 34 mods étaient éteints sans
                    // que rien ne le dise, et plusieurs par mégarde.
                    if !vm.affirmedUpdates.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                // L'explication d'abord : la liste seule ne dit
                                // ni ce que le geste a fait, ni ce qu'il coûte.
                                Text(localization.L(L10n.Updates.affirmedExplanation))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 2)

                                ForEach(vm.affirmedUpdates) { row in
                                    HStack(spacing: 8) {
                                        Text(row.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                        // Les deux versions côte à côte : le
                                        // numéro affirmé seul ne dit rien,
                                        // c'est l'écart avec le disque qui
                                        // trahit le clic malheureux.
                                        Text(String(format: localization.L(L10n.Updates.affirmedVersion),
                                                    row.affirmedVersion))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        Text(String(format: localization.L(L10n.Updates.affirmedOnDisk),
                                                    row.manifestVersion))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(row.disagreesWithDisk
                                                             ? .orange : .secondary)
                                        Spacer(minLength: 8)
                                        // Voir la fiche avant de décider :
                                        // c'est là que se lisent la version,
                                        // la compatibilité et l'historique du
                                        // mod. On pose la cible PUIS on
                                        // bascule — `MainView` remet à `nil`
                                        // les états de détail dans son
                                        // `onChange(of: currentTab)`, et
                                        // `pendingModDetailFocus` est ce qui
                                        // traverse (patron B3-T4).
                                        //
                                        // Le **dossier**, pas le nom : le
                                        // résolveur le cherche en premier, et
                                        // deux mods homonymes ouvriraient la
                                        // fiche du premier venu.
                                        Button {
                                            vm.pendingModDetailFocus = row.folderName
                                            vm.pendingDetailTab = .state
                                            currentTab = .mods
                                        } label: {
                                            Text(localization.L(L10n.Updates.affirmedOpenMod))
                                                .font(.system(size: 11))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .pointingHandCursor()
                                        .help(localization.L(L10n.Updates.affirmedOpenModHelp))
                                        Button {
                                            vm.revealAffirmedUpdate(uniqueId: row.uniqueId)
                                        } label: {
                                            Text(localization.L(L10n.Updates.affirmedReveal))
                                                .font(.system(size: 11))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .pointingHandCursor()
                                        .help(localization.L(L10n.Updates.affirmedRevealHelp))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        } label: {
                            Label(String(format: localization.L(L10n.Updates.affirmedTitle),
                                         Int64(vm.affirmedUpdates.count)),
                                  systemImage: "eye.slash")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // R3 — ce que « Mettre en veille » a endormi. Même
                    // patron que les deux replis ci-dessus, et pour la même
                    // raison : la liste doit rester trouvable et réversible —
                    // snoozer ne doit jamais ressembler à perdre une
                    // information. Contrairement à « je l'ai déjà », rien
                    // n'est affirmé ici : tout revient tout seul.
                    if !vm.snoozedUpdates.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(localization.L(L10n.Updates.snoozedExplanation))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 2)
                                ForEach(vm.snoozedUpdates) { row in
                                    HStack(spacing: 8) {
                                        Text(row.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                        Text(vm.snoozeExpiryLabel(for: row))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 8)
                                        Button {
                                            vm.unsnoozeUpdate(uniqueId: row.uniqueId)
                                        } label: {
                                            Text(localization.L(L10n.Updates.snoozedWake))
                                                .font(.system(size: 11))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .pointingHandCursor()
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        } label: {
                            Label(String(format: localization.L(L10n.Updates.snoozedTitle),
                                         Int64(vm.snoozedUpdates.count)),
                                  systemImage: "moon.zzz.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)

            }
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        // Le scan de lancement remplit déjà la liste ; ce rappel couvre
        // l'ouverture de l'onglet avant qu'il n'ait rendu la main, et le
        // retour sur l'onglet après une affirmation faite ailleurs.
        .onAppear { vm.refreshAffirmedUpdates() }
    }
}

// MARK: - Poids du parc (B2-T2)

/// Ce que pèsent les mods, en pied de barre latérale.
///
/// Mesuré sur le parc réel le 2026-08-24 : **16,84 Go de mods, dont 12,71 Go
/// en pause** — 746 dossiers sur 863 — pour 30 Go libres. C'est ce rapport-là
/// que la barre montre, et c'est pour lui qu'elle existe : le total seul ne
/// dit pas que les trois quarts de la place sont immobilisés par des mods
/// désactivés, alors qu'une barre coupée aux trois quarts le dit sans qu'on
/// lise un chiffre.
///
/// **La barre ne compte que les mods** (100 % = le total mesuré), partagée
/// entre actifs et en pause. La place libre reste du texte : `mods + libre`
/// ne forme pas un tout — il y a ~450 Go d'autre chose sur ce volume — et un
/// troisième segment énoncerait une proportion fausse.
///
/// Ses deux couleurs sont celles des barres d'accent de la liste des mods
/// (vert pour un mod actif, gris pour un mod en pause) : le pied de barre
/// résume la liste, il doit en parler la langue.
///
/// Rien ne s'affiche tant qu'aucun jeu n'est désigné : « 0 octet » serait faux.
/// Le téléchargement Nexus en cours, en pied de barre latérale (B2-T1).
///
/// Ce qu'il remplace : un `ProgressView()` indéterminé sur une seule ligne de
/// la page des mises à jour. Un mod de 500 Mo se téléchargeait donc en
/// silence, sans qu'on sache s'il avançait, ni combien de temps il restait, ni
/// comment l'arrêter — et le lien `nxm://` d'un compte gratuit peut arriver
/// alors que n'importe quel onglet est ouvert.
///
/// **Sans taille annoncée, il ne ment pas.** Le CDN de Nexus n'annonce pas
/// toujours `Content-Length` : la barre disparaît alors, et il ne reste que le
/// volume reçu et le débit. Une barre figée à 0 % ferait croire à un blocage.
/// Volet de téléchargement Nexus, en bas de la barre latérale : une fenêtre
/// temporaire qui ne vit que le temps d'un téléchargement (`isDownloadingFromNexus`).
/// Le contenu — mod visé, annulation, progression, débit — reste identique ;
/// seul l'habillage en fait un volet flottant plutôt qu'une ligne du pied.
struct NexusDownloadFooter: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        panel
            // Le glissement est piloté côté vue : le VM se contente de muter
            // l'état à ses deux bascules (démarrage, complétion) ; animer ici
            // n'exige aucune transaction dans le ViewModel.
            .animation(.spring(response: 0.3, dampingFraction: 0.85),
                       value: vm.isDownloadingFromNexus)
    }

    /// Volet posé seulement pendant un téléchargement : glisse depuis le bord
    /// bas de la colonne, repart en sens inverse à la complétion.
    @ViewBuilder private var panel: some View {
        if vm.isDownloadingFromNexus {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 9))
                    Text(headline)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    // Le bouton existe **dès** la demande, avant même que le
                    // lien ne soit résolu : c'est le moment où l'on se rend
                    // compte qu'on s'est trompé de mod.
                    Button(action: { vm.cancelNexusDownload() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .pointingHandCursor()
                    .help(localization.L(L10n.Downloads.cancel))
                }
                .foregroundStyle(.secondary)

                if let fraction = vm.nexusDownloadProgress?.fractionCompleted {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }

                Text(detail)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: AppDesign.Radius.md,
                                             style: .continuous))
            .shadow(color: .black.opacity(0.12),
                    radius: AppDesign.Shadow.badge.radius,
                    y: AppDesign.Shadow.badge.y)
            // Fenêtre temporaire : entrée et sortie glissées, pas une ligne
            // de plus dans le pied.
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    /// Le mod visé, dès qu'on le connaît — **par son nom** quand l'app le
    /// connaît, faute de quoi la barre latérale n'annonçait qu'un numéro.
    private var headline: String {
        guard let modId = vm.downloadingNexusModId else {
            return localization.L(L10n.Downloads.connecting)
        }
        if let name = vm.nexusModDisplayName(for: modId) {
            return String(format: localization.L(L10n.Downloads.downloadingNamed), name)
        }
        return String(format: localization.L(L10n.Downloads.downloading), Int64(modId))
    }

    /// Volume, débit et temps restant — chacun seulement s'il est mesuré.
    /// Aucune valeur inventée : pas de « 0 o/s » au démarrage, pas d'ETA sans
    /// débit.
    private var detail: String {
        guard let progress = vm.nexusDownloadProgress else {
            return localization.L(L10n.Downloads.connecting)
        }
        var parts: [String] = []
        if let total = progress.totalBytes {
            parts.append(String(format: localization.L(L10n.Downloads.progress),
                                Self.bytes(progress.bytesReceived), Self.bytes(total)))
        } else {
            parts.append(String(format: localization.L(L10n.Downloads.progressUnknownTotal),
                                Self.bytes(progress.bytesReceived)))
        }
        if let rate = progress.bytesPerSecond {
            parts.append(String(format: localization.L(L10n.Downloads.rate), Self.bytes(Int64(rate))))
        }
        if let remaining = progress.estimatedTimeRemaining, remaining > 0 {
            parts.append(String(format: localization.L(L10n.Downloads.eta), Self.duration(remaining)))
        }
        return parts.joined(separator: " · ")
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// Une durée courte et lisible : « 45 s », « 2 min ». Le formateur du
    /// système localise les unités, ce qu'une concaténation à la main ne ferait
    /// pas.
    private static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds < 60 ? [.second] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }
}

struct ModsWeightFooter: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    /// Reprises telles quelles de `ModListRow` : la barre d'accent verte d'un
    /// mod actif, le gris d'un mod en pause.
    private static let activeColor = Color(red: 0.20, green: 0.65, blue: 0.35)
    private static let pausedColor = Color.secondary.opacity(AppDesign.Opacity.strong)

    var body: some View {
        if let sizes = vm.modsFolderSizes {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(String(format: localization.L(L10n.Main.sidebarModsWeight),
                                Self.bytes(sizes.totalBytes)))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    if vm.isMeasuringModsFolder {
                        ProgressView().controlSize(.mini).scaleEffect(0.6)
                    }
                }

                // Sans mod en pause, il n'y a pas de partage à montrer : la
                // barre serait d'une seule couleur et sa légende d'un seul
                // point, soit une décoration. Le total et la place libre disent
                // alors tout.
                //
                // Un parc vide, lui, n'a pas de proportion du tout — et le
                // rapport vaudrait une division par zéro, qui donne une largeur
                // `NaN` : une erreur d'exécution SwiftUI, pas une barre plate.
                if sizes.totalBytes > 0, sizes.pausedBytes > 0 {
                    weightBar(sizes)
                    legend(sizes)
                }

                if let free = sizes.availableBytes {
                    Text(String(format: localization.L(L10n.Main.sidebarDiskFree), Self.bytes(free)))
                        .font(.system(size: 9).monospacedDigit())
                        // Orange quand il reste moins que ce que pèsent déjà
                        // les mods : le prochain gros mod ne rentrera pas.
                        .foregroundStyle(free < sizes.totalBytes ? Color.orange : Color.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.a11yLabel(sizes, vm: vm))
        } else if vm.isMeasuringModsFolder {
            // Sans cet état, le pied reste vide plusieurs secondes au
            // lancement — de trois à six secondes de traversée sur 100 000
            // fichiers — et le vide se lit comme un défaut.
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
                Text(localization.L(L10n.Main.sidebarModsWeightMeasuring))
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// La part active posée sur toute la largeur, qui porte la part en pause.
    ///
    /// `GeometryReader` sous une hauteur **explicite** : laissé libre dans la
    /// pile de la barre latérale, il réclamerait toute la hauteur restante et
    /// pousserait les boutons de thème et de langue hors de l'écran.
    private func weightBar(_ sizes: ModsFolderSizes) -> some View {
        let active = Double(sizes.totalBytes - sizes.pausedBytes) / Double(sizes.totalBytes)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Self.pausedColor)
                Capsule()
                    .fill(Self.activeColor)
                    // Un filet minimal : une part active infime doit rester
                    // visible, sinon la barre laisse croire qu'il n'y a rien
                    // d'actif du tout.
                    .frame(width: max(active > 0 ? 2 : 0, geo.size.width * active))
            }
        }
        .frame(height: 5)
    }

    /// « 4,1 Go actifs · 12,7 Go en pause », chaque part sous sa couleur.
    private func legend(_ sizes: ModsFolderSizes) -> some View {
        HStack(spacing: 5) {
            dot(Self.activeColor)
            Text(String(format: localization.L(L10n.Main.sidebarModsWeightActive),
                        Self.bytes(sizes.totalBytes - sizes.pausedBytes)))
            dot(Self.pausedColor)
            Text(String(format: localization.L(L10n.Main.sidebarModsWeightAsleep),
                        Self.bytes(sizes.pausedBytes)))
        }
        .font(.system(size: 9).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 5, height: 5)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// Une barre ne se lit pas à voix haute : le lecteur d'écran reçoit les
    /// mêmes chiffres que les lignes de texte.
    static func a11yLabel(_ sizes: ModsFolderSizes, vm: StarHubTHViewModel) -> String {
        let label = String(format: vm.localization.L(L10n.Main.sidebarModsWeightA11y),
                           bytes(sizes.totalBytes),
                           bytes(sizes.totalBytes - sizes.pausedBytes),
                           bytes(sizes.pausedBytes),
                           sizes.availableBytes.map { bytes($0) } ?? "—")
        // `children: .ignore` remplace tout ce que contient le pied de barre,
        // y compris l'indicateur de mesure en cours. Sans cet ajout, un lecteur
        // d'écran recevrait des chiffres périmés pendant les secondes qui
        // suivent chaque bascule, sans rien pour le dire.
        guard vm.isMeasuringModsFolder else { return label }
        return label + " " + vm.localization.L(L10n.Main.sidebarModsWeightMeasuring)
    }
}
