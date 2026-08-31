import SwiftUI

struct ModProfilesView: View {
    @ObservedObject var vm: StarHubTHViewModel
    /// Bound to `MainView.currentTab` so "Manage mods" can jump to the Mods page.
    @Binding var currentTab: String

    @State private var isShowingNewProfileAlert = false
    @State private var newProfileName = ""
    @State private var renamingProfile: ModProfile?
    @State private var renameText = ""
    @State private var profileToDelete: ModProfile?
    @State private var profileShowingMissing: ModProfile?
    /// Profil pour lequel un import de favoris attend confirmation. Seulement
    /// renseigné quand le profil est **actif** : y importer active les mods sur
    /// le disque dans la foulée, ce qui n'est pas un simple changement de
    /// données. Sur un profil inactif l'import part directement.
    @State private var profileImportingFavorites: ModProfile?

    /// Aiguille l'import : rien à importer, profil actif (confirmation), ou
    /// simple changement de données.
    private func importFavorites(into profile: ModProfile) {
        guard !vm.favoriteMods.isEmpty else {
            // Ne rien faire silencieusement laisserait croire à un bouton
            // cassé : dire où l'on marque un favori.
            vm.showModal(message: vm.L(L10n.Profiles.importFavoritesNone))
            return
        }
        if vm.activeProfileId == profile.id {
            profileImportingFavorites = profile
        } else {
            runFavoriteImport(into: profile)
        }
    }

    /// Importe, puis **dit ce qui s'est passé** — combien sont entrés, et
    /// nommément ceux qui n'ont pas pu. Un import muet laisserait croire qu'il
    /// a tout pris.
    private func runFavoriteImport(into profile: ModProfile) {
        let result = vm.importFavorites(into: profile.id)
        var lines: [String] = []
        if result.ids.isEmpty {
            lines.append(String(format: vm.L(L10n.Profiles.importFavoritesNothingNew), profile.name))
        } else {
            lines.append(String(format: vm.L(L10n.Profiles.importFavoritesDone),
                                result.ids.count, profile.name))
        }
        if !result.unresolved.isEmpty {
            lines.append(String(format: vm.L(L10n.Profiles.importFavoritesUnresolved),
                                result.unresolved.count,
                                result.unresolved.joined(separator: ", ")))
        }
        vm.showModal(message: lines.joined(separator: "\n\n"))
    }

