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
    @State private var selectedTab = 0

    /// Draft text for the Nexus mod id field. Seeded once in `.onAppear` from
    /// the mod's effective id; safe to seed unconditionally (no "already
    /// seeded" guard needed) because the `.id(mod.folderName)` at the call
    /// site gives this view a fresh instance — and therefore a fresh
    /// `@State` — per mod.
    @State private var nexusIdDraft: String = ""

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
        .onAppear { seedDraft() }
        .task {
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
                                vm.toggleMod(live) { localIsOn = nil }
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
                    metaLine(icon: "clock.arrow.circlepath",
                             label: vm.L(L10n.Mods.detailUpdated),
                             text: updated.formatted(date: .abbreviated, time: .omitted))
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
            }
            .padding(.vertical, 4)
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
