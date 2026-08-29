import SwiftUI

/// Rich detail pane for a single mod: header (artwork, name, version/author,
/// Nexus link), a settings section (category override + Nexus-id editor), and
/// Description/Changelog/Dependencies segmented tabs — the last rendering
/// `DescriptionBlock`s produced by `StarHubTHViewModel.loadModDetail(for:)`.
/// Lives in the NavigationSplitView detail column (pushed via
/// `vm.viewingModDetail`, wired in `MainView`) — never a sheet/modal, so it
/// behaves like any other master-detail drill-down (back chevron pops it).
///
/// The caller (`MainView`) applies `.id(mod.folderName)` to this view so a
/// fresh instance is created whenever the user switches to a different mod:
/// that resets `selectedTab` and, more importantly, the Nexus-id draft below
/// so an in-progress edit can never leak onto the wrong mod's folder.
struct ModDetailView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem
    /// Le rapport de raccourcis vit sur ce service (tâche 9) : il est
    /// publié de façon asynchrone — le scan part quand le parc est connu
    /// (tâche 7) — et `keybindScanService` est un `let` du ViewModel, pas
    /// un `@Published` : sans observation ici, une fiche ouverte avant la
    /// fin du premier scan resterait muette sur ses conflits pour de bon.
    /// Même patron que `HomeView` et `MainView`.
    @ObservedObject private var keybindScanService: KeybindScanService

    init(vm: StarHubTHViewModel, mod: ModItem) {
        self.vm = vm
        self.mod = mod
        self.keybindScanService = vm.keybindScanService
    }

    @State private var selectedTab = 0
    /// Le mod dont l'activation attend une confirmation : smapi.io le signale
    /// cassé. Voir `CompatibilityWarning`.
    @State private var pendingActivation: ModItem?
    /// Même rôle, source différente : un conflit déclaré ou observé dans le
    /// journal avec un mod déjà actif (tâche 9). Voir `ConflictActivationGate`.
    @State private var pendingConflict: ConflictActivation?
    /// L'état du sélecteur « Signaler une incompatibilité… » (tâche 9).
    /// La cible se porte sur son `folderName`, pas sur le `ModItem` lui-même
    /// — `Picker(selection:)` demande `Hashable`, qu'`ModItem` ne porte pas
    /// (seulement `Equatable` : l'ajouter pour ce seul sélecteur aurait
    /// touché tout ce qui manipule `ModItem` ailleurs dans le dépôt).
    @State private var showReportConflict = false
    @State private var reportConflictTargetFolder: String?
    @State private var reportConflictNote: String = ""

    /// Draft text for the Nexus mod id field. Seeded once in `.onAppear` from
    /// the mod's effective id; safe to seed unconditionally (no "already
    /// seeded" guard needed) because the `.id(mod.folderName)` at the call
    /// site gives this view a fresh instance — and therefore a fresh
    /// `@State` — per mod.
    @State private var nexusIdDraft: String = ""
    /// B3-T6 — brouillon de la note libre, au patron du draft Nexus : la vue
    /// est recréée par mod (`.id(mod.folderName)` côté MainView), un brouillon
    /// ne peut donc jamais fuir sur le mod voisin.
    @State private var noteDraft: String = ""
    @FocusState private var noteFocused: Bool

    /// On-demand metadata fetch status (triggered after the user saves a new
    /// Nexus mod id). `.idle` hides the status row; `.loading` shows a spinner.
    @State private var fetchStatus: FetchStatus = .idle

    /// Position optimiste de l'interrupteur pendant que le dossier est renommé,
    /// `nil` dès que `vm.mods` a rattrapé — même mécanique que la liste.
    @State private var localIsOn: Bool? = nil
    /// Debounce du toggle : annule un toggle en attente si l'utilisateur
    /// rebascule avant le délai (sinon le 1er clic d'un double-clic gagnait).
    @State private var pendingToggle: DispatchWorkItem? = nil
    @State private var showDeleteConfirm = false

    /// Une traduction française retrouvée dans une sauvegarde, pour un mod qui
    /// n'en a plus. Cherché à l'ouverture de la fiche, hors du fil principal.
    @State private var backupTranslation: TranslationBackupFinder.Found?

    /// L'anglais de ce mod a-t-il été touché après son français ? Mesuré à
    /// l'ouverture de la fiche, hors du fil principal.
    @State private var translationStaleness: TranslationFreshness.Staleness?

    /// Les fichiers de traduction de ce mod que le jeu n'ouvrira jamais — un
    /// `pt-BR.json` sans `pt.json`, par exemple. Cherché à l'ouverture de la
    /// fiche, hors du fil principal.
    @State private var unloadableLocaleFiles: [I18nLocaleResolver.UnloadableLocaleFile] = []

    /// Ce que les profils ont mémorisé pour ce mod. Rempli à l'apparition et
    /// après chaque geste qui le change — jamais recalculé au rendu.
    @State private var configHolders: [(profileName: String, capturedAt: Date,
                                        bytes: Int, matchesDisk: Bool)] = []

    /// Le profil B de la comparaison des configs, quand la sheet est
    /// ouverte (le profil A est toujours l'actif).
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
            // Fixed hero + tab bar — both stay pinned while the tab content
            // below scrolls.
            heroBanner
            tabBar
            ScrollView {
                content
                    .frame(maxWidth: 700, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            seedDraft()
            noteDraft = vm.modNote(for: mod) ?? ""
            refreshConfigHolders()
        }
        .sheet(item: $compareProfile) { profile in
            ProfileConfigCompareView(vm: vm, mod: live, other: profile,
                                     isPresented: Binding(
                                        get: { compareProfile != nil },
                                        set: { if !$0 { compareProfile = nil } }))
        }
        // Pause/reprise renomme le dossier physique du mod (`live`, pas
        // `mod` — voir `profileConfigSection`), ce qui change le chemin où
        // `profileConfigHolders(for:)` lit le config.json. `mod.isEnabled`
        // ne bougerait jamais : c'est une copie figée, elle ne déclencherait
        // jamais cet `onChange`.
        .onChange(of: live.isEnabled) { _, _ in
            refreshConfigHolders()
        }
        // B3-T6 — la note se sauvegarde à la perte du focus : une annotation
        // n'est pas un formulaire, pas de bouton Enregistrer.
        .onChange(of: noteFocused) { _, focused in
            if !focused { vm.setModNote(noteDraft, for: mod) }
        }
        // …et aussi à la sortie de la fiche : cliquer un autre mod dans la
        // liste remplace la vue (`.id(mod.folderName)`) avant que le blur ne
        // tire — sans ce filet, une note vidée juste avant de partir n'était
        // jamais committée. Idempotent avec le blur : même valeur, deux fois.
        .onDisappear {
            vm.setModNote(noteDraft, for: mod)
        }
        .compatibilityGate(vm: vm, pending: $pendingActivation) { target in
            vm.toggleMod(target)
        }
        .conflictActivationGate(vm: vm, pending: $pendingConflict) { target in
            vm.toggleMod(target)
        }
        .sheet(isPresented: $showReportConflict) {
            reportConflictSheet
        }
        .task {
            // Venu de la couverture française d'un profil : la demande n'était
            // pas « montre-moi ce mod » mais « traduis-le ». Consommée ici,
            // avant tout travail asynchrone, et effacée aussitôt pour que le
            // mod suivant ne s'ouvre pas sur le même onglet.
            if vm.pendingTranslationFocus == mod.folderName {
                vm.pendingTranslationFocus = nil
                if mod.languages.contains("fr") || mod.languages.contains("en") {
                    selectedTab = 3
                }
            }
            translationStaleness = await vm.translationStaleness(for: mod)
            unloadableLocaleFiles = await vm.unloadableLocaleFiles(for: mod)
            // Seulement quand il y a quelque chose à retrouver : un mod déjà
            // traduit n'a pas besoin qu'on fouille les sauvegardes.
            guard !mod.languages.contains("fr") else { return }
            backupTranslation = await vm.backupTranslation(for: mod)
        }
    }

    /// The Description / Changelog / Dependencies switcher, pinned under the
    /// hero (outside the ScrollView) so it stays visible while scrolling.
    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            Text(vm.L(L10n.Mods.detailDescription)).tag(0)
            Text(vm.L(L10n.Mods.detailChangelog)).tag(1)
            Text(vm.L(L10n.Profiles.dependencies)).tag(2)
            // Quatrième onglet plutôt qu'une feuille : la barre est déjà
            // épinglée sous la bannière, et le diff est une lecture du mod
            // comme les autres — pas une action modale.
            // `en` autant que `fr` : un mod qui n'a qu'un `default.json` est
            // précisément celui qu'il reste à traduire, et c'est lui qui a le
            // plus besoin de cet onglet. Le réserver aux mods déjà traduits
            // n'ouvrait l'éditeur que là où le travail était fait.
            // (`I18nLocaleResolver.languageCodes` rend `default` sous la forme
            // `en` : la présence de `en` signifie donc « il y a une source ».)
            if mod.languages.contains("fr") || mod.languages.contains("en") {
                Text(vm.L(L10n.Mods.diffTab)).tag(3)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 700)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: Hero banner (full-width illustration + full-width metadata band)

    private var heroBanner: some View {
        VStack(spacing: 0) {
            bannerImage
            headerBand
        }
    }

    /// Compact edge-to-edge illustration (shorter than a full hero image) so the
    /// pinned banner doesn't eat the pane. Omitted when there's no picture.
    @ViewBuilder
    private var bannerImage: some View {
        if let extra = vm.modExtra(for: mod), !extra.pictureUrl.isEmpty, let url = URL(string: extra.pictureUrl) {
            CachedAsyncImage(url: url)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .clipped()
        }
    }

    /// Compact metadata band under the image: name + category + links on the
    /// left, the metadata (updated / installed / languages) stacked on the
    /// right. The name sits on a solid tinted band so it stays readable.
    private var headerBand: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                categoryTag
                Text(mod.name)
                    .font(.title2.weight(.bold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)   // wrap long names
                HStack(spacing: 6) {
                    Text(String(format: vm.L(L10n.Mods.versionPrefix), vm.displayVersion(for: mod)))
                    if !mod.isGroup, !mod.author.isEmpty, mod.author != "Unknown" {
                        Text("•")
                        Text(mod.author)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                let link = vm.nexusLink(for: mod)
                if !link.isEmpty {
                    HStack(spacing: 16) {
                        linkButton(icon: "link", label: vm.L(L10n.Mods.nexusOpenPage), url: link)
                        linkButton(icon: "ladybug", label: vm.L(L10n.Mods.detailBugs), url: link + "?tab=bugs")
                    }
                }
                actionRow
                CompatibilityBanner(vm: vm, mod: live)
                if isTopLevel { TranslationSection(vm: vm, mod: live) }
                if isTopLevel { SupplementSection(vm: vm, mod: live) }
            }
            Spacer(minLength: 8)
            metadataColumn
        }
        .frame(maxWidth: 700, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.opacity(0.06))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Whether this mod is a top-level folder rather than one component of a
    /// pack. Same test as `performToggle`'s seed resolution: `vm.mods` holds
    /// pack headers and standalone mods, never children.
    private var isTopLevel: Bool {
        vm.mods.contains { $0.folderName == mod.folderName }
    }

    /// L'état courant du mod, relu dans `vm.mods` à chaque rendu.
    ///
    /// `mod` est une **copie figée** au moment où la fiche a été ouverte
    /// (`vm.viewingModDetail`), et rien ne la rafraîchit : mettre le mod en
    /// pause renomme bien le dossier et met à jour `vm.mods`, mais la copie
    /// garde son ancien `isEnabled`. L'interrupteur revenait donc en position
    /// « activé » dès que la valeur optimiste s'effaçait — l'affichage
    /// contredisait le disque.
    private var live: ModItem {
        vm.mods.first { $0.folderName == mod.folderName } ?? mod
    }

    /// Mettre en pause et supprimer, depuis la fiche. Jusqu'ici il fallait
    /// revenir à la liste pour les deux — alors que la fiche est justement
    /// l'écran où l'on décide du sort d'un mod, après avoir lu sa description,
    /// ses dépendances et son historique d'erreurs.
    ///
    /// Absent pour un composant de pack, comme dans la liste : c'est l'en-tête
    /// du pack qui porte ces actions pour tous ses composants, et mettre en
    /// pause un seul composant n'a pas de sens — SMAPI écarterait les autres.
    @ViewBuilder
    private var actionRow: some View {
        if isTopLevel {
            HStack(spacing: 12) {
                // La place du témoin est réservée en permanence : le faire
                // apparaître et disparaître décalait tout le reste de la rangée
                // à chaque bascule, et l'interrupteur semblait sauter.
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
                    .opacity(vm.pendingToggleFolder == mod.folderName ? 1 : 0)
                Toggle(vm.L(L10n.Mods.detailEnabled), isOn: Binding(
                    get: { localIsOn ?? live.isEnabled },
                    set: { newValue in
                        // Même temporisation optimiste que la liste : la valeur
                        // locale tient jusqu'à ce que la complétion confirme
                        // que `vm.mods` a rattrapé, sinon l'interrupteur revient
                        // visiblement en arrière le temps du rescan.
                        localIsOn = newValue
                        // Annule un toggle en attente : sans cela, un double-clic
                        // laissait deux timers tirer et le 1er clic gagnait.
                        pendingToggle?.cancel()
                        let work = DispatchWorkItem {
                            if newValue != live.isEnabled {
                                // Activer un mod signalé cassé demande une
                                // confirmation ; le mettre en pause, jamais.
                                if vm.activationWarning(for: live) != nil {
                                    localIsOn = nil
                                    pendingActivation = live
                                } else if let other = vm.conflictWarning(for: live) {
                                    // Même porte, source différente : un
                                    // conflit déclaré ou observé dans le
                                    // journal avec un mod déjà actif (tâche 9).
                                    localIsOn = nil
                                    pendingConflict = ConflictActivation(mod: live, other: other)
                                } else {
                                    vm.toggleMod(live) { localIsOn = nil }
                                }
                            } else {
                                localIsOn = nil
                            }
                        }
                        pendingToggle = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.20, green: 0.65, blue: 0.35)))
                .controlSize(.small)
                // Annuler un toggle en attente quand la vue disparaît : sinon le
                // timer (debounce 300 ms) tirait pour un mod désaffiché.
                .onDisappear { pendingToggle?.cancel() }
                .accessibilityLabel(String(format: vm.L(L10n.Mods.toggleA11yLabel), mod.name))
                .accessibilityHint(vm.L(L10n.Mods.toggleA11yHint))

                // Le favori, à côté de la bascule : même geste de tri du parc,
                // et la fiche est l'écran où l'on décide du sort d'un mod.
                // `live` et non `mod` — la clé est le `folderName` logique, que
                // la bascule ne change pas, mais lire l'état courant garde la
                // fiche d'accord avec la liste après un aller-retour.
                Button {
                    vm.toggleFavorite(live)
                } label: {
                    Label(vm.L(vm.isFavorite(live) ? L10n.Mods.favoriteRemove : L10n.Mods.favoriteAdd),
                          systemImage: vm.isFavorite(live) ? "star.fill" : "star")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundColor(vm.isFavorite(live) ? .yellow : .secondary)
                .pointingHandCursor()

                // La config du mod, entre le favori et la suppression : la
                // fiche est l'écran où l'on décide du sort d'un mod, ses
                // réglages en font partie — jusqu'ici il fallait repasser
                // par la liste pour l'engrenage. Même prédicat que la liste
                // (`!isGroup && hasConfigFile`) : un en-tête de pack n'a pas
                // de config à lui. `live`, pas `mod` : l'éditeur construit
                // ses chemins depuis `physicalFolderName`, que la mise en
                // pause renomme — la copie figée viserait un dossier qui
                // n'existe plus.
                if !live.isGroup && live.hasConfigFile {
                    Button {
                        vm.editingModConfig = live
                    } label: {
                        Label(vm.L(L10n.Settings.configModSettings),
                              systemImage: "gearshape")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .pointingHandCursor()
                }

                // « Signaler une incompatibilité… » (tâche 9) : ouvre le
                // sélecteur parmi les mods installés. Réservé aux mods de
                // premier niveau, comme les autres actions de cette rangée —
                // un composant de pack ne se signale pas seul, c'est le pack
                // entier qui est en cause.
                Button {
                    reportConflictTargetFolder = nil
                    reportConflictNote = ""
                    showReportConflict = true
                } label: {
                    // `exclamationmark.triangle`, sans `.fill` : déjà utilisé
                    // (non filled) ailleurs dans ce dépôt — un nom de
                    // symbole erroné compile sans avertissement et se rend
                    // comme un rectangle vide, indétectable au build (voir
                    // la mise en garde de la tâche 8 sur `arrow.triangle.merge`).
                    Label(vm.L(L10n.Conflicts.reportButton), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .pointingHandCursor()

                // Pas de pendant au spinner de suppression de la liste : la
                // fiche se referme dès la confirmation, personne ne le verrait.
                // La garde sur une suppression déjà en vol, elle, reste utile.
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label(vm.L(L10n.Mods.deleteMod), systemImage: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .disabled(vm.pendingDeleteFolder != nil)
                .accessibilityHint(vm.L(L10n.Mods.deleteModA11yHint))
                .pointingHandCursor()
            }
            .padding(.top, 2)
            .confirmationDialog(
                String(format: vm.L(L10n.Mods.deleteConfirmTitle), mod.name),
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(vm.L(L10n.Mods.deleteMod), role: .destructive) {
                    vm.deleteMod(mod)
                    // Refermer la fiche : le mod qu'elle décrit n'existe plus.
                    // La laisser ouverte afficherait une version, des
                    // dépendances et une description d'un dossier supprimé.
                    vm.viewingModDetail = nil
                }
                Button(vm.L(L10n.Saves.cancel), role: .cancel) { }
            } message: {
                Text(mod.isGroup
                     ? vm.L(L10n.Mods.deleteConfirmPack)
                     : vm.L(L10n.Mods.deleteConfirmMessage))
            }
        }
    }

    /// The mod's category as a colored chip — the Nexus category when known,
    /// otherwise the inferred offline type tag (same resolution as the list).
    @ViewBuilder
    private var categoryTag: some View {
        if let cat = vm.category(for: mod) {
            HStack(spacing: 5) {
                Circle().fill(cat.color).frame(width: 7, height: 7)
                Text(cat.localizedName(vm.L)).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(cat.color.opacity(0.18))
            .clipShape(Capsule())
        } else {
            HStack(spacing: 5) {
                Image(systemName: "tag.fill").font(.system(size: 9))
                Text(vm.L(L10n.ModTag.key(for: vm.inferredTagKey(for: mod)))).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    /// Metadata stacked vertically on the right of the header band (last update,
    /// install date, languages) — one under another. Empty when nothing's known.
    @ViewBuilder
    private var metadataColumn: some View {
        let updated = vm.nexusLastUpdated(for: mod)
        let installed = vm.installedDate(for: mod)
        let langs = mod.languages
        // `live` et non `mod` : le poids est indexé sur le nom **physique** du
        // dossier, qui porte un point quand le mod est en pause. La copie figée
        // à l'ouverture de la fiche garde l'ancien `isEnabled` — mettre le mod
        // en pause depuis cette fiche ferait alors chercher la mauvaise clé.
        let size = vm.sizeOnDisk(of: live)
        if updated != nil || installed != nil || !langs.isEmpty || size != nil {
            VStack(alignment: .trailing, spacing: 8) {
                if let size {
                    metaLine(icon: "internaldrive",
                             label: vm.L(L10n.Mods.detailSize),
                             text: sizeText(size))
                }
                if let updated {
                    // B2-T5 : l'âge rejoint la date à partir d'un an révolu —
                    // la règle vit en Core (`LastUpdateAge`) avec ses tests,
                    // la vue ne fait que composer. « · » : le patron du dépôt
                    // pour deux valeurs sur une même ligne.
                    metaLine(icon: "clock.arrow.circlepath",
                             label: vm.L(L10n.Mods.detailUpdated),
                             text: [updated.formatted(date: .abbreviated, time: .omitted),
                                    LastUpdateAge.ageText(for: updated)].compactMap { $0 }
                                 .joined(separator: " · "))
                }
                if let installed {
                    metaLine(icon: "tray.and.arrow.down",
                             label: vm.L(L10n.Mods.detailInstalled),
                             text: installed.formatted(date: .abbreviated, time: .omitted))
                }
                if !langs.isEmpty {
                    metaLine(icon: "globe",
                             label: vm.L(L10n.Mods.detailLanguages),
                             text: langs.map { $0.uppercased() }.joined(separator: " "))
                }
            }
            .frame(maxWidth: 210, alignment: .trailing)
        }
    }

    /// « 3,84 Go », et pour un pack « 3,84 Go · Pack, 12 mods ».
    ///
    /// Un pack est **un** dossier de premier niveau qui en contient plusieurs :
    /// le poids mesuré est celui du dossier entier, pas d'un composant. Le dire
    /// évite qu'on lise 3,84 Go comme le poids d'un seul de ses mods. Les
    /// composants, eux, n'affichent rien : répéter le chiffre du pack sur
    /// chacun compterait la même place autant de fois qu'il y a de composants.
    private func sizeText(_ bytes: Int64) -> String {
        let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        guard live.isGroup, let count = live.children?.count else { return formatted }
        // Un « pack » d'un seul mod existe : le scan prend la branche groupe
        // dès que le manifeste ne siège pas à la racine du dossier de premier
        // niveau. « Pack, 1 mods » se lirait comme un défaut.
        guard count > 1 else { return formatted + " · " + vm.L(L10n.Mods.detailSizePackOne) }
        return formatted + " · " + String(format: vm.L(L10n.Mods.detailSizePack), count)
    }

    private func metaLine(icon: String, label: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.secondary)
            VStack(alignment: .trailing, spacing: 1) {
                Text(label).font(.system(size: 9)).foregroundStyle(.secondary.opacity(0.75))
                Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
        }
    }

    private func linkButton(icon: String, label: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.footnote.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .pointingHandCursor()
    }

    // MARK: Pack contents (children of a group)

    @ViewBuilder
    private var packContentsSection: some View {
        if let children = mod.children, !children.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: vm.L(L10n.Mods.detailPackContents), children.count))
                    .font(.headline)
                VStack(spacing: 6) {
                    ForEach(children) { child in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(child.isEnabled ? Color.green : Color.secondary.opacity(0.35))
                                .frame(width: 7, height: 7)
                            Text(child.name).font(.system(size: 13))
                            Spacer()
                            if !child.version.isEmpty, child.version != "Unknown" {
                                Text("v\(child.version)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: Settings (category + Nexus id) — migrated from `ModDetailsPopover`

    /// Grouped, boxed section sitting between the header and the read-only
    /// content tabs: HIG guidance keeps interactive controls (pickers, text
    /// fields) out of the scrolling Description/Changelog/Dependencies tabs,
    /// so both editors live here instead, always visible regardless of tab.
    @ViewBuilder
    private var settingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                categorySection
                Divider()
                nexusSection
                Divider()
                noteSection
                Divider()
                profileConfigSection
            }
            .padding(.vertical, 4)
        }
    }

    /// B3-T6 — note libre attachée au mod **dans le profil actif** : elle dit
    /// *pourquoi* (« désactivé en multi car désync ») et change avec le
    /// profil. L'en-tête d'un pack n'a pas d'identité (F4) — ses composants
    /// se notent eux-mêmes ; sans profil actif la section reste visible et
    /// l'explique, plutôt que de disparaître sans dire pourquoi.
    @ViewBuilder
    private var noteSection: some View {
        if !mod.isGroup {
            VStack(alignment: .leading, spacing: 6) {
                if let profile = vm.activeProfile {
                    Text(String(format: vm.L(L10n.Mods.noteTitleProfile), profile.name))
                        .font(.headline)
                    TextEditor(text: $noteDraft)
                        .font(.system(size: 12))
                        .frame(height: 52)
                        .scrollContentBackground(.hidden)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .focused($noteFocused)
                    Text(vm.L(L10n.Mods.noteHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(vm.L(L10n.Mods.noteTitle))
                        .font(.headline)
                    Text(vm.L(L10n.Mods.noteNeedsProfile))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// B3-T5 — le `config.json` du mod suit le profil actif : mémorisé quand
    /// on quitte un profil, réécrit quand on y revient.
    ///
    /// L'en-tête d'un pack n'a pas de réglages propres — ses composants ont
    /// chacun les leurs. La section reste **visible** et l'explique, au patron
    /// de `noteSection` sans profil actif : disparaître sans dire pourquoi
    /// laisserait croire à un oubli.
    @ViewBuilder
    private var profileConfigSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.L(L10n.Mods.profileConfigTitle))
                .font(.headline)

            if !vm.canManageProfileConfig(live) {
                Text(vm.L(L10n.Mods.profileConfigGroup))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Le `set` prend sa valeur — il ne bascule pas. SwiftUI
                // réécrit la valeur affichée au re-rendu, et un setter qui
                // basculerait démarquerait le mod tout seul.
                //
                // `live`, pas `mod` : mettre le mod en pause renomme son
                // dossier physique (X7 dans `actionRow`), et `resetModConfigToDefaults`
                // comme `profileConfigHolders(for:)` calculent leur chemin à
                // partir de `physicalFolderName` — la copie figée viserait un
                // dossier qui n'existe plus.
                Toggle(vm.L(L10n.Mods.profileConfigEnable), isOn: Binding(
                    get: { vm.isProfileConfigManaged(live) },
                    set: { on in
                        vm.setProfileConfigManaged(live, on)
                        refreshConfigHolders()
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

                Text(vm.L(L10n.Mods.profileConfigHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if vm.isProfileConfigManaged(live) {
                    profileConfigHoldersView

                    // Comparer ce que deux profils retiennent de ce mod —
                    // l'écran qui rend la divergence lisible (spec §7). Le
                    // profil actif y est toujours le côté A.
                    Menu {
                        ForEach(vm.modProfiles.filter { $0.id != vm.activeProfileId }) { profile in
                            Button(profile.name) { compareProfile = profile }
                        }
                    } label: {
                        Label(vm.L(L10n.Mods.profileConfigCompare),
                              systemImage: "rectangle.split.2x1")
                            .font(.system(size: 12))
                    }
                    .disabled(vm.modProfiles.filter { $0.id != vm.activeProfileId }.isEmpty)
                }

                Button(vm.L(L10n.Mods.profileConfigReset)) {
                    vm.resetModConfigToDefaults(live)
                    refreshConfigHolders()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)

                Text(vm.L(L10n.Mods.profileConfigResetHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Ce que chaque profil a mémorisé, et surtout **si cela diffère encore du
    /// disque**. Après un aller-retour entre deux profils, les deux mémorisent
    /// le même texte : sans ce renseignement, l'absence d'effet se lirait
    /// comme une panne.
    ///
    /// Lu **une fois** dans `configHolders`, jamais à chaque rendu : chaque
    /// appel ouvre et décode le fichier de magasin de chaque profil, plus le
    /// `config.json` du mod. Une propriété calculée le referait à chaque
    /// redessin — la forme exacte qui a figé la page des journaux et coûté
    /// 14,8 s au balayage de couverture.
    @ViewBuilder
    private var profileConfigHoldersView: some View {
        if configHolders.isEmpty {
            Text(vm.L(L10n.Mods.profileConfigNone))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                // Indexé par rang : rien n'empêche deux profils de porter
                // le même nom, et un id dupliqué fait taire des lignes.
                ForEach(Array(configHolders.enumerated()), id: \.offset) { _, holder in
                    HStack(spacing: 6) {
                        Text(holder.profileName)
                            .font(.system(size: 11, weight: .medium))
                        Text(ByteCountFormatter.string(fromByteCount: Int64(holder.bytes),
                                                       countStyle: .file))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(holder.capturedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(vm.L(holder.matchesDisk ? L10n.Mods.profileConfigSame
                                                     : L10n.Mods.profileConfigDiffers))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.L(L10n.Mods.categoryLabel))
                .font(.headline)
            categoryPicker
            Text(vm.L(L10n.Mods.categoryEditHint))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Dropdown bound to the mod's own effective category (never the
    /// pack→child fallback used elsewhere for content resolution). Selecting
    /// "Automatic" clears any user override; selecting a category pins it.
    private var categoryPicker: some View {
        let overrideId = vm.customCategoryId(for: mod)
        return Picker("", selection: Binding<Int?>(
            get: { overrideId },
            set: { newValue in vm.setCustomCategory(for: mod, categoryId: newValue) }
        )) {
            Text(vm.L(L10n.Mods.categoryAutomatic)).tag(Int?.none)
            ForEach(NexusCategory.all) { cat in
                Text(cat.localizedName(vm.L)).tag(Int?.some(cat.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Nexus-id editor + fetch status. The header above already renders a
    /// "View on Nexus" link, so unlike the old popover this section skips the
    /// open-link button and the raw URL text — it only owns the id itself.
    private var nexusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.L(L10n.Mods.nexusSection))
                .font(.headline)
            HStack(spacing: 8) {
                Text(vm.L(L10n.Mods.nexusModId))
                    .font(.system(size: 11, weight: .medium))
                TextField("191", text: $nexusIdDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .onSubmit { commitDraft() }
                Button(vm.L(L10n.Mods.nexusSave)) { commitDraft() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isValidDraft)
                if vm.nexusCustomModIds[mod.folderName] != nil {
                    Button(vm.L(L10n.Mods.nexusReset)) { resetDraft() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundColor(.red)
                }
            }
            Text(vm.L(L10n.Mods.nexusModIdHint))
                .font(.caption)
                .foregroundStyle(.secondary)
            fetchStatusRow
            // Uniquement quand rien n'est connu : chercher la fiche d'un mod
            // qui en déclare déjà une n'a pas d'objet.
            if vm.resolvedNexusModId(for: mod).isEmpty {
                NexusIdentitySection(vm: vm, mod: mod)
            }
        }
    }

    /// Compact status row shown below the mod id editor. Reflects the on-demand
    /// metadata fetch triggered by `commitDraft`: spinner while loading,
    /// category + latest version on success, or a localized error message.
    @ViewBuilder
    private var fetchStatusRow: some View {
        switch fetchStatus {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(vm.L(L10n.Mods.nexusFetching))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        case .success(let catName, let latest):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                    Text(vm.L(L10n.Mods.nexusFetchSuccess))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                if let cat = catName {
                    Text(String(format: vm.L(L10n.Mods.nexusFetchedCategory), cat))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.85))
                }
                if let v = latest {
                    Text(String(format: vm.L(L10n.Mods.nexusLatestVersion), v))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.85))
                }
            }
        case .noApiKey:
            Text(vm.L(L10n.Mods.nexusNoApiKey))
                .font(.system(size: 10))
                .foregroundColor(.orange)
        case .failed(let msg):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 10))
                Text(String(format: vm.L(L10n.Mods.nexusFetchFailed), msg))
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
        }
    }

    /// A Nexus mod id draft is valid when empty (clears the override) or a
    /// positive integer. Shared by `isValidDraft` (disables the Save button)
    /// and `commitDraft` (guards the actual save) so they can't disagree.
    private func isValidNexusIdDraft(_ trimmed: String) -> Bool {
        trimmed.isEmpty || (Int(trimmed).map { $0 > 0 } ?? false)
    }

    private var isValidDraft: Bool {
        isValidNexusIdDraft(nexusIdDraft.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func seedDraft() {
        // `resolved…`, not `effective…`: a pack header carries no id of its own
        // (it isn't a mod), so `effectiveNexusModId` returned "" and the field
        // looked empty even though the pack's children declare an id — which
        // the rest of this pane happily uses, since the header link and the
        // description both resolve through the children. The field was the only
        // place showing nothing.
        nexusIdDraft = vm.resolvedNexusModId(for: mod)
    }

    private func commitDraft() {
        let trimmed = nexusIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidNexusIdDraft(trimmed) else { return }
        vm.setCustomNexusModId(for: mod, modId: trimmed.isEmpty ? nil : trimmed)
        nexusIdDraft = vm.resolvedNexusModId(for: mod)
        // The description, changelog and dependency pane all key off the mod
        // id, but they were only ever loaded when navigating *into* the pane
        // (`viewingModDetail.didSet`). Entering an id therefore fetched the
        // metadata below while the description kept showing the local manifest
        // text — the one thing the user was trying to fix. Reload it here.
        vm.loadModDetail(for: mod)
        // When a mod id is saved, fetch its metadata (category + latest
        // version) from Nexus so the badge and update detection pick it up
        // immediately. Clearing the id resets the status to idle.
        let effectiveId = vm.resolvedNexusModId(for: mod)
        guard !effectiveId.isEmpty else { fetchStatus = .idle; return }
        fetchStatus = .loading
        vm.fetchMetadata(forNexusModId: effectiveId) { result in
            switch result {
            case .success(let version, let catId, _):
                let catName: String? = catId.flatMap { NexusCategory.from(id: $0) }
                    .map { $0.localizedName(vm.L) }
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
        // Same reason as in `commitDraft`: dropping a custom id changes which
        // Nexus mod this pane describes, so the description has to follow.
        vm.loadModDetail(for: mod)
        fetchStatus = .idle
    }

    // MARK: Dependencies

    /// Transitive dependency tree (see `DependencyTreeView`), replacing SP2's
    /// flat list. Empty/loaded states are handled inside the tree view.
    @ViewBuilder
    private var dependenciesSection: some View {
        DependencyTreeView(vm: vm, mod: mod)
    }

    // MARK: Error history

    // MARK: Traduction

    /// Ce que la liste ne peut pas dire, faute de place : **quoi** manque.
    ///
    /// Le taux seul ne distingue pas deux situations que le joueur ne vit pas
    /// de la même façon. Une clé **absente** laisse l'anglais s'afficher et le
    /// jeu tourne ; une clé **vide** n'affiche rien du tout, en silence. Un mod
    /// à 98 % dont les 2 % restants sont vides est plus cassé qu'un mod à 60 %.
    ///
    /// Masquée quand le mod ne livre pas de français : il n'y a alors rien à
    /// mesurer, et une section vide serait du bruit.
    @ViewBuilder
    private var translationSection: some View {
        // La section s'affiche aussi pour un mod **sans** français dès qu'une
        // sauvegarde en contient un, ou qu'un de ses fichiers ne sera jamais
        // lu par le jeu : c'est précisément le cas où l'utilisateur a quelque
        // chose à apprendre, français ou pas — un mod purement portugais avec
        // un `pt-BR.json` mort n'a pas besoin de français pour mériter la note.
        if mod.languages.contains("fr") || backupTranslation != nil || translationStaleness != nil
            || !unloadableLocaleFiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.L(L10n.Mods.translationSection))
                    .font(.system(size: 13, weight: .semibold))

                // Un défaut du mod, pas une panne de l'app : le jeu ne charge
                // que des codes de langue nus, donc un `pt-BR.json` sans
                // `pt.json` n'est jamais lu — sauf si un autre mod déclare
                // cette langue via `Data/AdditionalLanguages`, ce qu'aucun mod
                // du parc ne fait aujourd'hui mais que SMAPI permet.
                // `fileName` seul ne suffit pas comme identifiant : un mod à
                // plusieurs dossiers `i18n` peut porter le même nom fautif deux
                // fois avec un `expectedName` différent (base absente d'un
                // côté, déjà prise de l'autre) — l'indice de tableau est le
                // seul identifiant qui ne collisionne jamais ici.
                ForEach(Array(unloadableLocaleFiles.enumerated()), id: \.offset) { _, file in
                    if let expected = file.expectedName {
                        translationNote(String(format: vm.L(L10n.Mods.translationUnloadableExpected),
                                               file.fileName, expected),
                                        icon: "exclamationmark.triangle", color: .secondary)
                    } else {
                        translationNote(String(format: vm.L(L10n.Mods.translationUnloadableUnknown),
                                               file.fileName),
                                        icon: "exclamationmark.triangle", color: .secondary)
                    }
                }

                if let backup = backupTranslation {
                    translationNote(String(format: vm.L(L10n.Mods.translationInBackup),
                                           backup.modifiedAt.formatted(date: .abbreviated,
                                                                       time: .omitted)),
                                    icon: "clock.arrow.circlepath", color: .orange)
                }

                if let stale = translationStaleness {
                    // Le fait et ses deux dates, jamais un verdict : l'auteur a
                    // pu retoucher son fichier sans changer une phrase.
                    translationNote(
                        stale.note(sourceNewerFormat: vm.L(L10n.Mods.translationSourceNewer),
                                  sameDayFormat: vm.L(L10n.Mods.translationSourceNewerToday),
                                  oneDayFormat: vm.L(L10n.Mods.translationSourceNewerOneDay),
                                  dateText: stale.sourceDate.formatted(date: .abbreviated,
                                                                       time: .omitted)),
                        icon: "clock.badge.exclamationmark", color: .secondary)
                }
                if vm.outdatedKeyCount(for: mod) > 0 {
                    translationNote(String(format: vm.L(L10n.Mods.translationOutdatedKeys),
                                           vm.outdatedKeyCount(for: mod)),
                                    icon: "clock.badge.exclamationmark",
                                    color: DiffStateStyle.tint(.outdated))
                }

                if mod.languages.contains("fr"), let coverage = vm.frenchCoverageDetail(for: mod) {
                    TranslationProgressBar(percent: coverage.displayPercent)
                    Text(String(format: vm.L(L10n.Mods.translationCounts),
                                coverage.translated, coverage.total))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(.secondary)

                    // Les vides d'abord : c'est le seul défaut qui casse
                    // vraiment l'affichage, et il passerait inaperçu derrière un
                    // pourcentage flatteur.
                    if !coverage.empty.isEmpty {
                        translationNote(String(format: vm.L(L10n.Mods.translationEmpty),
                                               coverage.empty.count),
                                        icon: "exclamationmark.triangle.fill",
                                        color: .orange)
                    }
                    if !coverage.missing.isEmpty {
                        translationNote(String(format: vm.L(L10n.Mods.translationMissing),
                                               coverage.missing.count),
                                        icon: "text.badge.minus", color: .secondary)
                    }
                    // Seulement quand c'est significatif. Une valeur française
                    // identique à l'anglaise est le plus souvent légitime — un
                    // nom propre, un nombre — et la note s'afficherait sur 228
                    // des 424 mods traduits du parc, soit plus d'un sur deux :
                    // une note qui apparaît partout n'informe plus. Au-delà d'un
                    // cinquième des clés, en revanche, elle trahit une
                    // traduction recopiée : 12 mods, et ceux-là méritent l'œil.
                    if coverage.total > 0,
                       Double(coverage.identicalToSource.count) / Double(coverage.total) > 0.2 {
                        translationNote(String(format: vm.L(L10n.Mods.translationIdentical),
                                               coverage.identicalToSource.count),
                                        icon: "equal.circle", color: .secondary)
                    }
                    if !coverage.orphan.isEmpty {
                        translationNote(String(format: vm.L(L10n.Mods.translationOrphan),
                                               coverage.orphan.count),
                                        icon: "questionmark.circle", color: .secondary)
                    }
                } else if mod.languages.contains("fr") {
                    // Le calcul se fait en tâche de fond : le dire plutôt que
                    // de laisser un blanc qu'on prendrait pour une erreur.
                    Text(vm.L(L10n.Mods.translationPending))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func translationNote(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(color == .secondary ? .secondary : color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Errors and warnings this mod logged, per version — so a version can be
    /// compared against the one before it. Hidden entirely when the mod has
    /// never logged anything, which is the normal case.
    @ViewBuilder
    private var errorHistorySection: some View {
        let records = vm.modErrorHistory.history(for: mod.folderName)
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.L(L10n.Mods.errorHistory))
                    .font(.system(size: 13, weight: .semibold))
                Text(vm.L(L10n.Mods.errorHistoryHint))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(records, id: \.version) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(record.version)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                            // The mod's current version, for context: an old
                            // version's tally isn't what the player runs today.
                            if record.version == mod.version {
                                Text(vm.L(L10n.Mods.errorHistoryCurrent))
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(3)
                            }
                            Spacer()
                            if record.errorCount > 0 {
                                Label("\(record.errorCount)", systemImage: "xmark.octagon")
                                    .font(.system(size: 10))
                                    .foregroundColor(.red)
                            }
                            if record.warningCount > 0 {
                                Label("\(record.warningCount)", systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                        }
                        Text(record.lastSeen, style: .date)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        ForEach(record.samples, id: \.self) { sample in
                            Text(sample)
                                .font(.system(size: 10, design: .monospaced))
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

    /// Ce que **ce** mod subit en raccourcis, lu dans le rapport global du
    /// service de scan — le pendant fiche du rapport des Alertes système.
    ///
    /// Muette deux fois, par décision du brief : pas de rapport ⇒ rien
    /// (affirmer « aucun conflit » sans mesure serait mensonger ; le scan
    /// part quand le parc est connu, le cas est rare), et mod sans conflit
    /// ⇒ rien non plus (une ligne verte sur 900 fiches est du bruit —
    /// l'inverse du rapport global, où le vert répond à une question
    /// posée).
    ///
    /// En lecture seule : agir sur un conflit passe par le bouton
    /// « Réglages du mod » de `actionRow` (le chemin ouvert en tâche 8,
    /// même onglet) — la zone n'en ouvre pas un deuxième.
    @ViewBuilder
    private var keybindConflictsSection: some View {
        if let conflicts = keybindScanService.report?.conflicts(affecting: mod.folderName),
           !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text(vm.L(L10n.Keybinds.title))
                    .font(.system(size: 13, weight: .semibold))

                if !conflicts.collisions.isEmpty {
                    Text(String(format: vm.L(L10n.Keybinds.collisionsHeader),
                                conflicts.collisions.count))
                        .font(.system(size: 12, weight: .semibold))
                    ForEach(conflicts.collisions, id: \.combo) { collision in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collision.combo.display)
                                .font(.system(size: 13, weight: .medium))
                            ForEach(KeybindScanner.groupedUses(collision.uses)) { use in
                                // Hors de l'interpolation : une fermeture
                                // multiligne dans `\(...)` ne compile pas.
                                let paths = use.keyPaths
                                    .map { $0.joined(separator: ".") }
                                    .joined(separator: ", ")
                                Text("· \(use.modName) (\(paths))")
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }

                if !conflicts.gameConflicts.isEmpty {
                    // La réserve reste visible : c'est elle qui évite la
                    // fausse alerte chez qui a remappé ses touches (même
                    // raison que dans le rapport global).
                    Text(vm.L(L10n.Keybinds.gameCaveat))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    Text(String(format: vm.L(L10n.Keybinds.gameHeader),
                                conflicts.gameConflicts.count))
                        .font(.system(size: 12, weight: .semibold))
                    ForEach(conflicts.gameConflicts, id: \.control.name) { conflict in
                        // Même règle que chaque ligne de la zone : bornée à
                        // une ligne, tronquée au milieu — la fenêtre peut
                        // être étroite (ronde finale de revue).
                        HStack(spacing: AppDesign.Spacing.xs) {
                            Text(conflict.control.buttons.joined(separator: " / "))
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1).truncationMode(.middle)
                            Text(conflict.control.name)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }

    // MARK: Incompatibilités (tâche 9)

    /// Les incompatibilités que l'utilisateur a **déclarées** entre ce mod et
    /// un autre, avec de quoi les écarter sans changer d'écran.
    ///
    /// Pendant fiche du rapport global (`ModConflictSection`, tâche 8) —
    /// même principe que `keybindConflictsSection` juste au-dessus : donner
    /// un retour visible **ici**, sur l'écran où « Signaler » vient d'être
    /// cliqué. Sans lui, la seule confirmation serait de naviguer vers
    /// Alertes système — l'erreur qu'une fonctionnalité qui ne montre rien à
    /// l'endroit où on vient d'agir a déjà coûté deux fois dans ce dépôt.
    ///
    /// Ne montre que les paires **déclarées** : les conflits observés dans
    /// le journal ont leur propre écran d'écarte (`ModConflictSection`), et
    /// les dupliquer ici referait diverger la même correspondance conflit ↔
    /// paire que `vm.conflictPair(for:)` centralise déjà.
    @ViewBuilder
    private var declaredConflictsSection: some View {
        let pairs = vm.modConflictVerdicts.declared.filter { $0.contains(mod.folderName) }
        if !pairs.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text(vm.L(L10n.Conflicts.title))
                    .font(.system(size: 13, weight: .semibold))
                ForEach(pairs, id: \.self) { pair in
                    let otherFolder = pair.first == mod.folderName ? pair.second : pair.first
                    let otherName = vm.mods.flattenedMods.first(where: { $0.folderName == otherFolder })?.name
                        ?? otherFolder
                    HStack(spacing: AppDesign.Spacing.xs) {
                        Text("· \(otherName)")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(vm.L(L10n.Conflicts.dismissButton)) {
                            vm.dismissConflict(pair)
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .pointingHandCursor()
                    }
                }
            }
        }
    }

    /// Les mods candidats du sélecteur « Signaler » : le parc, aplati (un
    /// composant de pack a sa propre entrée, comme dans `ModConflictSection`
    /// et `conflictFolderNames`), moins ce mod lui-même — se signaler soi-même
    /// produirait une paire `(X, X)`, la même clé qu'un `withinOnePack` du
    /// journal, ce qui collision­nerait avec un cas déjà modélisé.
    private var reportConflictCandidates: [ModItem] {
        vm.mods.flattenedMods
            .filter { $0.folderName != mod.folderName }
            .alphabeticalListOrder
    }

    /// Le sélecteur « Signaler une incompatibilité… » : un mod installé, une
    /// note facultative. `reportConflictTarget` est réinitialisé à
    /// l'ouverture (voir le bouton) — jamais de brouillon fuyant d'un mod à
    /// l'autre, même patron que `nexusIdDraft`/`noteDraft`.
    private var reportConflictSheet: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(vm.L(L10n.Conflicts.reportButton))
                .font(.system(size: 15, weight: .bold))
            Picker(vm.L(L10n.Conflicts.pickMod), selection: $reportConflictTargetFolder) {
                Text("").tag(String?.none)
                ForEach(reportConflictCandidates, id: \.folderName) { candidate in
                    Text(candidate.name).tag(String?.some(candidate.folderName))
                }
            }
            TextField(vm.L(L10n.Conflicts.notePlaceholder), text: $reportConflictNote)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(vm.L(L10n.Saves.cancel)) { showReportConflict = false }
                Button(vm.L(L10n.Conflicts.reportConfirm)) {
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
        case 3:
            TranslationDiffView(vm: vm, mod: mod)
        case 2:
            dependenciesSection
        case 1:
            blocksView(isChangelog: true)
        default:
            // Description tab: pack contents (for a pack) + the category /
            // Nexus-id editors + the rendered description.
            VStack(alignment: .leading, spacing: 16) {
                if mod.isGroup { packContentsSection }
                settingsSection
                translationSection
                errorHistorySection
                keybindConflictsSection
                declaredConflictsSection
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
                    // Content genuinely absent (not loading): the mod has no
                    // description / no changelog for this version. Connectivity
                    // isn't tracked here, so a neutral per-tab message is more
                    // honest than an "offline" claim that would also fire for a
                    // perfectly online mod that simply ships no changelog.
                    ContentUnavailableView(
                        vm.L(isChangelog ? L10n.Mods.detailNoChangelog : L10n.Mods.detailNoDescription),
                        systemImage: "doc.plaintext"
                    )
                    .frame(maxWidth: .infinity, minHeight: 160)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if state.isStale {
                        stalenessHint
                    }
                    DescriptionBlocksView(blocks: blocks, vm: vm)

                    // **Ce que l'auteur dit de la compatibilité.** Mesuré sur 200
                    // fiches : 30 % en ouvrent une section, longue de 359
                    // caractères en médiane et 614 au maximum — d'où l'absence de
                    // repli, qui serait une cérémonie pour un paragraphe court.
                    // On affiche sa phrase, on n'en déduit aucune paire.
                    //
                    // Réservé à l'onglet Description : `blocks` porte le
                    // changelog quand `isChangelog` est vrai, et un titre
                    // « Compatibility » y désignerait une note de version, pas
                    // la déclaration de l'auteur sur la fiche.
                    if !isChangelog, let note = CompatibilityNote.find(in: blocks) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(vm.L(L10n.Mods.compatibilityNote))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            DescriptionBlocksView(blocks: note.blocks, vm: vm)
                        }
                        .padding(12)
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

    /// Discreet indicator shown above the content when it was served from
    /// cache/local fallback and a background refresh is in flight (or failed
    /// and was dropped in favor of keeping the last-known-good content).
    private var stalenessHint: some View {
        Label(vm.L(L10n.Mods.detailCached), systemImage: "arrow.triangle.2.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// La barre de progression de la traduction.
///
/// Sa place est ici et non dans la liste : la ligne de liste porte déjà le
/// globe, les langues et deux dates, là où la fiche a l'espace. La barre donne
/// la comparaison instantanée, le nombre juste à côté donne la précision —
/// deux rôles, deux éléments.
///
/// Le remplissage n'est jamais nul quand une seule clé est traduite : une barre
/// vide sur un travail commencé le nierait. Symétriquement, seul un travail
/// terminé remplit toute la largeur.
private struct TranslationProgressBar: View {
    let percent: Int

    private var tint: Color {
        percent >= 100 ? Color(red: 0.20, green: 0.62, blue: 0.34) : .orange
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(AppDesign.Opacity.light))
                Capsule()
                    .fill(tint)
                    .frame(width: max(geometry.size.width * CGFloat(percent) / 100,
                                      percent > 0 ? 3 : 0))
            }
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityLabel(Text("\(percent) %"))
    }
}


// MARK: - Suppléments d'un mod (A3-T4)

/// Ce qui se greffe sur un mod installé : bagages `ItemBags`, correctifs de
/// compatibilité, packs de contenu qui le citent.
///
/// **Ce que cette section ne peut pas faire, et le dit.** Nexus n'a pas de
/// notion de « supplément » : la recherche rend les mods dont le **titre**
/// contient celui-ci, et rien de plus. Deux mesures cadrent l'affichage :
/// - les résultats sont noyés de traductions — 8 des 26 premiers sur
///   « Sword and Sorcery » —, écartées par leur tag `Translation` ;
/// - un nom générique ramasse tout : « Content Patcher » rend **428**
///   résultats, dont 45 sur 50 ne sont pas des traductions. La liste est
///   plafonnée et le total annoncé, faute de quoi une poignée passerait pour
///   une exhaustivité.
///
/// Aucun bouton d'installation : le dépôt d'une archive sans manifeste
/// (**A1-T3**) s'en charge, et un compte gratuit ne peut de toute façon pas
/// télécharger depuis l'API. Le bouton mène à la page Nexus.
private struct SupplementSection: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem

    private var search: StarHubTHViewModel.SupplementSearch? {
        vm.supplementSearches[mod.folderName]
    }
    private var isSearching: Bool { vm.searchingSupplements.contains(mod.folderName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    vm.searchSupplements(for: mod)
                } label: {
                    Label(vm.L(L10n.Mods.searchShortSupplement),
                          systemImage: "puzzlepiece.extension")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSearching || !vm.hasNexusApiKey)
                .help(vm.hasNexusApiKey ? vm.L(L10n.Mods.supplementSearch)
                                        : vm.L(L10n.Mods.nexusNoApiKey))
                .pointingHandCursor()
                if isSearching {
                    ProgressView().controlSize(.small)
                    Text(vm.L(L10n.Mods.supplementSearching))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else if search != nil {
                    Button {
                        vm.dismissSupplementResults(for: mod)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(vm.L(L10n.Mods.searchClose))
                    .pointingHandCursor()
                } else if !vm.hasNexusApiKey {
                    Text(vm.L(L10n.Mods.nexusNoApiKey))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Ce que le mod porte déjà, avant toute recherche : le registre le
            // sait sans avoir à interroger Nexus.
            let installed = vm.addons(for: mod)
            if !installed.isEmpty || !(search?.alreadyInstalled.isEmpty ?? true) {
                Text(vm.L(L10n.Mods.installedSection))
                    .font(.system(size: 11, weight: .semibold))
                ForEach(installed, id: \.nexusName) { addon in installedRow(addon) }
                // Reconnus dans les résultats **et absents du registre** :
                // ceux-là seuls sont installés comme mods à part entière. Sans
                // ce tri, une greffe posée à la main s'affichait deux fois,
                // dont une sous une étiquette fausse.
                ForEach((search?.alreadyInstalled ?? []).filter { hit in
                    !installed.contains { known in
                        known.nexusModId == hit.modId
                            || NexusModSearch.namesMatch(known.nexusName, hit.name)
                    }
                }) { hit in asModRow(hit) }
            }
            // Rien tant qu'on n'a pas cherché : une liste vide affichée d'emblée
            // se lirait comme « aucun supplément n'existe », ce qu'on ne sait pas.
            if !isSearching, let search {
                // Les deux moitiés vides, pas seulement les propositions : sinon
                // « rien trouvé » s'affichait juste sous la liste de ce qui
                // venait d'être trouvé, et reconnu comme déjà installé.
                if search.hits.isEmpty, search.alreadyInstalled.isEmpty {
                    Text(vm.L(L10n.Mods.supplementNone))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text(String(format: vm.L(L10n.Mods.supplementFound), search.hits.count))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if search.isCapped {
                        Text(String(format: vm.L(L10n.Mods.supplementCapped),
                                    search.serverTotal, search.received))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    ForEach(search.hits.prefix(6)) { hit in candidate(hit) }
                    // La réserve reste sous les yeux : ce sont des titres qui
                    // citent ce mod, pas des suppléments établis.
                    Text(vm.L(L10n.Mods.supplementHint))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 4)
    }

    /// Une greffe posée par la feuille d'installation : le registre la connaît,
    /// donc elle se retire — et se rattache à Nexus pour être suivie.
    @ViewBuilder
    private func installedRow(_ addon: InstalledTranslation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(addon.nexusName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if addon.nexusModId == 0 {
                    Text(vm.L(L10n.Mods.noUpdateCheck))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if vm.addonUpdateAvailable(addon, for: mod) != nil {
                Text(vm.L(L10n.Mods.translationUpdateAvailable))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
            }
            let linkable = (search.map { $0.alreadyInstalled + $0.hits }) ?? []
            if addon.nexusModId == 0, !linkable.isEmpty {
                Menu(vm.L(L10n.Mods.linkToNexus)) {
                    ForEach(linkable.prefix(6)) { hit in
                        Button(hit.name) {
                            vm.linkToNexus(addon, hit: hit, isTranslation: false, for: mod)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.system(size: 10))
                .help(vm.L(L10n.Mods.linkToNexusHint))
            }
            Button(vm.L(L10n.Mods.addonRemove)) { vm.removeAddon(addon, from: mod) }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .font(.system(size: 11))
        }
        .padding(.vertical, 2)
    }

    /// Un supplément installé **comme un mod à part entière** : il vit dans
    /// `Mods/` avec son manifeste, se met à jour comme les autres, et n'a rien
    /// à faire dans le registre des greffes.
    @ViewBuilder
    private func asModRow(_ hit: NexusModSearch.Hit) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(vm.L(L10n.Mods.supplementAsMod))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func candidate(_ hit: NexusModSearch.Hit) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(String(format: vm.L(L10n.Mods.translationFromNexus), hit.uploader,
                            hit.updatedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                if let url = URL(string:
                    "https://www.nexusmods.com/stardewvalley/mods/\(hit.modId)?tab=files") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(vm.L(L10n.Mods.translationOpenNexus), systemImage: "arrow.up.right.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Traduction française (A3-T3)

/// Chercher, poser, suivre et retirer une traduction communautaire.
///
/// Une traduction n'est pas un mod : ce sont des fichiers déposés **dans** le
/// mod traduit. Elle n'apparaît donc nulle part ailleurs dans l'app, et c'est
/// ici — sur la fiche du mod concerné — qu'elle a un sens.
///
/// Absente des composants de pack : c'est le dossier de premier niveau qu'on
/// traduit, comme c'est lui qu'on met en pause ou qu'on sauvegarde.
private struct TranslationSection: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem

    private var installed: InstalledTranslation? { vm.translation(for: mod) }
    private var hits: [NexusModSearch.Hit] { vm.translationHits[mod.folderName] ?? [] }
    private var isSearching: Bool { vm.searchingTranslations.contains(mod.folderName) }
    private var isBusy: Bool { vm.busyTranslations.contains(mod.folderName) }
    private var update: NexusModSearch.Hit? { vm.translationUpdateAvailable(for: mod) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let installed {
                inPlace(installed)
            }
            searchRow
            // Rien tant qu'on n'a pas cherché : une liste vide affichée
            // d'emblée se lirait comme « aucune traduction n'existe », ce qu'on
            // ne sait pas encore.
            if !isSearching, vm.translationHits[mod.folderName] != nil {
                if hits.isEmpty {
                    Text(vm.L(L10n.Mods.translationNoneFound))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(hits.prefix(4)) { hit in candidate(hit) }
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func inPlace(_ installed: InstalledTranslation) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
            Text(vm.L(L10n.Mods.translationInPlace))
                .font(.system(size: 12, weight: .medium))
            Text(installed.nexusName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if update != nil {
                Text(vm.L(L10n.Mods.translationUpdateAvailable))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
            }
            Spacer()
            if let newer = update {
                Button(vm.L(L10n.Mods.translationUpdate)) {
                    vm.installTranslation(newer, into: mod)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy || vm.nexusDirectDownloadUnavailable)
                .help(vm.nexusDirectDownloadUnavailable ? vm.L(L10n.Mods.premiumOnlyHint) : "")
            }
            Button(vm.L(L10n.Mods.translationRemove)) { vm.removeTranslation(from: mod) }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .disabled(isBusy)
                .font(.system(size: 11))
        }
        // **Sans page Nexus rattachée, aucune mise à jour ne peut être vue.**
        // C'est le cas courant : sur un compte gratuit tout s'installe à la
        // main, donc sans identifiant. Le rattachement se fait donc ici, après
        // coup, en désignant l'entrée correspondante parmi les résultats.
        if installed.nexusModId == 0 {
            HStack(spacing: 6) {
                Text(vm.L(L10n.Mods.noUpdateCheck))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                // Les deux moitiés : le bon candidat est celui que le filtre a
                // retiré des propositions, et le menu serait vide sans lui.
                let candidates = (vm.translationInstalledHits[mod.folderName] ?? []) + hits
                if !candidates.isEmpty {
                    Menu(vm.L(L10n.Mods.linkToNexus)) {
                        ForEach(candidates.prefix(6)) { hit in
                            Button(hit.name) {
                                vm.linkToNexus(installed, hit: hit,
                                               isTranslation: true, for: mod)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.system(size: 10))
                    .help(vm.L(L10n.Mods.linkToNexusHint))
                }
            }
        }
    }

    @ViewBuilder
    private var searchRow: some View {
        HStack(spacing: 8) {
            Button {
                vm.searchTranslations(for: mod)
            } label: {
                Label(vm.L(L10n.Mods.searchShortTranslation),
                      systemImage: "globe.badge.chevron.backward")
                    .font(.system(size: 11))
            }
            // `.bordered` et non `.borderless` : les résultats en dessous
            // portent des boutons encadrés, et l'action qui les fait
            // apparaître ne doit pas ressembler à du texte.
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isSearching || isBusy || !vm.hasNexusApiKey)
            // **Dire pourquoi il est gris.** Un bouton désactivé et muet laisse
            // chercher la panne du mauvais côté.
            .help(vm.hasNexusApiKey ? vm.L(L10n.Mods.translationSearch)
                                    : vm.L(L10n.Mods.nexusNoApiKey))
            .pointingHandCursor()
            if isSearching {
                ProgressView().controlSize(.small)
                Text(vm.L(L10n.Mods.translationSearching))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else if isBusy {
                ProgressView().controlSize(.small)
            } else if vm.translationHits[mod.folderName] != nil {
                // Une liste de propositions se referme : elle a fait son
                // office, et la fiche a d'autres choses à montrer.
                Button {
                    vm.dismissTranslationResults(for: mod)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(vm.L(L10n.Mods.searchClose))
                .pointingHandCursor()
            } else if !vm.hasNexusApiKey {
                // Écrit, pas seulement en infobulle : AppKit ne garantit pas
                // l'infobulle d'un contrôle désactivé, et c'est précisément
                // quand il est gris qu'il faut dire pourquoi.
                Text(vm.L(L10n.Mods.nexusNoApiKey))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Une traduction proposée : son titre, son auteur, sa date, et le geste.
    ///
    /// La date est celle de Nexus, la même qui décide qu'une mise à jour
    /// existe — les numéros de version ne servent à rien ici, beaucoup de
    /// traducteurs reprennent celui du mod traduit.
    @ViewBuilder
    private func candidate(_ hit: NexusModSearch.Hit) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(String(format: vm.L(L10n.Mods.translationFromNexus), hit.uploader,
                            hit.updatedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            // Même paire de boutons que les mises à jour de mods : le
            // téléchargement direct, qui demande un compte Premium, et la
            // sortie vers Nexus. Elle ouvre l'onglet **Files**, où vit le
            // téléchargement gratuit par gestionnaire de mods — la page
            // d'accueil du mod, elle, ne le porte pas.
            Button {
                if let url = URL(string:
                    "https://www.nexusmods.com/stardewvalley/mods/\(hit.modId)?tab=files") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(vm.L(L10n.Mods.translationOpenNexus), systemImage: "arrow.up.right.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()

            Button(vm.L(installed?.nexusModId == hit.modId
                        ? L10n.Mods.translationUpdate : L10n.Mods.translationInstall)) {
                vm.installTranslation(hit, into: mod)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            // Même règle que la page des mises à jour : sans compte premium,
            // l'API refuse le lien direct, et c'est le bouton Nexus qui prend
            // le relais.
            .disabled(isBusy || vm.nexusDirectDownloadUnavailable)
            .help(vm.nexusDirectDownloadUnavailable ? vm.L(L10n.Mods.premiumOnlyHint) : "")
        }
        .padding(.vertical, 2)
    }
}


/// Retrouver la fiche Nexus d'un mod qui n'en déclare aucune.
///
/// **Ce que la mesure impose à cet écran.** Sur les 83 mods du parc encore sans
/// identifiant, la recherche par nom a été réellement exécutée le 2026-08-26 :
/// 55 ne rendent rien, 23 rendent des candidats — dont 61 % de traductions,
/// écartées en amont — et 18 n'en ont plus qu'un seul. Deux mods sur trois
/// verront donc « aucun résultat », et c'est une réponse, pas une panne : elle
/// est écrite en toutes lettres, sans quoi le bouton passerait pour cassé.
///
/// **Rien n'est relié d'autorité**, même quand un seul candidat subsiste et que
/// l'auteur concorde : deux des 18 candidats uniques mesurés portaient un auteur
/// sans rapport. Chaque ligne offre d'abord d'ouvrir la fiche — vérifier avant
/// de désigner — et l'adoption reste un geste.
private struct NexusIdentitySection: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem

    private var search: StarHubTHViewModel.IdentitySearch? {
        vm.identitySearches[mod.folderName]
    }
    private var isSearching: Bool { vm.searchingIdentity.contains(mod.folderName) }
    /// Le pack qui contient ce mod, quand il en est un composant.
    private var packName: String {
        String(mod.folderName.split(separator: "/").first ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    vm.searchNexusIdentity(for: mod)
                } label: {
                    Label(vm.L(L10n.Mods.nexusIdentityShort), systemImage: "magnifyingglass")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSearching || !vm.hasNexusApiKey)
                .help(vm.hasNexusApiKey ? vm.L(L10n.Mods.nexusIdentitySearch)
                                        : vm.L(L10n.Mods.nexusNoApiKey))
                .pointingHandCursor()
                if isSearching {
                    ProgressView().controlSize(.small)
                    Text(vm.L(L10n.Mods.supplementSearching))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else if search != nil {
                    Button {
                        vm.dismissIdentityResults(for: mod)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(vm.L(L10n.Mods.searchClose))
                    .pointingHandCursor()
                } else if !vm.hasNexusApiKey {
                    // Écrit, pas seulement en infobulle : AppKit ne garantit
                    // pas l'infobulle d'un contrôle désactivé.
                    Text(vm.L(L10n.Mods.nexusNoApiKey))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Dit **avant** le clic, pas après : mesuré, les 20 composants de
            // pack sans identifiant n'ont rendu aucun résultat. Le bouton reste
            // ouvert — un composant peut avoir sa propre page — mais on annonce
            // où chercher pour de bon.
            if mod.isPackComponent, !packName.isEmpty {
                Text(String(format: vm.L(L10n.Mods.nexusIdentityComponent), packName))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isSearching, let search {
                if search.candidates.isEmpty {
                    Text(vm.L(L10n.Mods.nexusIdentityNone))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(format: vm.L(L10n.Mods.nexusIdentityFound),
                                search.candidates.count))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if search.isCapped {
                        Text(String(format: vm.L(L10n.Mods.supplementCapped),
                                    search.serverTotal, search.received))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    ForEach(search.candidates.prefix(6)) { candidate in row(candidate) }
                    Text(vm.L(L10n.Mods.nexusIdentityHint))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func row(_ candidate: NexusModSearch.IdentityCandidate) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(candidate.hit.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if candidate.authorMatches {
                        Text(vm.L(L10n.Mods.nexusIdentitySameAuthor))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Text(String(format: vm.L(L10n.Mods.translationFromNexus), candidate.hit.uploader,
                            candidate.hit.updatedAt.map {
                                $0.formatted(date: .abbreviated, time: .omitted)
                            } ?? "—"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            // Vérifier d'abord : la fiche s'ouvre, et c'est elle qui tranche.
            Button {
                if let url = URL(string:
                    "https://www.nexusmods.com/stardewvalley/mods/\(candidate.hit.modId)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(vm.L(L10n.Mods.translationOpenNexus))
            .pointingHandCursor()
            Button(vm.L(L10n.Mods.nexusIdentityAdopt)) {
                vm.adoptNexusIdentity(candidate, for: mod)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .fixedSize()
            .pointingHandCursor()
        }
        .padding(.vertical, 2)
    }
}
