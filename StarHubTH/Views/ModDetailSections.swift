import SwiftUI

// Sections de la fiche mod (P8, 2026-09-14), déplacées de
// `ModDetailView` ; `private` levé.

/// Barre de progression de la traduction, sur la fiche (la ligne de liste
/// n'a pas la place). Jamais vide dès une clé traduite ; pleine seulement
/// quand tout l'est.
struct TranslationProgressBar: View {
    let percent: Int

    private var tint: Color {
        percent >= 100 ? AppDesign.Color.success : .orange
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

/// Ce qui se greffe sur un mod (`ItemBags`, correctifs, packs qui le
/// citent). Nexus ne connaît que les **titres** qui contiennent celui-ci :
/// traductions écartées par tag, liste plafonnée **et total annoncé**
/// (« Content Patcher » : 428). Pas d'installation ici (A1-T3) : le bouton
/// mène à Nexus.
struct SupplementSection: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem

    private var search: SupplementSearch? {
        vm.translationHub.supplementSearches[mod.folderName]
    }
    private var isSearching: Bool { vm.translationHub.isSupplementsSearching(mod.folderName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    vm.searchSupplements(for: mod)
                } label: {
                    Label(localization.L(L10n.Mods.searchShortSupplement),
                          systemImage: "puzzlepiece.extension")
                        .font(AppDesign.Font.footnote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSearching || !vm.hasNexusApiKey)
                .help(vm.hasNexusApiKey ? localization.L(L10n.Mods.supplementSearch)
                                        : localization.L(L10n.Mods.nexusNoApiKey))
                .pointingHandCursor()
                if isSearching {
                    ProgressView().controlSize(.small)
                    Text(localization.L(L10n.Mods.supplementSearching))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                } else if search != nil {
                    Button {
                        vm.dismissSupplementResults(for: mod)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .iconHelp(localization.L(L10n.Mods.searchClose))
                    .pointingHandCursor()
                } else if !vm.hasNexusApiKey {
                    Text(localization.L(L10n.Mods.nexusNoApiKey))
                        .font(AppDesign.Font.iconXS)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Ce que le registre connaît déjà, sans Nexus.
            let installed = vm.addons(for: mod)
            if !installed.isEmpty || !(search?.alreadyInstalled.isEmpty ?? true) {
                Text(localization.L(L10n.Mods.installedSection))
                    .font(AppDesign.Font.footnote(.semibold))
                ForEach(installed, id: \.nexusName) { addon in installedRow(addon) }
                // Reconnus **et absents du registre** : sinon une greffe s'affichait
                // deux fois.
                ForEach((search?.alreadyInstalled ?? []).filter { hit in
                    !installed.contains { known in
                        known.nexusModId == hit.modId
                            || NexusModSearch.namesMatch(known.nexusName, hit.name)
                    }
                }) { hit in asModRow(hit) }
            }
            // Rien avant la recherche : vide se lirait « aucun supplément ».
            if !isSearching, let search {
                // Les deux moitiés vides : sinon « rien trouvé » sous ce qui était trouvé.
                if search.hits.isEmpty, search.alreadyInstalled.isEmpty {
                    Text(localization.L(L10n.Mods.supplementNone))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Text(String(format: localization.L(L10n.Mods.supplementFound), search.hits.count))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                    if search.isCapped {
                        Text(String(format: localization.L(L10n.Mods.supplementCapped),
                                    search.serverTotal, search.received))
                            .font(AppDesign.Font.iconXS)
                            .foregroundColor(.secondary)
                    }
                    ForEach(search.hits.prefix(6)) { hit in candidate(hit) }
                    // Réserve visible : titres qui citent le mod, pas suppléments établis.
                    Text(localization.L(L10n.Mods.supplementHint))
                        .font(AppDesign.Font.iconXS)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 4)
    }

    /// Greffe posée par la feuille : retirable et rattachable à Nexus.
    @ViewBuilder
    private func installedRow(_ addon: InstalledTranslation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(AppDesign.Font.iconXS)
                .foregroundColor(AppDesign.Color.installed)
            VStack(alignment: .leading, spacing: 1) {
                Text(addon.nexusName)
                    .font(AppDesign.Font.footnote(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if addon.nexusModId == 0 {
                    Text(localization.L(L10n.Mods.noUpdateCheck))
                        .font(AppDesign.Font.iconXS)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if vm.addonUpdateAvailable(addon, for: mod) != nil {
                Text(localization.L(L10n.Mods.translationUpdateAvailable))
                    .font(AppDesign.Font.iconXS(.semibold))
                    .foregroundColor(.orange)
            }
            let linkable = (search.map { $0.alreadyInstalled + $0.hits }) ?? []
            if addon.nexusModId == 0, !linkable.isEmpty {
                Menu(localization.L(L10n.Mods.linkToNexus)) {
                    ForEach(linkable.prefix(6)) { hit in
                        Button(hit.name) {
                            vm.linkToNexus(addon, hit: hit, isTranslation: false, for: mod)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(AppDesign.Font.iconXS)
                .help(localization.L(L10n.Mods.linkToNexusHint))
            }
            Button(localization.L(L10n.Mods.addonRemove), role: .destructive) { vm.removeAddon(addon, from: mod) }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .font(AppDesign.Font.footnote)
        }
        .padding(.vertical, 2)
    }

    /// Supplément installé **comme mod** : hors registre des greffes.
    @ViewBuilder
    private func asModRow(_ hit: NexusModSearch.Hit) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(AppDesign.Font.iconXS)
                .foregroundColor(AppDesign.Color.installed)
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.name)
                    .font(AppDesign.Font.footnote(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(localization.L(L10n.Mods.supplementAsMod))
                    .font(AppDesign.Font.iconXS)
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
                    .font(AppDesign.Font.footnote(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(String(format: localization.L(L10n.Mods.translationFromNexus), hit.uploader,
                            hit.updatedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                if let url = URL(string:
                    "https://www.nexusmods.com/stardewvalley/mods/\(hit.modId)?tab=files") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(localization.L(L10n.Mods.translationOpenNexus), systemImage: "arrow.up.right.square")
                    .font(AppDesign.Font.footnote)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Traduction française (A3-T3)

/// Chercher, poser, suivre et retirer une traduction communautaire —
/// fichiers déposés **dans** le mod, d'où sa place sur la fiche. Absente
/// des composants de pack : on traduit le dossier de premier niveau.
struct TranslationSection: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem
    @State private var showDeclareSheet = false

    private var installed: InstalledTranslation? { vm.translation(for: mod) }
    private var hits: [NexusModSearch.Hit] { vm.translationHits[mod.folderName] ?? [] }
    private var isSearching: Bool { vm.searchingTranslations.contains(mod.folderName) }
    private var isBusy: Bool { vm.busyTranslations.contains(mod.folderName) }
    private var update: NexusModSearch.Hit? { vm.translationUpdateAvailable(for: mod) }
    /// A3-T6 — bandeau seulement si `installed` est `nil`.
    private var showUndeclaredBanner: Bool {
        installed == nil && vm.hasUndeclaredFrenchTranslation(for: mod)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let installed {
                inPlace(installed)
            } else if let declared = vm.declaredTranslation(for: mod) {
                declaredInPlace(declared)
            }
            if showUndeclaredBanner {
                undeclaredBanner
            }
            searchRow
            // Rien avant la recherche : vide se lirait « aucune traduction ».
            if !isSearching, vm.translationHits[mod.folderName] != nil {
                if hits.isEmpty {
                    Text(localization.L(L10n.Mods.translationNoneFound))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(hits.prefix(4)) { hit in candidate(hit) }
                }
            }
        }
        .padding(.top, 4)
        .sheet(isPresented: $showDeclareSheet) {
            declareSheet
        }
    }

    /// Variante déclarée : « Retirer » n'enlève que la ligne du registre
    /// (l'UI le dit).
    @ViewBuilder
    private func declaredInPlace(_ declared: DeclaredTranslation) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.rectangle.badge.checkmark")
                .font(AppDesign.Font.iconXS)
                .foregroundColor(.blue)
            Text(localization.L(L10n.Mods.translationDeclared))
                .font(AppDesign.Font.caption(.medium))
            Text(declared.nexusName)
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(localization.L(L10n.Mods.translationUndeclare), role: .destructive) {
                vm.undeclareTranslation(for: mod)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
            .font(AppDesign.Font.footnote)
            .help(localization.L(L10n.Mods.translationUndeclareHint))
        }
    }

    /// Bandeau « origine inconnue » : recherche Nexus ou déclaration manuelle.
    /// Rien d'office : `birthtime`/`mtime` mentent sur un dossier copié.
    @ViewBuilder
    private var undeclaredBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "questionmark.circle")
                .foregroundColor(.orange)
                .font(AppDesign.Font.caption)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.L(L10n.Mods.translationUndeclared))
                    .font(AppDesign.Font.caption(.medium))
                Text(localization.L(L10n.Mods.translationUndeclaredHint))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button(localization.L(L10n.Mods.translationDeclare)) {
                        showDeclareSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button(localization.L(L10n.Mods.translationOpenNexus)) {
                        vm.searchTranslations(for: mod)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(isBusy)
                }
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(AppDesignCore.Radius.sm)
    }

    /// Déclaration manuelle : id, nom, version ; date Nexus laissée `nil`.
    @State private var declareModId: String = ""
    @State private var declareName: String = ""
    @State private var declareVersion: String = ""

    @ViewBuilder
    private var declareSheet: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(L10n.Mods.translationDeclareTitle))
                .font(.system(size: AppDesign.Font.scaled(15), weight: .bold))
            Text(localization.L(L10n.Mods.translationDeclareExplainer))
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(localization.L(L10n.Mods.translationDeclareNexusId), text: $declareModId)
                .textFieldStyle(.roundedBorder)
            TextField(localization.L(L10n.Mods.translationDeclareName), text: $declareName)
                .textFieldStyle(.roundedBorder)
            TextField(localization.L(L10n.Mods.translationDeclareVersion), text: $declareVersion)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(localization.L(L10n.Saves.cancel)) { showDeclareSheet = false }
                Button(localization.L(L10n.Mods.translationDeclareConfirm)) {
                    if let modId = Int(declareModId.trimmingCharacters(in: .whitespaces)),
                       modId > 0 {
                        let version = declareVersion.trimmingCharacters(in: .whitespaces)
                        vm.declareTranslation(
                            modId: modId,
                            name: declareName.trimmingCharacters(in: .whitespaces),
                            version: version.isEmpty ? nil : version,
                            updatedAt: nil,
                            for: mod)
                    }
                    showDeclareSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(Int(declareModId.trimmingCharacters(in: .whitespaces)) ?? 0 <= 0
                          || declareName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @ViewBuilder
    private func inPlace(_ installed: InstalledTranslation) -> some View {
        SplitRow(spacing: 6) { // ~720 pt en FR avec une mise à jour : repli sous 512
            Image(systemName: "checkmark.seal.fill")
                .font(AppDesign.Font.iconXS)
                .foregroundColor(AppDesign.Color.installed)
            Text(localization.L(L10n.Mods.translationInPlace))
                .font(AppDesign.Font.caption(.medium))
            Text(installed.nexusName)
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if update != nil {
                Text(localization.L(L10n.Mods.translationUpdateAvailable))
                    .font(AppDesign.Font.iconXS(.semibold))
                    .foregroundColor(.orange)
            }
        } trailing: {
            if let newer = update {
                Button(localization.L(L10n.Mods.translationUpdate)) {
                    vm.installTranslation(newer, into: mod)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy || vm.nexusDirectDownloadUnavailable)
                .help(vm.nexusDirectDownloadUnavailable ? localization.L(L10n.Mods.premiumOnlyHint) : "")
            }
            Button(localization.L(L10n.Mods.translationRemove), role: .destructive) { vm.removeTranslation(from: mod) }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .disabled(isBusy)
                .font(AppDesign.Font.footnote)
        }
        // **Sans page Nexus, aucune mise à jour visible** (compte gratuit) :
        // rattachement ici, parmi les résultats.
        if installed.nexusModId == 0 {
            HStack(spacing: 6) {
                Text(localization.L(L10n.Mods.noUpdateCheck))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
                // Les deux moitiés : le bon candidat a été retiré des propositions.
                let candidates = (vm.translationInstalledHits[mod.folderName] ?? []) + hits
                if !candidates.isEmpty {
                    Menu(localization.L(L10n.Mods.linkToNexus)) {
                        ForEach(candidates.prefix(6)) { hit in
                            Button(hit.name) {
                                vm.linkToNexus(installed, hit: hit,
                                               isTranslation: true, for: mod)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(AppDesign.Font.iconXS)
                    .help(localization.L(L10n.Mods.linkToNexusHint))
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
                Label(localization.L(L10n.Mods.searchShortTranslation),
                      systemImage: "globe.badge.chevron.backward")
                    .font(AppDesign.Font.footnote)
            }
            // `.bordered` : l'action ne doit pas ressembler à du texte.
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isSearching || isBusy || !vm.hasNexusApiKey)
            // **Dire pourquoi il est gris.**
            .help(vm.hasNexusApiKey ? localization.L(L10n.Mods.translationSearch)
                                    : localization.L(L10n.Mods.nexusNoApiKey))
            .pointingHandCursor()
            if isSearching {
                ProgressView().controlSize(.small)
                Text(localization.L(L10n.Mods.translationSearching))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
            } else if isBusy {
                ProgressView().controlSize(.small)
            } else if vm.translationHits[mod.folderName] != nil {
                // La liste se referme, son office fait.
                Button {
                    vm.dismissTranslationResults(for: mod)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .iconHelp(localization.L(L10n.Mods.searchClose))
                .pointingHandCursor()
            } else if !vm.hasNexusApiKey {
                // Écrit, pas seulement en infobulle (non garantie sur un contrôle
                // désactivé).
                Text(localization.L(L10n.Mods.nexusNoApiKey))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Traduction proposée : titre, auteur, date Nexus (celle qui décide des
    /// mises à jour ; les numéros ne servent à rien).
    @ViewBuilder
    private func candidate(_ hit: NexusModSearch.Hit) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.name)
                    .font(AppDesign.Font.footnote(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(String(format: localization.L(L10n.Mods.translationFromNexus), hit.uploader,
                            hit.updatedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
            }
            Spacer()
            // Même paire que les mises à jour : direct (Premium) et Nexus, onglet
            // **Files** (téléchargement gratuit par gestionnaire).
            Button {
                if let url = URL(string:
                    "https://www.nexusmods.com/stardewvalley/mods/\(hit.modId)?tab=files") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(localization.L(L10n.Mods.translationOpenNexus), systemImage: "arrow.up.right.square")
                    .font(AppDesign.Font.footnote)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()

            Button(localization.L(installed?.nexusModId == hit.modId
                        ? L10n.Mods.translationUpdate : L10n.Mods.translationInstall)) {
                vm.installTranslation(hit, into: mod)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            // Sans Premium, lien direct refusé : le bouton Nexus relaie.
            .disabled(isBusy || vm.nexusDirectDownloadUnavailable)
            .help(vm.nexusDirectDownloadUnavailable ? localization.L(L10n.Mods.premiumOnlyHint) : "")
        }
        .padding(.vertical, 2)
    }
}


/// Retrouver la fiche Nexus d'un mod sans id (83 mesurés le 2026-08-26 :
/// 55 sans résultat) : « aucun résultat » est une réponse, écrite en
/// toutes lettres. **Rien relié d'autorité** (2 candidats uniques sur 18
/// d'un auteur sans rapport) : ouvrir la fiche d'abord, adopter ensuite.
struct NexusIdentitySection: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem

    private var search: IdentitySearch? {
        vm.translationHub.identitySearches[mod.folderName]
    }
    private var isSearching: Bool { vm.translationHub.isIdentitySearching(mod.folderName) }
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
                    Label(localization.L(L10n.Mods.nexusIdentityShort), systemImage: "magnifyingglass")
                        .font(AppDesign.Font.footnote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSearching || !vm.hasNexusApiKey)
                .help(vm.hasNexusApiKey ? localization.L(L10n.Mods.nexusIdentitySearch)
                                        : localization.L(L10n.Mods.nexusNoApiKey))
                .pointingHandCursor()
                if isSearching {
                    ProgressView().controlSize(.small)
                    Text(localization.L(L10n.Mods.supplementSearching))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                } else if search != nil {
                    Button {
                        vm.dismissIdentityResults(for: mod)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .iconHelp(localization.L(L10n.Mods.searchClose))
                    .pointingHandCursor()
                } else if !vm.hasNexusApiKey {
                    // Écrit, pas seulement en infobulle.
                    Text(localization.L(L10n.Mods.nexusNoApiKey))
                        .font(AppDesign.Font.iconXS)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Dit **avant** le clic : les 20 composants de pack sans id n'ont rien
            // rendu ; on annonce où chercher.
            if mod.isPackComponent, !packName.isEmpty {
                Text(String(format: localization.L(L10n.Mods.nexusIdentityComponent), packName))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isSearching, let search {
                if search.candidates.isEmpty {
                    Text(localization.L(L10n.Mods.nexusIdentityNone))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(format: localization.L(L10n.Mods.nexusIdentityFound),
                                search.candidates.count))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                    if search.isCapped {
                        Text(String(format: localization.L(L10n.Mods.supplementCapped),
                                    search.serverTotal, search.received))
                            .font(AppDesign.Font.iconXS)
                            .foregroundColor(.secondary)
                    }
                    ForEach(search.candidates.prefix(6)) { candidate in row(candidate) }
                    Text(localization.L(L10n.Mods.nexusIdentityHint))
                        .font(AppDesign.Font.iconXS)
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
                        .font(AppDesign.Font.footnote(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if candidate.authorMatches {
                        Text(localization.L(L10n.Mods.nexusIdentitySameAuthor))
                            .font(AppDesign.Font.iconXXS(.semibold))
                            .foregroundColor(.green)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Text(String(format: localization.L(L10n.Mods.translationFromNexus), candidate.hit.uploader,
                            candidate.hit.updatedAt.map {
                                $0.formatted(date: .abbreviated, time: .omitted)
                            } ?? "—"))
                    .font(AppDesign.Font.iconXS)
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
                    .font(AppDesign.Font.footnote)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .iconHelp(localization.L(L10n.Mods.translationOpenNexus))
            .pointingHandCursor()
            Button(localization.L(L10n.Mods.nexusIdentityAdopt)) {
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
