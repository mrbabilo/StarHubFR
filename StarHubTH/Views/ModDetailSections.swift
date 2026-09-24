import SwiftUI

// Les sections de la fiche mod — P8, geste B (cadrage 2026-09-14) :
// types inchangés, déplacés du fichier de `ModDetailView`, `private`
// levé car instanciés par le body qui reste dans l'autre fichier.
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
                        .font(.system(size: 11))
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
                    .help(localization.L(L10n.Mods.searchClose))
                    .pointingHandCursor()
                } else if !vm.hasNexusApiKey {
                    Text(localization.L(L10n.Mods.nexusNoApiKey))
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
                Text(localization.L(L10n.Mods.installedSection))
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
                    Text(localization.L(L10n.Mods.supplementNone))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text(String(format: localization.L(L10n.Mods.supplementFound), search.hits.count))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if search.isCapped {
                        Text(String(format: localization.L(L10n.Mods.supplementCapped),
                                    search.serverTotal, search.received))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    ForEach(search.hits.prefix(6)) { hit in candidate(hit) }
                    // La réserve reste sous les yeux : ce sont des titres qui
                    // citent ce mod, pas des suppléments établis.
                    Text(localization.L(L10n.Mods.supplementHint))
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
                .foregroundColor(AppDesign.Color.installed)
            VStack(alignment: .leading, spacing: 1) {
                Text(addon.nexusName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if addon.nexusModId == 0 {
                    Text(localization.L(L10n.Mods.noUpdateCheck))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if vm.addonUpdateAvailable(addon, for: mod) != nil {
                Text(localization.L(L10n.Mods.translationUpdateAvailable))
                    .font(.system(size: 10, weight: .semibold))
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
                .font(.system(size: 10))
                .help(localization.L(L10n.Mods.linkToNexusHint))
            }
            Button(localization.L(L10n.Mods.addonRemove), role: .destructive) { vm.removeAddon(addon, from: mod) }
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
                .foregroundColor(AppDesign.Color.installed)
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(localization.L(L10n.Mods.supplementAsMod))
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
                Text(String(format: localization.L(L10n.Mods.translationFromNexus), hit.uploader,
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
                Label(localization.L(L10n.Mods.translationOpenNexus), systemImage: "arrow.up.right.square")
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
    /// A3-T6 — traduction sur disque mais inconnue du registre. Le bandeau
    /// n'apparaît **que** quand `installed` est `nil` : une traduction déjà
    /// suivie par l'app n'a rien à déclarer.
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
            // Rien tant qu'on n'a pas cherché : une liste vide affichée
            // d'emblée se lirait comme « aucune traduction n'existe », ce qu'on
            // ne sait pas encore.
            if !isSearching, vm.translationHits[mod.folderName] != nil {
                if hits.isEmpty {
                    Text(localization.L(L10n.Mods.translationNoneFound))
                        .font(.system(size: 11))
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

    /// Variante « déclarée à la main ». Pas d'install, pas de fichiers
    /// connus : un clic sur « Retirer » n'enlève rien du disque, il retire
    /// juste la ligne du registre (et le bandeau « origine inconnue »
    /// réapparaît). L'UI le dit.
    @ViewBuilder
    private func declaredInPlace(_ declared: DeclaredTranslation) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.rectangle.badge.checkmark")
                .font(.system(size: 10))
                .foregroundColor(.blue)
            Text(localization.L(L10n.Mods.translationDeclared))
                .font(.system(size: 12, weight: .medium))
            Text(declared.nexusName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(localization.L(L10n.Mods.translationUndeclare), role: .destructive) {
                vm.undeclareTranslation(for: mod)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
            .font(.system(size: 11))
            .help(localization.L(L10n.Mods.translationUndeclareHint))
        }
    }

    /// Bandeau « traduction présente, origine inconnue ». Deux sorties :
    /// **recherche Nexus** (bouton à gauche, qui remplit la même barre que
    /// `searchRow`), et **déclaration manuelle** (à droite, qui ouvre la
    /// sheet). Aucune ne s'inscrit d'office — `birthtime` et `mtime` mentent
    /// sur un dossier copié ou restauré, et deviner une provenance dans un
    /// registre qui sert justement à ne pas deviner vaudrait moins que pas
    /// de provenance du tout.
    @ViewBuilder
    private var undeclaredBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "questionmark.circle")
                .foregroundColor(.orange)
                .font(.system(size: 12))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.L(L10n.Mods.translationUndeclared))
                    .font(.system(size: 12, weight: .medium))
                Text(localization.L(L10n.Mods.translationUndeclaredHint))
                    .font(.system(size: 10))
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

    /// Sheet de déclaration manuelle : `nexusModId` + nom + version (option).
    /// La date Nexus reste à `nil` : on ne la demande pas à l'utilisateur, et
    /// une recherche dédiée peut la remplir après coup.
    @State private var declareModId: String = ""
    @State private var declareName: String = ""
    @State private var declareVersion: String = ""

    @ViewBuilder
    private var declareSheet: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(L10n.Mods.translationDeclareTitle))
                .font(.system(size: 15, weight: .bold))
            Text(localization.L(L10n.Mods.translationDeclareExplainer))
                .font(.system(size: 11))
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
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10))
                .foregroundColor(AppDesign.Color.installed)
            Text(localization.L(L10n.Mods.translationInPlace))
                .font(.system(size: 12, weight: .medium))
            Text(installed.nexusName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if update != nil {
                Text(localization.L(L10n.Mods.translationUpdateAvailable))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
            }
            Spacer()
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
                .font(.system(size: 11))
        }
        // **Sans page Nexus rattachée, aucune mise à jour ne peut être vue.**
        // C'est le cas courant : sur un compte gratuit tout s'installe à la
        // main, donc sans identifiant. Le rattachement se fait donc ici, après
        // coup, en désignant l'entrée correspondante parmi les résultats.
        if installed.nexusModId == 0 {
            HStack(spacing: 6) {
                Text(localization.L(L10n.Mods.noUpdateCheck))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                // Les deux moitiés : le bon candidat est celui que le filtre a
                // retiré des propositions, et le menu serait vide sans lui.
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
                    .font(.system(size: 10))
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
            .help(vm.hasNexusApiKey ? localization.L(L10n.Mods.translationSearch)
                                    : localization.L(L10n.Mods.nexusNoApiKey))
            .pointingHandCursor()
            if isSearching {
                ProgressView().controlSize(.small)
                Text(localization.L(L10n.Mods.translationSearching))
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
                .help(localization.L(L10n.Mods.searchClose))
                .pointingHandCursor()
            } else if !vm.hasNexusApiKey {
                // Écrit, pas seulement en infobulle : AppKit ne garantit pas
                // l'infobulle d'un contrôle désactivé, et c'est précisément
                // quand il est gris qu'il faut dire pourquoi.
                Text(localization.L(L10n.Mods.nexusNoApiKey))
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
                Text(String(format: localization.L(L10n.Mods.translationFromNexus), hit.uploader,
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
                Label(localization.L(L10n.Mods.translationOpenNexus), systemImage: "arrow.up.right.square")
                    .font(.system(size: 11))
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
            // Même règle que la page des mises à jour : sans compte premium,
            // l'API refuse le lien direct, et c'est le bouton Nexus qui prend
            // le relais.
            .disabled(isBusy || vm.nexusDirectDownloadUnavailable)
            .help(vm.nexusDirectDownloadUnavailable ? localization.L(L10n.Mods.premiumOnlyHint) : "")
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
                        .font(.system(size: 11))
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
                    .help(localization.L(L10n.Mods.searchClose))
                    .pointingHandCursor()
                } else if !vm.hasNexusApiKey {
                    // Écrit, pas seulement en infobulle : AppKit ne garantit
                    // pas l'infobulle d'un contrôle désactivé.
                    Text(localization.L(L10n.Mods.nexusNoApiKey))
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
                Text(String(format: localization.L(L10n.Mods.nexusIdentityComponent), packName))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isSearching, let search {
                if search.candidates.isEmpty {
                    Text(localization.L(L10n.Mods.nexusIdentityNone))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(format: localization.L(L10n.Mods.nexusIdentityFound),
                                search.candidates.count))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if search.isCapped {
                        Text(String(format: localization.L(L10n.Mods.supplementCapped),
                                    search.serverTotal, search.received))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    ForEach(search.candidates.prefix(6)) { candidate in row(candidate) }
                    Text(localization.L(L10n.Mods.nexusIdentityHint))
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
                        Text(localization.L(L10n.Mods.nexusIdentitySameAuthor))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Text(String(format: localization.L(L10n.Mods.translationFromNexus), candidate.hit.uploader,
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
            .help(localization.L(L10n.Mods.translationOpenNexus))
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
