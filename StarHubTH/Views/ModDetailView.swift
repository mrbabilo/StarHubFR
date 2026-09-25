import SwiftUI

/// Rich detail pane: header, settings (category + Nexus id), and content
/// tabs rendering `loadModDetail(for:)`'s blocks. Detail column of the
/// split view (`navigationStore.viewingModDetail`), never a sheet.
/// `MainView` applies `.id(mod.folderName)`: a fresh instance per mod, so
/// tab and drafts never leak onto another mod.
struct ModDetailView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem
    /// Rapport de raccourcis publié en asynchrone par un `let` du VM : sans
    /// observation ici, une fiche ouverte avant le premier scan resterait
    /// muette. Patron de `HomeView`/`MainView`.
    @ObservedObject private var keybindScanService: KeybindScanService

    init(vm: StarHubTHViewModel, localization: LocalizationStore, mod: ModItem) {
        self.localization = localization
        self.vm = vm
        self.mod = mod
        self.keybindScanService = vm.keybindScanService
    }

    @State private var selectedTab: DetailTab = .description
    /// Activation en attente : smapi.io signale le mod cassé
    /// (`CompatibilityWarning`).
    @State private var pendingActivation: ModItem?
    /// Même rôle pour un conflit avec un mod actif (`ConflictActivationGate`).
    @State private var pendingConflict: ConflictActivation?
    /// Sélecteur « Signaler une incompatibilité… », ciblé par `folderName`
    /// (`Picker` exige `Hashable`, qu'`ModItem` ne porte pas).
    @State private var showReportConflict = false
    @State private var reportConflictTargetFolder: String?
    @State private var reportConflictNote: String = ""

    /// Nexus id draft, seeded in `.onAppear` without guard (fresh `@State`
    /// per mod via `.id`).
    @State private var nexusIdDraft: String = ""
    /// B3-T6 — brouillon de note, même patron (pas de fuite entre mods).
    @State private var noteDraft: String = ""
    @FocusState private var noteFocused: Bool

    /// On-demand metadata fetch status after saving a Nexus id.
    @State private var fetchStatus: FetchStatus = .idle

    @State private var showDeleteConfirm = false

    /// Traduction FR retrouvée dans une sauvegarde (mod qui n'en a plus),
    /// cherchée hors main.
    @State private var backupTranslation: TranslationBackupFinder.Found?

    /// Anglais touché après le français ? Mesuré hors main.
    @State private var translationStaleness: TranslationFreshness.Staleness?

    /// Fichiers de traduction jamais ouverts par le jeu (`pt-BR.json` sans
    /// `pt.json`), cherchés hors main.
    @State private var unloadableLocaleFiles: [I18nLocaleResolver.UnloadableLocaleFile] = []

    /// Mémorisé par les profils ; rempli à l'apparition et après chaque geste,
    /// jamais au rendu.
    @State private var configHolders: [(profileName: String, capturedAt: Date,
                                        bytes: Int, matchesDisk: Bool)] = []

    /// Profil B de la comparaison (A = l'actif).
    @State private var compareProfile: ModProfile?

    enum FetchStatus: Equatable {
        case idle
        case loading
        case success(categoryName: String?, latestVersion: String?)
        case noApiKey
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hero, état (I-T14), mise à jour (I-T13), onglets épinglés ; le contenu défile.
            heroBanner
            if selectedTab != .state, let anomaly = vm.anomaly(for: live) {
                ModAnomalyBanner(anomaly: anomaly, vm: vm, localization: localization) { selectedTab = .state }
            }
            if let pending = PendingModUpdates.current(vm).pending(for: live) { ModUpdateBanner(pending: pending, vm: vm, localization: localization) }
            tabBar
            ScrollView {
                content
                    .frame(maxWidth: 700, alignment: .leading)
                    .padding(AppDesign.Spacing.xl)
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            seedDraft()
            noteDraft = vm.modNote(for: mod) ?? ""
            refreshConfigHolders()
        }
        .sheet(item: $compareProfile) { profile in
            ProfileConfigCompareView(vm: vm, localization: localization, mod: live, other: profile,
                                     isPresented: Binding(
                                        get: { compareProfile != nil },
                                        set: { if !$0 { compareProfile = nil } }))
        }
        // La pause renomme le dossier (`live`, pas `mod` : copie figée qui ne
        // déclencherait jamais cet `onChange`).
        .onChange(of: live.isEnabled) { _, _ in
            refreshConfigHolders()
        }
        // B3-T6 — note sauvegardée au blur : pas un formulaire, pas de bouton.
        .onChange(of: noteFocused) { _, focused in
            if !focused { vm.setModNote(noteDraft, for: mod) }
        }
        // …et à la sortie : remplacée par `.id` avant le blur. Idempotent.
        .onDisappear {
            vm.setModNote(noteDraft, for: mod)
        }
        .compatibilityGate(vm: vm, pending: $pendingActivation) { target in
            vm.toggleMod(target)
        }
        .conflictActivationGate(vm: vm, pending: $pendingConflict) { target in
            vm.toggleMod(target)
        }
        // Confirmation de suppression (le geste est dans la barre).
        .confirmationDialog(
            String(format: localization.L(L10n.Mods.deleteConfirmTitle), mod.name),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(localization.L(L10n.Mods.deleteMod), role: .destructive) {
                vm.deleteMod(mod)
                // Mod supprimé : refermer la fiche.
                vm.navigationStore.setViewingModDetail(nil)
            }
            Button(localization.L(L10n.Saves.cancel), role: .cancel) { }
        } message: {
            Text(mod.isGroup
                 ? localization.L(L10n.Mods.deleteConfirmPack)
                 : localization.L(L10n.Mods.deleteConfirmMessage))
        }
        // Chevrons dans la zone de navigation ; SwiftUI fusionne les ToolbarItems.
        .toolbar {
            ToolbarItem(placement: .navigation) {
                pagerControls
            }
        }
        .sheet(isPresented: $showReportConflict) {
            reportConflictSheet
        }
        .task {
            // Onglet demandé par l'appelant (couverture FR d'un profil, alertes) :
            // consommé sans condition et effacé aussitôt, pour que la fiche suivante
            // s'ouvre normalement.
            if let tab = vm.navigationStore.pendingDetailTab {
                vm.navigationStore.pendingDetailTab = nil
                selectedTab = tab
            }
            if vm.navigationStore.pendingTranslationFocus == mod.folderName {
                vm.navigationStore.pendingTranslationFocus = nil
                if mod.languages.contains("fr") || mod.languages.contains("en") {
                    selectedTab = .translation
                }
            }
            translationStaleness = await vm.translationStaleness(for: mod)
            unloadableLocaleFiles = await vm.unloadableLocaleFiles(for: mod)
            // Seulement si rien de FR : sinon inutile de fouiller.
            guard !mod.languages.contains("fr") else { return }
            backupTranslation = await vm.backupTranslation(for: mod)
        }
    }

    /// Content tab switcher, pinned under the hero.
    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            Text(localization.L(L10n.Mods.detailDescription)).tag(DetailTab.description)
            Text(localization.L(L10n.Mods.detailChangelog)).tag(DetailTab.changelog)
            Text("\(localization.L(L10n.Profiles.dependencies)) (\(dependencyCount))")
                .tag(DetailTab.dependencies)
            // État du mod groupé dans son onglet.
            Text(localization.L(L10n.Mods.tabState)).tag(DetailTab.state)
            // Onglet plutôt que feuille. `en` autant que `fr` : un mod à
            // `default.json` seul est celui qui reste à traduire
            // (`languageCodes` rend `default` sous la forme `en`).
            if mod.languages.contains("fr") || mod.languages.contains("en") {
                Text(localization.L(L10n.Mods.diffTab)).tag(DetailTab.translation)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 700)
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: Hero (bandeau image) + bande fine + chiffres clés — le motif
    // Découvrir, tenu par les composants partagés.

    private var heroBanner: some View {
        VStack(spacing: 0) {
            HeroHeader(title: mod.name,
                       subtitle: heroSubtitle,
                       imageURL: heroPictureURL) {
                vm.navigationStore.setViewingModDetail(nil)
            }
            fineBand
            statStrip
            if isTopLevel {
                ModDetailActionBar(
                    vm: vm,
                    localization: localization,
                    mod: mod,
                    pendingActivation: $pendingActivation,
                    pendingConflict: $pendingConflict,
                    onReportConflict: {
                        reportConflictTargetFolder = nil
                        reportConflictNote = ""
                        showReportConflict = true
                    },
                    onDelete: { showDeleteConfirm = true })
            }
        }
    }

    /// « version · auteur », auteur omis si vide ou « Unknown ».
    private var heroSubtitle: String {
        let version = String(format: localization.L(L10n.Mods.versionPrefix), vm.displayVersion(for: mod))
        if !mod.isGroup, !mod.author.isEmpty, mod.author != "Unknown" {
            return "\(version) · \(mod.author)"
        }
        return version
    }

    private var heroPictureURL: URL? {
        guard let extra = vm.modExtra(for: mod), !extra.pictureUrl.isEmpty else { return nil }
        return URL(string: extra.pictureUrl)
    }

    /// Catégorie, couverture FR, liens Nexus, date d'installation ; un
    /// composant ramène à son pack (sinon cul-de-sac).
    @ViewBuilder
    private var fineBand: some View {
        HStack(spacing: AppDesign.Spacing.lg) {
            if let pack = parentPack {
                Button {
                    vm.navigationStore.setViewingModDetail(pack)
                } label: {
                    Label(String(format: localization.L(L10n.Mods.backToPack), pack.name),
                          systemImage: "chevron.backward")
                        .font(AppDesign.Font.footnote)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            categoryTag
            if mod.languages.contains("fr") { FrenchCoverageBadge(percent: vm.frenchCoverage(for: mod), unmeasuredLabel: "FR", percentFormat: localization.L(L10n.Mods.frCoveragePercent)) }
            let link = vm.nexusLink(for: mod)
            if !link.isEmpty {
                AdaptiveLabels { HStack(spacing: AppDesign.Spacing.lg) { // ~547 pt en FR pour 512 : icônes seules
                    linkButton(icon: "link", label: localization.L(L10n.Mods.nexusOpenPage), url: link)
                    linkButton(icon: "ladybug", label: localization.L(L10n.Mods.detailBugs), url: link + "?tab=bugs")
                } }
            }
            Spacer()
            if let installed = vm.installedDate(for: mod) {
                Text(installed.formatted(date: .abbreviated, time: .omitted))
                    .font(AppDesign.Font.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(localization.L(L10n.Mods.detailInstalled))
            }
        }
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, 10)
        .frame(maxWidth: 700, alignment: .leading)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Le pack dont `mod` est un composant, s'il en est un.
    private var parentPack: ModItem? {
        guard !isTopLevel else { return nil }
        return vm.scanStore.mods.first { pack in
            pack.children?.contains { $0.folderName == mod.folderName } ?? false
        }
    }

    /// ‹ › sur le cadrage courant (ordre complet, pas la page) ; éteints hors
    /// cadrage. Dans la **barre de la fenêtre** : sur le hero, invisibles sur
    /// fond clair.
    private var pagerControls: some View {
        let neighbors = ModDetailPager.neighbors(of: mod.folderName,
                                                 in: vm.modList.displayOrder)
        return HStack(spacing: AppDesign.Spacing.xs) {
            chevron(icon: "chevron.left", target: neighbors.previous,
                    help: localization.L(L10n.Mods.pagerPrevious))
            chevron(icon: "chevron.right", target: neighbors.next,
                    help: localization.L(L10n.Mods.pagerNext))
        }
    }

    private func chevron(icon: String, target: String?, help: String) -> some View {
        Group {
            if let target, let destination = vm.scanStore.mods.first(where: { $0.folderName == target }) {
                Button {
                    vm.navigationStore.setViewingModDetail(destination)
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: AppDesign.Icon.sm))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .iconHelp(help)
            } else {
                Image(systemName: icon)
                    .font(.system(size: AppDesign.Icon.sm))
                    .foregroundStyle(.tertiary)
                    .help(localization.L(L10n.Mods.pagerUnavailable))
            }
        }
        .frame(width: 18, height: 18)   // cible de survol vivante
        .contentShape(.rect)
    }

    /// Version, fraîcheur, poids, langues — tous locaux.
    private var statStrip: some View {
        StatStrip(items: [
            .init(label: localization.L(L10n.ModInstall.labelVersion),
                  value: vm.displayVersion(for: mod)),
            .init(label: localization.L(L10n.Mods.detailUpdated), value: updatedLine),
            .init(label: localization.L(L10n.Mods.detailSize),
                  value: vm.sizeOnDisk(of: live).map(sizeText) ?? "—"),
            .init(label: localization.L(L10n.Mods.detailLanguages),
                  value: mod.languages.isEmpty
                      ? "—"
                      : mod.languages.map { $0.uppercased() }.joined(separator: " "),
                  help: mod.languages.isEmpty ? nil : mod.languages.joined(separator: " ")),
        ])
        // Même cadrage que la bande : 700 pt.
        .padding(.horizontal, AppDesign.Spacing.xl)
        .frame(maxWidth: 700, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    /// Date courte + âge au-delà d'un an (`LastUpdateAge`).
    private var updatedLine: String {
        guard let updated = vm.nexusLastUpdated(for: mod) else { return "—" }
        return [updated.formatted(date: .abbreviated, time: .omitted),
                LastUpdateAge.ageText(for: updated)].compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Top-level folder rather than a pack component (`scanStore.mods` never
    /// holds children).
    private var isTopLevel: Bool {
        vm.scanStore.mods.contains { $0.folderName == mod.folderName }
    }

    /// État courant relu dans `scanStore.mods` : `mod` est une **copie
    /// figée**, et l'interrupteur contredisait le disque après une pause.
    private var live: ModItem {
        vm.scanStore.mods.first { $0.folderName == mod.folderName } ?? mod
    }

    /// Racines de l'arbre rendu (fusionnées pour un pack), pas
    /// `mod.dependencies.count` (vide sur un en-tête).
    private var dependencyCount: Int {
        vm.dependencyTree(for: mod).count
    }

    /// Category chip: Nexus category, else the inferred offline tag.
    @ViewBuilder
    private var categoryTag: some View {
        if let cat = vm.category(for: mod) {
            HStack(spacing: 5) {
                Circle().fill(Color(cat.color)).frame(width: 7, height: 7)
                Text(cat.localizedName(localization.L)).font(AppDesign.Font.footnote(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9).padding(.vertical, AppDesign.Spacing.xs)
            .background(Color(cat.color).opacity(0.18))
            .clipShape(Capsule())
        } else {
            HStack(spacing: 5) {
                Image(systemName: "tag.fill").font(AppDesign.Font.iconXXS)
                Text(localization.L(L10n.ModTag.key(for: vm.inferredTagKey(for: mod)))).font(AppDesign.Font.footnote(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9).padding(.vertical, AppDesign.Spacing.xs)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    /// « 3,84 Go », pour un pack « 3,84 Go · Pack, 12 mods » (poids du
    /// dossier entier) ; rien sur les composants (compté une fois).
    private func sizeText(_ bytes: Int64) -> String {
        let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        guard live.isGroup, let count = live.children?.count else { return formatted }
        // Pack d'un seul mod possible : pas de « Pack, 1 mods ».
        guard count > 1 else { return formatted + " · " + localization.L(L10n.Mods.detailSizePackOne) }
        return formatted + " · " + String(format: localization.L(L10n.Mods.detailSizePack), count)
    }

    private func linkButton(icon: String, label: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            Label(label, systemImage: icon).font(.footnote.weight(.medium))
        }
        .buttonStyle(.plain)
        .help(label)
        .foregroundStyle(Color.accentColor)
        .pointingHandCursor()
    }

    // MARK: Pack contents (children of a group)

    @ViewBuilder
    private var packContentsSection: some View {
        if let children = mod.children, !children.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text(String(format: localization.L(L10n.Mods.detailPackContents), children.count))
                    .font(.headline)
                VStack(spacing: 6) {
                    ForEach(children) { child in
                        // Chaque composant ouvre sa fiche.
                        Button {
                            vm.navigationStore.setViewingModDetail(child)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(child.isEnabled ? AppDesign.Color.installed : Color.secondary.opacity(0.35))
                                    .frame(width: 7, height: 7)
                                Text(child.name).font(AppDesign.Font.body)
                                Spacer()
                                if !child.version.isEmpty, child.version != "Unknown" {
                                    Text("v\(child.version)")
                                        .font(AppDesign.Font.monoFootnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }
                }
                .padding(AppDesign.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: Settings (category + Nexus id) — migrated from `ModDetailsPopover`

    /// Boxed editors (pickers, text fields) kept out of the scrolling tabs
    /// (HIG), always visible.
    @ViewBuilder
    private var settingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                categorySection
                Divider()
                nexusSection
                Divider()
                noteSection
                Divider()
                profileConfigSection
            }
            .padding(.vertical, AppDesign.Spacing.xs)
        }
    }

    /// B3-T6 — note libre du mod **dans le profil actif** (le *pourquoi*).
    /// Un en-tête de pack n'en porte pas (F4) ; sans profil actif, la section
    /// l'explique au lieu de disparaître.
    @ViewBuilder
    private var noteSection: some View {
        if !mod.isGroup {
            VStack(alignment: .leading, spacing: 6) {
                if let profile = vm.activeProfile {
                    Text(String(format: localization.L(L10n.Mods.noteTitleProfile), profile.name))
                        .font(.headline)
                    TextEditor(text: $noteDraft)
                        .font(AppDesign.Font.caption)
                        .frame(height: 52)
                        .scrollContentBackground(.hidden)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .focused($noteFocused)
                    Text(localization.L(L10n.Mods.noteHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(localization.L(L10n.Mods.noteTitle))
                        .font(.headline)
                    Text(localization.L(L10n.Mods.noteNeedsProfile))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// B3-T5 — `config.json` suivant le profil actif. En-tête de pack : section
    /// **visible** qui l'explique (patron `noteSection`).
    @ViewBuilder
    private var profileConfigSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.L(L10n.Mods.profileConfigTitle))
                .font(.headline)

            if !vm.canManageProfileConfig(live) {
                Text(localization.L(L10n.Mods.profileConfigGroup))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Le `set` prend sa valeur, ne bascule pas. `live`, pas `mod` : les
                // chemins dérivent de `physicalFolderName`.
                Toggle(localization.L(L10n.Mods.profileConfigEnable), isOn: Binding(
                    get: { vm.isProfileConfigManaged(live) },
                    set: { on in
                        vm.setProfileConfigManaged(live, on)
                        refreshConfigHolders()
                    }
                ))
                .toggleStyle(.checkbox)
                .font(AppDesign.Font.caption)

                Text(localization.L(L10n.Mods.profileConfigHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if vm.isProfileConfigManaged(live) {
                    profileConfigHoldersView

                    // Comparer deux profils (spec §7) ; A = l'actif.
                    Menu {
                        ForEach(vm.modProfiles.filter { $0.id != vm.activeProfileId }) { profile in
                            Button(profile.name) { compareProfile = profile }
                        }
                    } label: {
                        Label(localization.L(L10n.Mods.profileConfigCompare),
                              systemImage: "rectangle.split.2x1")
                            .font(AppDesign.Font.caption)
                    }
                    .disabled(vm.modProfiles.filter { $0.id != vm.activeProfileId }.isEmpty)
                }

                Button(localization.L(L10n.Mods.profileConfigReset)) {
                    vm.resetModConfigToDefaults(live)
                    refreshConfigHolders()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)

                Text(localization.L(L10n.Mods.profileConfigResetHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Ce que chaque profil a mémorisé et **si ça diffère du disque** (sinon
    /// un aller-retour passe pour une panne). Lu **une fois** dans
    /// `configHolders` : au rendu, ce serait le gel des journaux.
    @ViewBuilder
    private var profileConfigHoldersView: some View {
        if configHolders.isEmpty {
            Text(localization.L(L10n.Mods.profileConfigNone))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                // Par rang : deux profils peuvent porter le même nom.
                ForEach(Array(configHolders.enumerated()), id: \.offset) { _, holder in
                    HStack(spacing: 6) {
                        Text(holder.profileName)
                            .font(AppDesign.Font.footnote(.medium))
                        Text(ByteCountFormatter.string(fromByteCount: Int64(holder.bytes),
                                                       countStyle: .file))
                            .font(AppDesign.Font.footnote)
                            .foregroundStyle(.secondary)
                        Text(holder.capturedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(AppDesign.Font.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(localization.L(holder.matchesDisk ? L10n.Mods.profileConfigSame
                                                     : L10n.Mods.profileConfigDiffers))
                            .font(AppDesign.Font.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(AppDesign.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.L(L10n.Mods.categoryLabel))
                .font(.headline)
            categoryPicker
            Text(localization.L(L10n.Mods.categoryEditHint))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Picker on the mod's own category; "Automatic" clears the override.
    private var categoryPicker: some View {
        let overrideId = vm.customCategoryId(for: mod)
        return Picker("", selection: Binding<Int?>(
            get: { overrideId },
            set: { newValue in vm.setCustomCategory(for: mod, categoryId: newValue) }
        )) {
            Text(localization.L(L10n.Mods.categoryAutomatic)).tag(Int?.none)
            ForEach(NexusCategory.all) { cat in
                Text(cat.localizedName(localization.L)).tag(Int?.some(cat.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Nexus id editor + fetch status (the header already links to Nexus).
    private var nexusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.L(L10n.Mods.nexusSection))
                .font(.headline)
            HStack(spacing: AppDesign.Spacing.sm) {
                Text(localization.L(L10n.Mods.nexusModId))
                    .font(AppDesign.Font.footnote(.medium))
                TextField("191", text: $nexusIdDraft)
                    .font(AppDesign.Font.monoCaption)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .onSubmit { commitDraft() }
                Button(localization.L(L10n.Mods.nexusSave)) { commitDraft() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isValidDraft)
                if vm.nexusCustomModIds[mod.folderName] != nil {
                    Button(localization.L(L10n.Mods.nexusReset), role: .destructive) { resetDraft() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundColor(AppDesign.Color.error)
                }
            }
            Text(localization.L(L10n.Mods.nexusModIdHint))
                .font(.caption)
                .foregroundStyle(.secondary)
            fetchStatusRow
            // Seulement sans fiche connue.
            if vm.resolvedNexusModId(for: mod).isEmpty {
                NexusIdentitySection(vm: vm, localization: localization, mod: mod)
            }
        }
    }

    /// Fetch status row: spinner, category + version, or error.
    @ViewBuilder
    private var fetchStatusRow: some View {
        switch fetchStatus {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(localization.L(L10n.Mods.nexusFetching))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
            }
        case .success(let catName, let latest):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppDesign.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppDesign.Color.success)
                        .font(AppDesign.Font.iconXS)
                    Text(localization.L(L10n.Mods.nexusFetchSuccess))
                        .font(AppDesign.Font.iconXS(.medium))
                        .foregroundColor(.secondary)
                }
                if let cat = catName {
                    Text(String(format: localization.L(L10n.Mods.nexusFetchedCategory), cat))
                        .font(AppDesign.Font.iconXS)
                        .foregroundColor(AppDesign.Color.dimmedSecondary(0.85))
                }
                if let v = latest {
                    Text(String(format: localization.L(L10n.Mods.nexusLatestVersion), v))
                        .font(AppDesign.Font.iconXS)
                        .foregroundColor(AppDesign.Color.dimmedSecondary(0.85))
                }
            }
        case .noApiKey:
            Text(localization.L(L10n.Mods.nexusNoApiKey))
                .font(AppDesign.Font.iconXS)
                .foregroundColor(AppDesign.Color.warning)
        case .failed(let msg):
            HStack(spacing: AppDesign.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppDesign.Color.error)
                    .font(AppDesign.Font.iconXS)
                Text(String(format: localization.L(L10n.Mods.nexusFetchFailed), msg))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(AppDesign.Color.error)
            }
        }
    }

    /// Valid draft: empty (clears) or positive integer; shared by
    /// `isValidDraft` and `commitDraft`.
    private func isValidNexusIdDraft(_ trimmed: String) -> Bool {
        trimmed.isEmpty || (Int(trimmed).map { $0 > 0 } ?? false)
    }

    private var isValidDraft: Bool {
        isValidNexusIdDraft(nexusIdDraft.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func seedDraft() {
        // `resolved…`: a pack header has no own id; the field looked empty while
        // the rest of the pane used the children's.
        nexusIdDraft = vm.resolvedNexusModId(for: mod)
    }

    private func commitDraft() {
        let trimmed = nexusIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidNexusIdDraft(trimmed) else { return }
        vm.setCustomNexusModId(for: mod, modId: trimmed.isEmpty ? nil : trimmed)
        nexusIdDraft = vm.resolvedNexusModId(for: mod)
        // Reload the detail: a new id must change the description too.
        vm.loadModDetail(for: mod)
        // Fetch metadata for the saved id (badge, update detection); clearing
        // resets to idle.
        let effectiveId = vm.resolvedNexusModId(for: mod)
        guard !effectiveId.isEmpty else { fetchStatus = .idle; return }
        fetchStatus = .loading
        vm.fetchMetadata(forNexusModId: effectiveId) { result in
            switch result {
            case .success(let version, let catId, _, _):
                let catName: String? = catId.flatMap { NexusCategory.from(id: $0) }
                    .map { $0.localizedName(localization.L) }
                fetchStatus = .success(categoryName: catName, latestVersion: version)
            case .noApiKey:
                fetchStatus = .noApiKey
            case .rateLimited(let retry):
                fetchStatus = .failed("rate limited (\(Int(retry))s)")
            case .error(let msg):
                fetchStatus = .failed(msg)
            }
        }
    }

    private func refreshConfigHolders() {
        configHolders = vm.profileConfigHolders(for: live)
    }

    private func resetDraft() {
        vm.setCustomNexusModId(for: mod, modId: nil)
        nexusIdDraft = vm.resolvedNexusModId(for: mod)
        // Same as `commitDraft`: the description follows the id.
        vm.loadModDetail(for: mod)
        fetchStatus = .idle
    }

    // MARK: Dependencies

    /// Transitive dependency tree (`DependencyTreeView`).
    @ViewBuilder
    private var dependenciesSection: some View {
        DependencyTreeView(vm: vm, localization: localization, mod: mod)
    }

    // MARK: Error history

    // MARK: Traduction

    /// **Quoi** manque : une clé **absente** affiche l'anglais, une clé
    /// **vide** n'affiche rien, en silence — 98 % à vides est pire que 60 %.
    /// Masquée sans français.
    @ViewBuilder
    private var translationSection: some View {
        // Aussi sans français si une sauvegarde en contient un ou qu'un fichier
        // ne sera jamais lu.
        if mod.languages.contains("fr") || backupTranslation != nil || translationStaleness != nil
            || !unloadableLocaleFiles.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text(localization.L(L10n.Mods.translationSection))
                    .font(AppDesign.Font.body(.semibold))

                // Défaut du mod : le jeu ne charge que des codes nus (sauf
                // `Data/AdditionalLanguages`). Id par indice : un même nom fautif peut
                // apparaître deux fois.
                ForEach(Array(unloadableLocaleFiles.enumerated()), id: \.offset) { _, file in
                    if let expected = file.expectedName {
                        translationNote(String(format: localization.L(L10n.Mods.translationUnloadableExpected),
                                               file.fileName, expected),
                                        icon: "exclamationmark.triangle", color: .secondary)
                    } else {
                        translationNote(String(format: localization.L(L10n.Mods.translationUnloadableUnknown),
                                               file.fileName),
                                        icon: "exclamationmark.triangle", color: .secondary)
                    }
                }

                if let backup = backupTranslation {
                    translationNote(String(format: localization.L(L10n.Mods.translationInBackup),
                                           backup.modifiedAt.formatted(date: .abbreviated,
                                                                       time: .omitted)),
                                    icon: "clock.arrow.circlepath", color: AppDesign.Color.warning)
                }

                if let stale = translationStaleness {
                    // Le fait et ses deux dates, jamais un verdict.
                    translationNote(
                        stale.note(sourceNewerFormat: localization.L(L10n.Mods.translationSourceNewer),
                                  sameDayFormat: localization.L(L10n.Mods.translationSourceNewerToday),
                                  oneDayFormat: localization.L(L10n.Mods.translationSourceNewerOneDay),
                                  dateText: stale.sourceDate.formatted(date: .abbreviated,
                                                                       time: .omitted)),
                        icon: "clock.badge.exclamationmark", color: .secondary)
                }
                if vm.outdatedKeyCount(for: mod) > 0 {
                    translationNote(String(format: localization.L(L10n.Mods.translationOutdatedKeys),
                                           vm.outdatedKeyCount(for: mod)),
                                    icon: "clock.badge.exclamationmark",
                                    color: DiffStateStyle.tint(.outdated))
                }

                if mod.languages.contains("fr"), let coverage = vm.frenchCoverageDetail(for: mod) {
                    TranslationProgressBar(percent: coverage.displayPercent)
                    Text(String(format: localization.L(L10n.Mods.translationCounts),
                                coverage.translated, coverage.total))
                        .font(AppDesign.Font.footnote.monospacedDigit())
                        .foregroundColor(.secondary)

                    // Les vides d'abord : seul défaut qui casse l'affichage.
                    if !coverage.empty.isEmpty {
                        translationNote(String(format: localization.L(L10n.Mods.translationEmpty),
                                               coverage.empty.count),
                                        icon: "exclamationmark.triangle.fill",
                                        color: AppDesign.Color.warning)
                    }
                    if !coverage.missing.isEmpty {
                        translationNote(String(format: localization.L(L10n.Mods.translationMissing),
                                               coverage.missing.count),
                                        icon: "text.badge.minus", color: .secondary)
                    }
                    // Seulement au-delà d'un cinquième de clés identiques à l'anglais
                    // (sinon la note toucherait 228/424 mods ; ici 12, traductions
                    // recopiées).
                    if coverage.total > 0,
                       Double(coverage.identicalToSource.count) / Double(coverage.total) > 0.2 {
                        translationNote(String(format: localization.L(L10n.Mods.translationIdentical),
                                               coverage.identicalToSource.count),
                                        icon: "equal.circle", color: .secondary)
                    }
                    if !coverage.orphan.isEmpty {
                        translationNote(String(format: localization.L(L10n.Mods.translationOrphan),
                                               coverage.orphan.count),
                                        icon: "questionmark.circle", color: .secondary)
                    }
                } else if mod.languages.contains("fr") {
                    // Calcul en cours : le dire.
                    Text(localization.L(L10n.Mods.translationPending))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func translationNote(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(AppDesign.Font.iconXS)
                .foregroundColor(color)
            Text(text)
                .font(AppDesign.Font.footnote)
                .foregroundColor(color == .secondary ? .secondary : color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Per-version errors and warnings; hidden when never logged.
    @ViewBuilder
    private var errorHistorySection: some View {
        let records = vm.modErrorHistory.history(for: mod.folderName)
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text(localization.L(L10n.Mods.errorHistory))
                    .font(AppDesign.Font.body(.semibold))
                Text(localization.L(L10n.Mods.errorHistoryHint))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(records, id: \.version) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(record.version)
                                .font(.system(size: AppDesign.Font.scaled(12), weight: .medium, design: .monospaced))
                            // Current version, for context.
                            if record.version == mod.version {
                                Text(localization.L(L10n.Mods.errorHistoryCurrent))
                                    .font(AppDesign.Font.iconXXS(.medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(3)
                            }
                            Spacer()
                            if record.errorCount > 0 {
                                Label("\(record.errorCount)", systemImage: "xmark.octagon")
                                    .font(AppDesign.Font.iconXS)
                                    .foregroundColor(AppDesign.Color.error)
                            }
                            if record.warningCount > 0 {
                                Label("\(record.warningCount)", systemImage: "exclamationmark.triangle")
                                    .font(AppDesign.Font.iconXS)
                                    .foregroundColor(AppDesign.Color.warning)
                            }
                        }
                        Text(record.lastSeen, style: .date)
                            .font(AppDesign.Font.iconXS)
                            .foregroundColor(.secondary)
                        ForEach(record.samples, id: \.self) { sample in
                            Text(sample)
                                .font(AppDesign.Font.monoIconXS)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: Raccourcis (C4-T2/T9)

    /// Raccourcis de **ce** mod, lus dans le rapport global. Muette sans
    /// rapport (« aucun conflit » sans mesure mentirait) et sans conflit
    /// (bruit). Lecture seule : agir passe par « Réglages du mod ».
    @ViewBuilder
    private var keybindConflictsSection: some View {
        if let conflicts = keybindScanService.report?.conflicts(affecting: mod.folderName),
           !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text(localization.L(L10n.Keybinds.title))
                    .font(AppDesign.Font.body(.semibold))

                if !conflicts.collisions.isEmpty {
                    Text(String(format: localization.L(L10n.Keybinds.collisionsHeader),
                                conflicts.collisions.count))
                        .font(AppDesign.Font.caption(.semibold))
                    ForEach(conflicts.collisions, id: \.combo) { collision in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collision.combo.display)
                                .font(AppDesign.Font.body(.medium))
                            ForEach(KeybindScanner.groupedUses(collision.uses)) { use in
                                // Hors interpolation (closure multiligne ne compile pas).
                                let paths = use.keyPaths
                                    .map { $0.joined(separator: ".") }
                                    .joined(separator: ", ")
                                Text("· \(use.modName) (\(paths))")
                                    .font(AppDesign.Font.caption).foregroundColor(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }

                if !conflicts.gameConflicts.isEmpty {
                    // Réserve visible : évite la fausse alerte chez qui a remappé.
                    Text(localization.L(L10n.Keybinds.gameCaveat))
                        .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                    Text(String(format: localization.L(L10n.Keybinds.gameHeader),
                                conflicts.gameConflicts.count))
                        .font(AppDesign.Font.caption(.semibold))
                    ForEach(conflicts.gameConflicts, id: \.control.name) { conflict in
                        // Une ligne, tronquée au milieu (fenêtre étroite).
                        HStack(spacing: AppDesign.Spacing.xs) {
                            Text(conflict.control.buttons.joined(separator: " / "))
                                .font(AppDesign.Font.body(.medium))
                                .lineLimit(1).truncationMode(.middle)
                            Text(conflict.control.name)
                                .font(AppDesign.Font.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }

    // MARK: Incompatibilités (tâche 9)

    /// Incompatibilités **déclarées** avec ce mod, écartables ici : retour
    /// visible là où « Signaler » vient d'être cliqué. Les observées ont leur
    /// écran (`ModConflictSection`) ; correspondance centralisée dans
    /// `vm.conflictPair(for:)`.
    @ViewBuilder
    private var declaredConflictsSection: some View {
        let pairs = vm.modConflictVerdicts.declared.filter { $0.contains(mod.folderName) }
        if !pairs.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text(localization.L(L10n.Conflicts.title))
                    .font(AppDesign.Font.body(.semibold))
                ForEach(pairs, id: \.self) { pair in
                    let otherFolder = pair.first == mod.folderName ? pair.second : pair.first
                    let otherName = vm.scanStore.mods.flattenedMods.first(where: { $0.folderName == otherFolder })?.name
                        ?? otherFolder
                    HStack(spacing: AppDesign.Spacing.xs) {
                        Text("· \(otherName)")
                            .font(AppDesign.Font.body(.medium))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(localization.L(L10n.Conflicts.dismissButton)) {
                            vm.dismissConflict(pair)
                        }
                        .buttonStyle(.borderless)
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                        .pointingHandCursor()
                    }
                }
            }
        }
    }

    /// Candidats : parc aplati, moins ce mod (une paire `(X, X)` collisionne
    /// avec `withinOnePack`).
    private var reportConflictCandidates: [ModItem] {
        vm.scanStore.mods.flattenedMods
            .filter { $0.folderName != mod.folderName }
            .alphabeticalListOrder
    }

    /// Sélecteur « Signaler » ; cible réinitialisée à l'ouverture (patron des
    /// brouillons).
    private var reportConflictSheet: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(L10n.Conflicts.reportButton))
                .font(.system(size: AppDesign.Font.scaled(15), weight: .bold))
            Picker(localization.L(L10n.Conflicts.pickMod), selection: $reportConflictTargetFolder) {
                Text("").tag(String?.none)
                ForEach(reportConflictCandidates, id: \.folderName) { candidate in
                    Text(candidate.name).tag(String?.some(candidate.folderName))
                }
            }
            TextField(localization.L(L10n.Conflicts.notePlaceholder), text: $reportConflictNote)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(localization.L(L10n.Saves.cancel)) { showReportConflict = false }
                Button(localization.L(L10n.Conflicts.reportConfirm)) {
                    if let targetFolder = reportConflictTargetFolder {
                        vm.declareConflict(ModConflictPair(mod.folderName, targetFolder),
                                           note: reportConflictNote)
                    }
                    showReportConflict = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(reportConflictTargetFolder == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    // MARK: Tab content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .translation:
            TranslationDiffView(vm: vm, localization: localization, mod: mod)
        case .dependencies:
            dependenciesSection
        case .changelog:
            blocksView(isChangelog: true)
        case .state:
            // État du mod groupé ; sections déplacées telles quelles.
            VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                // A2-T7 — au-dessus de tout : seul à parler de code hostile.
                MaliciousModBanner(vm: vm, localization: localization, mod: live)
                if let anomaly = vm.anomaly(for: live) {
                    ModAnomalyCard(anomaly: anomaly, vm: vm, localization: localization, currentFolder: live.folderName) { selectedTab = .dependencies }
                }
                // I-T16 — par gravité : bloquant, gênant, puis traduction.
                CompatibilityBanner(vm: vm, localization: localization, mod: live)
                errorHistorySection
                declaredConflictsSection
                PerformanceOverlapDetailRows(vm: vm, localization: localization, mod: live)
                keybindConflictsSection
                NexusPageBanner(vm: vm, localization: localization, mod: live)
                // Le hub de traduction : premier niveau seulement, là où il a sens.
                if isTopLevel { TranslationSection(vm: vm, localization: localization, mod: live) }
                translationSection
                if isTopLevel { SupplementSection(vm: vm, localization: localization, mod: live) }
            }
        case .description:
            // Description tab: pack contents + settings + description.
            VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                if mod.isGroup { packContentsSection }
                settingsSection
                // C2-T4 — changements de clés de la dernière mise à jour ; closures
                // directes (les canaux `pending…Focus` ne servent qu'au changement
                // d'onglet).
                ModUpdateDeltaSection(vm: vm, localization: localization, mod: mod,
                                      onOpenConfig: { vm.navigationStore.setEditingModConfig(mod) },
                                      onOpenTranslation: {
                                          vm.navigationStore.pendingTranslationDiffFilter = .state(.missing)
                                          selectedTab = .translation
                                      })
                blocksView(isChangelog: false)
            }
        }
    }

    /// Renders the description or changelog blocks with loading / empty states.
    @ViewBuilder
    private func blocksView(isChangelog: Bool) -> some View {
        if let state = vm.modDetailState {
            let blocks = isChangelog ? state.changelog : state.description
            if blocks.isEmpty {
                if state.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    // Genuinely absent content: neutral per-tab message, not "offline".
                    ContentUnavailableView(
                        localization.L(isChangelog ? L10n.Mods.detailNoChangelog : L10n.Mods.detailNoDescription),
                        systemImage: "doc.plaintext"
                    )
                    .frame(maxWidth: .infinity, minHeight: 160)
                }
            } else {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                    if state.isStale {
                        stalenessHint
                    }
                    DescriptionBlocksView(blocks: blocks, vm: vm, localization: localization)

                    // **Ce que l'auteur dit de la compatibilité** (30 % des fiches, médiane
                    // 359 caractères : pas de repli). Onglet Description seulement : dans le
                    // changelog, ce serait une note de version.
                    if !isChangelog, let note = CompatibilityNote.find(in: blocks) {
                        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                            Text(localization.L(L10n.Mods.compatibilityNote))
                                .font(AppDesign.Font.caption(.semibold))
                                .foregroundColor(.secondary)
                            DescriptionBlocksView(blocks: note.blocks, vm: vm, localization: localization)
                        }
                        .padding(AppDesign.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.08)))
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
        }
    }

    /// Indicator for cached/fallback content while a refresh runs (or failed).
    private var stalenessHint: some View {
        Label(localization.L(L10n.Mods.detailCached), systemImage: "arrow.triangle.2.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

