import SwiftUI

// MARK: - Sidebar Nav Groups

/// Les quatre groupes d'entrées de la barre latérale — Bibliothèque, Parties,
/// Santé & secours, Application. Extrait du corps de `MainView` (densité) et
/// posé dans le `ScrollView` de la colonne : en fenêtre basse, ce sont ces
/// lignes qui défilent, pas les réglages du bas.
struct SidebarNavGroups: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination

    /// Le badge d'une destination — donnée **vivante** du ViewModel, pas de
    /// `SidebarOrder` : il change à chaque scan. `nil` quand l'entrée ne
    /// compte rien.
    private func badge(_ d: SidebarDestination) -> (count: Int, color: Color)? {
        switch d {
        case .updates:
            return (UpdateCount.pending(outOfDate: vm.outOfDateMods,
                                        nexusCount: vm.nexusUpdates.count) {
                vm.resolveModFolder(forLoggedName: $0)?.version
            }, .blue)
        case .systemAlerts:
            return (vm.systemAlertCount, .orange)
        case .quarantine:
            return (vm.maintenanceStore.quarantineItemCount, .purple)
        case .home, .mods, .discover, .frenchTranslations, .profiles, .saves,
             .backups, .maintenance, .logs, .settings,
             .appChangelog:
            return nil
        }
    }

    private func group(_ g: SidebarGroup, header: String,
                       icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarSectionHeader(title: header, icon: icon)
            ForEach(SidebarOrder.entries(in: g)) { e in
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

    /// Reprises telles quelles de `ModListRow` (`Views/ModListRow.swift`) : la barre d'accent verte d'un
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
