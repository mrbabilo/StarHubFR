import SwiftUI

struct HomeView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @ObservedObject var smapiInstaller: SmapiInstaller
    @ObservedObject private var bisection: BisectionRunner
    // Observé séparément, comme `smapiInstaller`/`bisection` juste au-dessus :
    // `report` est publié par `KeybindScanService`, un `ObservableObject`
    // distinct de `vm` — sans cet abonnement, la bande d'attention ne se
    // redessinerait jamais quand le scan de raccourcis termine (tâche 7).
    @ObservedObject private var keybindScanService: KeybindScanService
    /// L'onglet courant de `MainView` : les compteurs de la bande mènent
    /// chacun à sa page, et un accueil qui les affiche sans y conduire ne
    /// ferait que constater.
    @Binding var currentTab: String

    // Mirrors the key launchGame() reads, so the subtitle reflects the mode that fires.
    @AppStorage("launchProfile") private var launchProfile: String = "SMAPI"

    init(vm: StarHubTHViewModel, currentTab: Binding<String>) {
        self.vm = vm
        self.smapiInstaller = vm.smapiInstaller
        self.bisection = vm.bisection
        self.keybindScanService = vm.keybindScanService
        self._currentTab = currentTab
    }

    /// Une recherche laissée en plan a laissé des mods en pause. C'est détecté
    /// au démarrage, mais la carte du Diagnostic ne vit que dans l'onglet
    /// Journaux : sans ce rappel, l'utilisateur retrouve une liste à moitié en
    /// pause sans que rien, nulle part, ne dise qu'un clic la remet en état.
    /// L'accueil est l'écran d'arrivée : c'est là que ça doit se voir.
    @ViewBuilder
    private var interruptedSearchNotice: some View {
        if let snapshot = bisection.interruptedSnapshot, bisection.state == nil {
            StandardSection(title: vm.L(L10n.Bisect.interruptedTitle)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(String(format: vm.L(L10n.Bisect.interruptedBody),
                                    DateFormatter.localizedString(from: snapshot.startedAt,
                                                                  dateStyle: .short,
                                                                  timeStyle: .short)))
                            .font(AppDesign.Font.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(vm.L(L10n.Bisect.restore)) { bisection.restoreAndStop() }
                        .buttonStyle(.borderedProminent)
                        .disabled(bisection.isApplying)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
        }
    }

    /// Les quatre chiffres qui décident de la suite. Toujours les quatre,
    /// zéros compris : un « 0 alerte » se lit, une absence ne se lit pas.
    private var attentionStrip: some View {
        // Les conflits de raccourcis se fondent dans ce compteur existant
        // plutôt que d'en créer un cinquième (brief tâche 7) : `HomeAttention`
        // résout un niveau à partir d'un compte qu'on lui donne, il ne décide
        // pas de ce qui compose « alertes » — c'est déjà le rôle de cet
        // appelant, par `vm.systemAlertCount`.
        let counters = HomeAttention.counters(
            updates: vm.outOfDateMods.count + vm.nexusUpdates.count,
            alerts: vm.systemAlertCount,
            quarantined: vm.lastRepairReport?.quarantined.count ?? 0,
            mods: vm.mods.count)
        return HStack(spacing: AppDesign.Spacing.md) {
            ForEach(counters) { counter in
                AttentionCounterTile(
                    glyph: glyph(for: counter.kind),
                    value: counter.count,
                    label: label(for: counter.kind),
                    tint: counter.level == .attention ? tint(for: counter.kind) : nil,
                    tab: counter.tab,
                    currentTab: $currentTab)
            }
        }
    }

    /// Le symbole de l'item de barre latérale (tâche 2) : même glyphe aux
    /// deux endroits pour la même destination.
    private func glyph(for kind: HomeAttention.Kind) -> String {
        switch kind {
        case .updates: return "arrow.triangle.2.circlepath"
        case .alerts: return "exclamationmark.triangle.fill"
        case .quarantine: return "tray.full.fill"
        case .library: return "puzzlepiece.extension.fill"
        }
    }

    /// La `badgeColor` de l'item de barre latérale (tâche 2). `.library` n'en
    /// a pas — ce n'est pas un item badgé — mais sa teinte n'est de toute
    /// façon jamais lue : `counter.level` du parc n'atteint jamais `.attention`.
    private func tint(for kind: HomeAttention.Kind) -> Color {
        switch kind {
        case .updates: return .blue
        case .alerts: return .orange
        case .quarantine: return .purple
        case .library: return .secondary
        }
    }

    private func label(for kind: HomeAttention.Kind) -> String {
        switch kind {
        case .updates: return vm.L(L10n.Main.modUpdates)
        case .alerts: return vm.L(L10n.Main.systemAlerts)
        case .quarantine: return vm.L(L10n.Main.quarantine)
        case .library: return vm.L(L10n.Mods.mods)
        }
    }

    /// La carte de lancement — ou l'état qui l'empêche, avec l'action qui le
    /// lève plutôt qu'un bouton grisé et muet (spec refonte §2, P1).
    @ViewBuilder private var launchCard: some View {
        switch HomeLaunchState.resolve(gameDirIsEmpty: vm.gameDir.isEmpty,
                                       smapiInstalled: vm.smapiInstalledVersion != nil,
                                       profileIsVanilla: launchProfile == "Vanilla") {
        case .needsGameFolder:
            // Un bouton « Jouer » grisé ne dit pas quoi faire ; la carte
            // d'état porte l'action qui lève l'empêchement.
            StateCard(icon: "folder.badge.questionmark",
                      text: vm.L(L10n.Home.notSet),
                      actionTitle: vm.L(L10n.Home.selectFolder)) { vm.selectGameDir() }
        case .needsSmapi:
            // SMAPI reste installable **d'ici** : c'est le prérequis de tout
            // le reste. La progression l'accompagne, sinon l'installation se
            // fait sans témoin.
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                StateCard(icon: "shippingbox",
                          text: vm.L(L10n.Home.smapiNotInstalled),
                          actionTitle: smapiInstaller.isInstalling
                              ? nil : vm.L(L10n.Home.installSmapi)) { vm.installSmapi() }
                if smapiInstaller.isInstalling {
                    ProgressView(value: smapiInstaller.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .animation(.easeInOut, value: smapiInstaller.progress)
                    Text(vm.L(smapiInstaller.statusMessage))
                        .font(AppDesign.Font.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .ready(let mode):
            readyCard(mode)
        }
    }

    /// Le bouton de lancement existant, avec le profil actif et le dossier du
    /// jeu en une ligne de méta — d'un coup d'œil (spec refonte §5).
    private func readyCard(_ mode: HomeLaunchMode) -> some View {
        VStack(spacing: AppDesign.Spacing.sm) {
            Button(action: { vm.launchGame() }) {
                Label(vm.L(L10n.Main.launchGame), systemImage: "play.fill")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)

            HStack(spacing: AppDesign.Spacing.xs) {
                Text(mode == .vanilla ? vm.L(L10n.Settings.vanillaGame) : vm.L(L10n.Settings.playSMAPI))
                Text("•").foregroundStyle(.secondary.opacity(0.5))
                Text(vm.gameDir)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(AppDesign.Font.footnote)
            .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .center, spacing: 24) {

                // ── RECHERCHE INTERROMPUE ──
                // (Le rembourrage vit dans la branche : appliqué ici, il
                // envelopperait l'`EmptyView` du cas courant et laisserait un
                // blanc en haut de l'accueil quand il n'y a rien à signaler.)
                interruptedSearchNotice

                // ── ATTENTION STRIP ──
                attentionStrip
                    .padding(.horizontal, 40)
                    .padding(.top, 28)

                // ── LAUNCH CARD ──
                launchCard
                    .padding(.horizontal, 40)

                // ── GAME INFO BLOCK ──
                StandardSection(title: vm.L(L10n.Home.appInfo)) {
                    StandardRow(title: LocalizedStringKey(vm.L(L10n.Home.developer)), detail: "AppleBoiy (original) · mrbabilo (fork)", showDivider: true)
                    StandardRow(
                        title: LocalizedStringKey(vm.L(L10n.Home.modManager)),
                        detail: LocalizedStringKey(vm.smapiInstalledVersion == nil
                            ? vm.L(L10n.Home.notInstalled)
                            : "SMAPI \(vm.smapiInstalledVersion!)"),
                        showDivider: true
                    )
                    StandardRow(
                        title: LocalizedStringKey(vm.L(L10n.Home.installedMods)),
                        detail: LocalizedStringKey(String(format: vm.L(L10n.Home.itemCount), Int64(vm.mods.count))),
                        showDivider: false
                    )
                }
                .padding(.horizontal, 40)

                // ── CORE EXTENSIONS SECTION ──
                StandardSection(title: vm.L(L10n.Home.coreExtensions)) {
                    VStack(spacing: 0) {
                        let core = vm.coreExtensionsSnapshot
                        CoreModRow(vm: vm, title: "Content Patcher", status: core.contentPatcher.status, mod: core.contentPatcher.mod)
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                        CoreModRow(vm: vm, title: "SpaceCore", status: core.spacecore.status, mod: core.spacecore.mod)
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                        CoreModRow(vm: vm, title: "Stardew Valley Thai", status: core.thai.status, mod: core.thai.mod)
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                        CoreModRow(vm: vm, title: "Stardew Valley Expanded", status: core.sve.status, mod: core.sve.mod)
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                        CoreToolRow(
                            title: vm.L(L10n.Home.toolUnar),
                            status: core.unarTool.installed ? .enabledAndInstalled : .notInstalled,
                            tooltip: vm.L(L10n.Home.toolUnarTooltip),
                            installCommand: "brew install unar"
                        )
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                        CoreToolRow(
                            title: vm.L(L10n.Home.toolSevenZip),
                            status: core.sevenZipTool.installed ? .enabledAndInstalled : .notInstalled,
                            tooltip: vm.L(L10n.Home.toolSevenZipTooltip),
                            installCommand: "brew install sevenzip"
                        )
                    }
                    .padding(.vertical, -8)
                }
                .padding(.horizontal, 40)
                
                Spacer(minLength: 40)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { vm.refresh() }
    }
}

// MARK: - Bande d'attention

/// Un carré de la bande d'attention : son glyphe, son chiffre, son libellé,
/// sa destination. Sorti du `ForEach` de `attentionStrip` (ronde finale de
/// revue) : le corps en une seule expression — un `Button` enveloppant un
/// `VStack` de deux `Text` et d'un `Image`, cinq modificateurs, une
/// condition dans le `foregroundStyle` — finissait par faire trébucher le
/// vérificateur de types (« unable to type-check this expression in
/// reasonable time »). `tint` à `nil` pour le carré neutre : le glyphe
/// repasse en `Color.secondary`.
private struct AttentionCounterTile: View {
    let glyph: String
    let value: Int
    let label: String
    let tint: Color?
    let tab: String
    @Binding var currentTab: String

    var body: some View {
        Button { currentTab = tab } label: {
            VStack(spacing: AppDesign.Spacing.xs) {
                Image(systemName: glyph)
                    .font(.system(size: AppDesign.Icon.md))
                    .foregroundStyle(tint ?? Color.secondary)
                Text("\(value)")
                    .font(AppDesign.Font.viewTitle)
                Text(label)
                    .font(AppDesign.Font.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppDesign.Spacing.md)
            .background(.background.secondary,
                        in: RoundedRectangle(cornerRadius: AppDesign.Radius.section))
            .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.section)
                .stroke(Color.primary.opacity(AppDesign.Opacity.light), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Core Mod Status

struct CoreExtensionsSnapshot {
    let contentPatcher: CoreModSlot
    let spacecore: CoreModSlot
    let thai: CoreModSlot
    let sve: CoreModSlot
    let unarTool: CoreToolSlot
    let sevenZipTool: CoreToolSlot
}

struct CoreToolSlot {
    let installed: Bool
}

// Helper for core mod status rows
struct CoreModRow: View {
    @ObservedObject var vm: StarHubTHViewModel
    let title: String
    let status: CoreModStatus
    let mod: ModItem?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppDesign.Font.body)

                // Author + version when installed, otherwise status text
                if let mod = mod {
                    HStack(spacing: 4) {
                        if !mod.author.isEmpty {
                            Text(mod.author)
                                .foregroundColor(.secondary)
                        }
                        if !mod.author.isEmpty && !mod.version.isEmpty {
                            Text("•").foregroundColor(.secondary.opacity(0.5))
                        }
                        if !mod.version.isEmpty {
                            Text("v\(mod.version)")
                                .foregroundColor(.secondary)
                                .fontDesign(.monospaced)
                        }
                    }
                    .font(AppDesign.Font.footnote)

                    // Status label below author/version
                    Group {
                        switch status {
                        case .enabledAndInstalled:
                            Text(vm.L(L10n.Home.installedAndEnabled))
                                .foregroundColor(.secondary)
                        case .installedButDisabled:
                            Text(vm.L(L10n.Home.installedButDisabled))
                                .foregroundColor(.orange)
                        case .notInstalled:
                            EmptyView()
                        }
                    }
                    .font(AppDesign.Font.footnote)
                } else {
                    Text(vm.L(L10n.Home.notInstalledOrDisabled))
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.red)
                }
            }
            Spacer()
            switch status {
            case .enabledAndInstalled:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .installedButDisabled:
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.orange)
            case .notInstalled:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

// Row for a non-mod tool status (e.g. unar)
struct CoreToolRow: View {
    let title: String
    let status: CoreModStatus
    let tooltip: String
    /// Commande à taper quand l'outil manque. Paramétrée : la ligne servait
    /// jusqu'ici au seul `unar` et l'affichait en dur.
    let installCommand: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppDesign.Font.body)
                Group {
                    switch status {
                    case .enabledAndInstalled:
                        Text("")
                    case .installedButDisabled:
                        Text("")
                    case .notInstalled:
                        Text(installCommand)
                            .font(AppDesign.Font.iconXS)
                            .foregroundColor(.secondary)
                    }
                }
                .font(AppDesign.Font.footnote)
            }
            Spacer()
            switch status {
            case .enabledAndInstalled:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .installedButDisabled:
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.orange)
            case .notInstalled:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .help(tooltip)
    }
}