    var body: some View {
        // Patron page de liste du dépôt (CLAUDE.md « UI »), calé sur le
        // pilote Mods : toolbar fixe au-dessus d'une liste qui scrolle,
        // fond `controlBackgroundColor` — plus de conteneur à bordure ni de
        // titre de page, l'identité de la page vient de la sidebar.
        VStack(spacing: 0) {
            // ── Toolbar fixe ────────────────────────────────────────────
            // Rien à filtrer sur cette page (un seul segment) : l'action
            // primaire « Ajouter » occupe seule la rangée, à droite.
            HStack {
                Spacer()
                Button(vm.L(L10n.Profiles.addProfile)) { presentNewProfileAlert() }
                    .buttonStyle(.borderedProminent)
                    .pointingHandCursor()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // ── Liste ────────────────────────────────────────────────────
            ScrollView(showsIndicators: false) {
                if vm.modProfiles.isEmpty {
                    VStack(spacing: AppDesign.Spacing.lg) {
                        Image(systemName: "person.2.slash")
                            .font(AppDesign.Font.emptyScopeGlyph)
                            .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
                        Text(vm.L(L10n.Profiles.noProfiles))
                            .font(AppDesign.Font.body)
                            .foregroundColor(.secondary)
                        Button(vm.L(L10n.Profiles.addProfile)) { presentNewProfileAlert() }
                            .buttonStyle(.borderedProminent)
                            .pointingHandCursor()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    let flattened = vm.mods.flattenedMods
                    let installedIds = vm.mods.allUniqueIds
                    LazyVStack(spacing: 0) {
                        ForEach(Array(vm.modProfiles.enumerated()), id: \.element.id) { index, profile in
                            ProfileRow(
                                profile: profile,
                                isActive: vm.activeProfileId == profile.id,
                                modCount: profile.enabledModIds.count,
                                // Compte brut : l'enrichissement (sauvegardes, cache
                                // Nexus) lit le disque et n'a lieu qu'à l'ouverture
                                // de la feuille.
                                issueCount: ProfileDiagnostics.missingMods(in: profile,
                                                                           installedUniqueIds: installedIds,
                                                                           backupNames: [:],
                                                                           nexusHints: [:]).count
                                    + ProfileDiagnostics.dependencyGaps(in: profile,
                                                                        installedMods: flattened).count,
                                translation: vm.translationSummary(for: profile),
                                isMeasuringTranslation: vm.isMeasuringProfileTranslation,
                                vm: vm,
                                onApply: { vm.applyProfile(id: profile.id) },
                                onManage: {
                                    vm.applyProfile(id: profile.id)
                                    currentTab = "Mods"
                                },
                                onRename: { renamingProfile = profile; renameText = profile.name },
                                onDuplicate: { vm.duplicateProfile(id: profile.id) },
                                onImportFavorites: { importFavorites(into: profile) },
                                onShowMissing: { profileShowingMissing = profile },
                                onDelete: { profileToDelete = profile }
                            )
                            if index < vm.modProfiles.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, AppDesign.Spacing.lg)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        // Create
        .alert(vm.L(L10n.Profiles.createNewProfile), isPresented: $isShowingNewProfileAlert) {
            TextField(vm.L(L10n.Profiles.profileNamePlaceholder), text: $newProfileName)
            // Deux boutons plutôt qu'un : le contenu du profil se décide ici,
            // et « vide » vient en premier — c'est le cas courant, préparer une
            // autre configuration sans figer celle en cours.
            // Désactivés tant que le nom est vide. Avant, ils se contentaient
            // de ne rien faire : les deux boutons de création agissaient donc
            // exactement comme « Annuler », sans que rien ne le dise. Le champ
            // arrive de toute façon pré-rempli (voir le bouton « Ajouter »),
            // donc le cas ne se présente qu'à qui efface délibérément.
            Button(vm.L(L10n.Profiles.createEmpty)) { createProfile(seed: .empty) }
                .disabled(trimmedNewProfileName.isEmpty)
            Button(vm.L(L10n.Profiles.createFromCurrent)) { createProfile(seed: .currentlyEnabledMods) }
                .disabled(trimmedNewProfileName.isEmpty)
            Button(vm.L(L10n.Profiles.cancel), role: .cancel) { newProfileName = "" }
        } message: {
            Text(vm.L(L10n.Profiles.newProfileNote))
        }
        // Rename
        .alert(vm.L(L10n.Profiles.renameTitle), isPresented: Binding(
            get: { renamingProfile != nil },
            set: { if !$0 { renamingProfile = nil } }
        )) {
            TextField(vm.L(L10n.Profiles.profileNamePlaceholder), text: $renameText)
            Button(vm.L(L10n.Profiles.save)) {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let p = renamingProfile, !name.isEmpty { vm.renameProfile(id: p.id, newName: name) }
                renamingProfile = nil
            }
            Button(vm.L(L10n.Profiles.cancel), role: .cancel) { renamingProfile = nil }
        }
        // Delete confirmation
        .confirmationDialog(
            profileToDelete.map { String(format: vm.L(L10n.Profiles.deleteConfirm), $0.name) } ?? "",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            // Supprimer le profil actif laissait le parc dans un état sans
            // propriétaire : plus aucun profil actif, et sur le disque les mods
            // que le profil supprimé avait activés. Rien ne le disait, et rien
            // ne proposait d'en sortir.
            //
            // Le choix se fait donc ici, au moment où l'on décide — et il porte
            // sur **tous** les profils restants, pas sur un successeur désigné
            // d'office : le profil par défaut n'est pas forcément celui vers
            // lequel on veut revenir. Ils sont proposés dans l'ordre de la
            // liste au-dessus, celui que l'œil vient de parcourir.
            //
            // Réactiver sans demander aurait déplacé des centaines de dossiers
            // sans qu'on l'ait voulu — sur ce parc, plusieurs secondes de
            // renommage. D'où le bouton qui supprime sans rien activer, gardé.
            ForEach(deletionSuccessors) { successor in
                Button(String(format: vm.L(L10n.Profiles.deleteActivateNamed), successor.name)) {
                    if let p = profileToDelete {
                        vm.deleteProfile(id: p.id)
                        vm.applyProfile(id: successor.id)
                    }
                    profileToDelete = nil
                }
                .disabled(vm.isApplyingProfile)
            }
            // Le libellé change avec la situation : « Supprimer » seul, quand
            // un successeur est proposé juste au-dessus, laisserait croire
            // qu'il en active un.
            Button(deletionSuccessors.isEmpty
                   ? vm.L(L10n.Profiles.delete)
                   : vm.L(L10n.Profiles.deleteWithoutActivating),
                   role: .destructive) {
                if let p = profileToDelete { vm.deleteProfile(id: p.id) }
                profileToDelete = nil
            }
            Button(vm.L(L10n.Profiles.cancel), role: .cancel) { profileToDelete = nil }
        } message: {
            // La phrase sur les configs n'apparaît que s'il y a quelque chose
            // à perdre : l'annoncer à vide apprendrait au lecteur à ne plus
            // la lire, le jour où elle compte.
            Text(vm.L(L10n.Profiles.deleteNote) + "\n"
                 + vm.L(L10n.Profiles.deleteKeepsMods)
                 + (deletionConfigCount > 0
                    ? "\n" + String(format: vm.L(L10n.Profiles.deleteDropsConfigs),
                                     Int64(deletionConfigCount))
                    : ""))
        }
        // Import des favoris dans le profil **actif** : les mods s'activeront
        // sur le disque immédiatement, il faut le dire avant.
        .confirmationDialog(
            profileImportingFavorites.map {
                String(format: vm.L(L10n.Profiles.importFavoritesConfirm), $0.name)
            } ?? "",
            isPresented: Binding(
                get: { profileImportingFavorites != nil },
                set: { if !$0 { profileImportingFavorites = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(vm.L(L10n.Profiles.importFavoritesConfirmAction)) {
                if let p = profileImportingFavorites { runFavoriteImport(into: p) }
                profileImportingFavorites = nil
            }
            Button(vm.L(L10n.Profiles.cancel), role: .cancel) { profileImportingFavorites = nil }
        }
        // La couverture française lit les fichiers de traduction de tous les
        // mods des profils : elle se mesure ici, à l'ouverture de la page, et
        // jamais au scan — le lancement est déjà le moment le plus chargé.
        .task { vm.refreshProfileTranslationCoverage() }
        .sheet(item: $profileShowingMissing) { profile in
            ProfileDiagnosticsView(
                vm: vm,
                profile: profile,
                isPresented: Binding(get: { profileShowingMissing != nil },
                                     set: { if !$0 { profileShowingMissing = nil } }),
                onOpenTranslation: { folderName in
                    vm.openTranslation(forFolder: folderName)
                    currentTab = "Mods"
                })
        }
    }

    /// Le profil à proposer après la suppression : le profil par défaut, ou à
    /// défaut le premier qui reste.
    ///
    /// `nil` — donc pas de bouton — quand le profil visé n'est **pas** actif
    /// (le disque ne lui appartient pas, il n'y a rien à reprendre) ou qu'il ne
    /// resterait aucun autre profil.
    /// Combien de configs le profil qu'on s'apprête à supprimer retient.
    /// `0` quand il n'y a rien à perdre — la confirmation se tait alors.
    private var deletionConfigCount: Int {
        guard let target = profileToDelete else { return 0 }
        return vm.profileConfigSummary(for: target).total
    }

    /// Les profils qu'on peut activer à la place de celui qu'on supprime.
    ///
    /// Vide quand le profil supprimé n'est pas l'actif : rien ne change de
    /// propriétaire, il n'y a rien à réactiver. Vide aussi s'il ne reste
    /// aucun profil.
    private var deletionSuccessors: [ModProfile] {
        guard let target = profileToDelete, vm.activeProfileId == target.id else { return [] }
        return vm.modProfiles.filter { $0.id != target.id }
    }

    private var trimmedNewProfileName: String {
        newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ouvre la création avec un nom déjà là.
    ///
    /// Un champ vide était le chemin vers un bouton muet : « Créer un profil
    /// vide » ne faisait rien et refermait l'alerte, indiscernable d'un clic
    /// sur « Annuler ». Proposer un nom supprime le cas au lieu de le
    /// signaler, et laisse le champ prêt à être réécrit.
    private func presentNewProfileAlert() {
        newProfileName = vm.L(L10n.Profiles.defaultNewName)
        isShowingNewProfileAlert = true
    }

    private func createProfile(seed: ProfileSeed) {
        let name = trimmedNewProfileName
        guard !name.isEmpty else { return }
        vm.createProfile(name: name, seed: seed)
        newProfileName = ""
    }
}

struct ProfileRow: View {
    let profile: ModProfile
    let isActive: Bool
    let modCount: Int
    /// Ce qui empêchera le profil de tourner tel quel : mods disparus et
    /// dépendances requises laissées de côté. `0` la plupart du temps.
    let issueCount: Int
    /// La part de français du profil (B3-T4). `nil` tant que la mesure n'a pas
    /// eu lieu — elle lit le disque et n'a lieu qu'à l'ouverture de cette page.
    let translation: ProfileTranslationSummary?
    /// La mesure est en cours : un témoin, plutôt qu'un chiffre qui monterait
    /// sous les yeux de l'utilisateur.
    let isMeasuringTranslation: Bool
    @ObservedObject var vm: StarHubTHViewModel
    let onApply: () -> Void
    let onManage: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onImportFavorites: () -> Void
    let onShowMissing: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    /// Ce que ce profil retient des `config.json`, rempli à l'apparition et
    /// jamais recalculé au rendu : la mesure ouvre et décode un fichier.
    @State private var configSummary: (total: Int, orphans: [String]) = (0, [])

    var body: some View {
        // A plain row (NOT a tappable button) so switching profiles — which
        // moves mod folders on disk — only ever happens via the explicit
        // "Activate"/"Manage" buttons, never an accidental click on the row.
        HStack(spacing: 14) {
            InitialsAvatar(
                text: profile.name,
                size: 40,
                fillColor: isActive ? Color.accentColor : Color.gray.opacity(0.3),
                textColor: isActive ? .white : .primary,
                fontSize: 20,
                fontWeight: .medium
            )

            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                HStack(spacing: AppDesign.Spacing.sm) {
                    Text(profile.name)
                        .font(AppDesign.Font.rowTitle)
                        .foregroundColor(.primary)
                    if isActive {
                        Text(vm.L(L10n.Profiles.active))
                            .font(AppDesign.Font.iconXS(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                // La carte à chiffres clés de la spec refonte (§6) : ce qui
                // décide si on active ce profil se lit en colonnes tenues,
                // pas en phrases empilées — trois colonnes de ~85 pt tiennent
                // dans les ~280 pt que la fenêtre minimale (820 pt) laisse
                // à côté de l'avatar et des boutons.
                statColumns
                // Pastilles d'attention sur leur propre ligne, sous les
                // colonnes : la pastille FR reste la seule porte vers le
                // diagnostic sur un profil sans le moindre défaut, et son
                // libellé (« FR 86 % · 50 à traduire ») ne se replie pas en
                // colonne.
                translationBadge
                configBadge
            }

            Spacer()

            // Activate → switch to this profile (applies its mod set). Hidden
            // for the already-active profile, and disabled while another
            // application is still moving files (activation is serialized).
            // While *this* profile is the one being applied, its Activate
            // button collapses to a spinner.
            // Le profil devient actif **avant** que ses dossiers ne bougent :
            // tester `applyingProfileId` d'abord, sinon le témoin d'activité
            // vivrait dans une branche `!isActive` que l'application ne
            // traverse jamais.
            if vm.applyingProfileId == profile.id {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 70, alignment: .center)
            } else if !isActive {
                Button(vm.L(L10n.Profiles.activate)) { onApply() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(vm.isApplyingProfile)
                    .pointingHandCursor()
            }

            // Manage → apply this profile and jump to the Mods page to edit it.
            Button(vm.L(L10n.Profiles.manageMods)) { onManage() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vm.isApplyingProfile)
                .pointingHandCursor()

            // Overflow: rename / delete. The default profile can't be deleted,
            // so its menu only offers rename.
            Menu {
                Button(vm.L(L10n.Profiles.rename)) { onRename() }
                Button(vm.L(L10n.Profiles.duplicate)) { onDuplicate() }
                // Refusée pendant qu'un profil s'applique : le profil devient
                // actif **avant** que ses dossiers ne bougent, un import lancé
                // dans cette fenêtre courserait les déplacements en cours.
                Button(vm.L(L10n.Profiles.importFavorites)) { onImportFavorites() }
                    .disabled(vm.isApplyingProfile)
                if !vm.isDefaultProfile(profile.id) {
                    Divider()
                    Button(vm.L(L10n.Profiles.delete), role: .destructive) { onDelete() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(vm.L(L10n.Profiles.rename))
        }
        .padding(.vertical, AppDesign.Spacing.md)
        .padding(.horizontal, AppDesign.Spacing.lg)
        .contentShape(Rectangle())
        .background(isHovered ? Color.primary.opacity(AppDesign.Opacity.subtle) : Color.clear)
        .onHover { isHovered = $0 }
        .onAppear { configSummary = vm.profileConfigSummary(for: profile) }
        .contextMenu {
            if !isActive {
                Button(vm.L(L10n.Profiles.activate)) { onApply() }
                    .disabled(vm.isApplyingProfile)
            }
            Button(vm.L(L10n.Profiles.manageMods)) { onManage() }
                .disabled(vm.isApplyingProfile)
            Button(vm.L(L10n.Profiles.rename)) { onRename() }
            Button(vm.L(L10n.Profiles.duplicate)) { onDuplicate() }
            Button(vm.L(L10n.Profiles.importFavorites)) { onImportFavorites() }
                .disabled(vm.isApplyingProfile)
            if !vm.isDefaultProfile(profile.id) {
                Divider()
                Button(vm.L(L10n.Profiles.delete), role: .destructive) { onDelete() }
            }
        }
    }

    /// Les trois chiffres qui résument le profil (spec refonte §6, « carte à
    /// chiffres clés »). Chaque colonne : libellé `footnote` au-dessus,
    /// valeur `body` semibold en dessous — le motif `StatStrip` en
    /// miniature, à hauteur réservée : une colonne sans données affiche
    /// « — », la rangée ne saute pas.
    ///
    /// Seule « Anomalies » est un bouton : c'est la donnée qui mène au
    /// diagnostic, la cible de clic est donc la colonne entière, pas un
    /// glyph de 12 pt (a11y §7). « 0 » s'affiche neutre — un zéro est une
    /// information ; « > 0 » porte glyph **et** couleur, jamais la couleur
    /// seule (P6).
    private var statColumns: some View {
        HStack(alignment: .top, spacing: AppDesign.Spacing.xl) {
            statColumn(label: vm.L(L10n.Profiles.colMods),
                       value: "\(modCount)",
                       help: String(format: vm.L(L10n.Profiles.modCount), modCount))
            Button(action: onShowMissing) {
                statColumn(label: vm.L(L10n.Profiles.colIssues),
                           value: "\(issueCount)",
                           attention: issueCount > 0,
                           help: String(format: vm.L(L10n.Profiles.issuesBadge),
                                        Int64(issueCount)))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            statColumn(label: vm.L(L10n.Profiles.colConfigs),
                       value: configSummary.total > 0 ? "\(configSummary.total)" : "—")
        }
        .fixedSize()
    }

    /// Une colonne de la bande : libellé, valeur, et le glyph d'attention
    /// quand la donnée en demande.
    private func statColumn(label: String, value: String,
                            attention: Bool = false, help: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
            HStack(spacing: AppDesign.Spacing.xs) {
                if attention {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppDesign.Font.iconXXS)
                        .foregroundColor(AppDesign.Color.warning)
                }
                Text(value)
                    .font(AppDesign.Font.body(.semibold))
                    .foregroundColor(attention ? AppDesign.Color.warning : .primary)
                    .lineLimit(1)
            }
        }
        .help(help)
    }

    /// Les `config.json` que ce profil retient, et ceux dont le mod n'est
    /// plus installé.
    ///
    /// Sa propre ligne, comme `translationBadge` : la rangée ne tient pas
    /// un compteur de plus à la largeur minimale de la fenêtre. Les noms
    /// d'orphelins sont tronqués à cinq — un profil peut en porter des
    /// dizaines.
    @ViewBuilder
    private var configBadge: some View {
        if configSummary.total > 0 {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: vm.L(L10n.Profiles.configStored),
                            Int64(configSummary.total)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if !configSummary.orphans.isEmpty {
                    let names = configSummary.orphans.prefix(5).joined(separator: ", ")
                    let more = configSummary.orphans.count - 5
                    Text(String(format: vm.L(L10n.Profiles.configOrphans),
                                Int64(configSummary.orphans.count),
                                more > 0 ? "\(names) +\(more)" : names))
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// La part de français du profil, et ce qu'il reste à traduire.
    ///
    /// Elle n'informe pas seulement : c'est **la seule porte** vers l'écran de
    /// diagnostic quand le profil n'a ni mod manquant ni dépendance en
    /// souffrance — la pastille orange ne s'affiche alors pas. Sur ses trois
    /// profils c'est le cas de « TEST », qui compte pourtant 15 mods sans une
    /// ligne de français.
    ///
    /// Rien pour un profil qui n'a aucun mod traduisible : annoncer « 0 % »
    /// ferait croire à un travail qui n'existe pas.
    @ViewBuilder
    private var translationBadge: some View {
        if let summary = translation, !summary.isEmpty {
            Button(action: onShowMissing) {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text(summary.pending.isEmpty
                         ? String(format: vm.L(L10n.Profiles.frBadgeDone), summary.displayPercent)
                         : String(format: vm.L(L10n.Profiles.frBadge),
                                  summary.displayPercent, Int64(summary.pending.count)))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(summary.pending.isEmpty ? .secondary : .accentColor)
                // Le libellé le plus long — « FR 100 % · 999 à traduire » —
                // reste sur une ligne : la colonne le tient, mais rien ne doit
                // pouvoir le replier en deux si un profil grossit encore.
                .lineLimit(1)
                .fixedSize()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(String(format: vm.L(L10n.Profiles.frBadgeHint),
                         Int64(summary.translatableCount),
                         Int64(summary.fullyTranslatedCount)))
        } else if isMeasuringTranslation {
            // Sans texte : trois lignes de profil afficheraient sinon trois
            // fois la même phrase. L'infobulle la porte pour qui s'interroge.
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
                .help(vm.L(L10n.Profiles.translationMeasuring))
        }
    }
}
