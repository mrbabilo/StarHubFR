import SwiftUI

struct ModProfilesView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// Bound to `MainView.currentTab` so "Manage mods" can jump to the Mods page.
    @Binding var currentTab: SidebarDestination

    @State private var isShowingNewProfileAlert = false
    @State private var newProfileName = ""
    @State private var renamingProfile: ModProfile?
    @State private var renameText = ""
    @State private var profileToDelete: ModProfile?
    /// La feuille du profil et la section où elle s'ouvre (R4).
    @State private var profileSheet: ProfileDiagnosticsView.Request?
    /// Profil pour lequel un import de favoris attend confirmation. Seulement
    /// renseigné quand le profil est **actif** : y importer active les mods sur
    /// le disque dans la foulée, ce qui n'est pas un simple changement de
    /// données. Sur un profil inactif l'import part directement.
    @State private var profileImportingFavorites: ModProfile?

    /// Symétrique de `profileImportingFavorites` : profil **actif** pour
    /// lequel on a demandé un import des mods « à écarter », en attente de
    /// confirmation. La feuille de confirmation vit dans `body`.
    @State private var profileImportingBlacklisted: ModProfile?

    /// Aiguille l'import : rien à importer, profil actif (confirmation), ou
    /// simple changement de données.
    private func importFavorites(into profile: ModProfile) {
        guard !vm.favoriteMods.isEmpty else {
            // Ne rien faire silencieusement laisserait croire à un bouton
            // cassé : dire où l'on marque un favori.
            vm.showModal(message: localization.L(L10n.Profiles.importFavoritesNone))
            return
        }
        if vm.activeProfileId == profile.id {
            profileImportingFavorites = profile
        } else {
            runFavoriteImport(into: profile)
        }
    }

    /// Symétrique de `importFavorites(into:)` — même aiguillage, même
    /// filet de sécurité, même message d'absence. Le bouton de menu dit
    /// « importer les écarter » et la marque `blacklistedMods` se traduit en
    /// `UniqueID` exactement comme la favorite.
    private func importBlacklisted(into profile: ModProfile) {
        guard !vm.blacklistedMods.isEmpty else {
            vm.showModal(message: localization.L(L10n.Profiles.importBlacklistedNone))
            return
        }
        if vm.activeProfileId == profile.id {
            profileImportingBlacklisted = profile
        } else {
            runBlacklistedImport(into: profile)
        }
    }

    /// Importe, puis **dit ce qui s'est passé** — combien sont entrés, et
    /// nommément ceux qui n'ont pas pu. Un import muet laisserait croire qu'il
    /// a tout pris.
    private func runFavoriteImport(into profile: ModProfile) {
        let result = vm.importFavorites(into: profile.id)
        var lines: [String] = []
        if result.ids.isEmpty {
            lines.append(String(format: localization.L(L10n.Profiles.importFavoritesNothingNew), profile.name))
        } else {
            lines.append(String(format: localization.L(L10n.Profiles.importFavoritesDone),
                                result.ids.count, profile.name))
        }
        if !result.unresolved.isEmpty {
            lines.append(String(format: localization.L(L10n.Profiles.importFavoritesUnresolved),
                                result.unresolved.count,
                                result.unresolved.joined(separator: ", ")))
        }
        vm.showModal(message: lines.joined(separator: "\n\n"))
    }

    /// Symétrique de `runFavoriteImport(into:)` : les mêmes trois lignes
    /// (comptes / aucun nouveau / non résolus), avec les libellés dédiés à
    /// la marque « à écarter ».
    private func runBlacklistedImport(into profile: ModProfile) {
        let result = vm.importBlacklisted(into: profile.id)
        var lines: [String] = []
        if result.ids.isEmpty {
            lines.append(String(format: localization.L(L10n.Profiles.importBlacklistedNothingNew), profile.name))
        } else {
            lines.append(String(format: localization.L(L10n.Profiles.importBlacklistedDone),
                                result.ids.count, profile.name))
        }
        if !result.unresolved.isEmpty {
            lines.append(String(format: localization.L(L10n.Profiles.importBlacklistedUnresolved),
                                result.unresolved.count,
                                result.unresolved.joined(separator: ", ")))
        }
        vm.showModal(message: lines.joined(separator: "\n\n"))
    }

    /// La phrase de confirmation de suppression. Hissée hors du `message:`
    /// le 2026-09-10 : la concaténation en une expression a fait franchir au
    /// `body` le seuil de saturation du type-checker (piège CLAUDE.md).
    private var profileDeletionMessage: String {
        var lines = [localization.L(L10n.Profiles.deleteNote),
                     localization.L(L10n.Profiles.deleteKeepsMods)]
        if deletionConfigCount > 0 {
            lines.append("\n" + String(format: localization.L(L10n.Profiles.deleteDropsConfigs),
                                       Int64(deletionConfigCount)))
        }
        return lines.joined(separator: "\n")
    }

    /// La rangée d'un profil. Extraite du `ForEach` le 2026-09-10 : la
    /// longue liste d'arguments avec closures saturaient le
    /// type-checker au sein du `body` (piège CLAUDE.md).
    private func profileRow(_ profile: ModProfile, issueCount: Int, flattened: [ModItem]) -> some View {
        ProfileRow(
            profile: profile,
            isActive: vm.activeProfileId == profile.id,
            modCount: profile.enabledModIds.count,
            issueCount: issueCount
                + ProfileDiagnostics.dependencyGaps(in: profile,
                                                    installedMods: flattened).count,
            translation: vm.translationSummary(for: profile),
            isMeasuringTranslation: vm.isMeasuringProfileTranslation,
            vm: vm,
            localization: localization,
            onApply: { vm.applyProfile(id: profile.id) },
            onManage: {
                vm.applyProfile(id: profile.id)
                currentTab = .mods
            },
            onRename: { renamingProfile = profile; renameText = profile.name },
            onDuplicate: { vm.duplicateProfile(id: profile.id) },
            onImportFavorites: { importFavorites(into: profile) },
            onImportBlacklisted: { importBlacklisted(into: profile) },
            onShowDetails: { focus in
                profileSheet = .init(profile: profile, focus: focus)
            },
            onDelete: { profileToDelete = profile }
        )
    }

    var body: some View {
        // Patron page de liste du dépôt (CLAUDE.md « UI ») : en-tête fixe
        // au-dessus d'une liste qui défile. Le titre de page, retiré en
        // septembre, revient avec l'en-tête commun des pages (audit UX
        // 2026-10-02) : il porte désormais le profil actif.
        VStack(spacing: 0) {
            PageHeader(icon: "person.2.fill", title: localization.L(L10n.Profiles.title),
                       subtitle: headerSummary) {
                Button(localization.L(L10n.Profiles.addProfile)) { presentNewProfileAlert() }
                    .buttonStyle(.borderedProminent).focusRing()
                    .pointingHandCursor()
            }
            .padding(.horizontal, AppDesign.Spacing.xl)
            .padding(.vertical, AppDesign.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()
            KeybindPlanProfileBanner(viewModel: vm, localization: localization)
            // ── Liste ────────────────────────────────────────────────────
            BackToTopScrollView(localization, showsIndicators: false) {
                if vm.modProfiles.isEmpty {
                    VStack(spacing: AppDesign.Spacing.lg) {
                        IconTile(icon: "person.2.slash", tint: AppDesign.Color.accent, size: 64)
                        Text(localization.L(L10n.Profiles.noProfiles))
                            .font(AppDesign.Font.body)
                            .foregroundColor(.secondary)
                        Button(localization.L(L10n.Profiles.addProfile)) { presentNewProfileAlert() }
                            .buttonStyle(.borderedProminent).focusRing()
                            .pointingHandCursor()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    let scanned = vm.scanStore.mods
                    let flattened = scanned.flattenedMods
                    let installedIds = scanned.allUniqueIds
                    LazyVStack(spacing: AppDesign.Spacing.sm) {
                        ForEach(vm.modProfiles) { profile in
                            // Compte brut, hissé hors de l'initialiseur le
                            // 2026-09-10 : les littéraux [:] dans une longue
                            // liste d'arguments saturaient le type-checker
                            // (piège CLAUDEmd). L'enrichissement (sauvegardes,
                            // cache Nexus) lit le disque et n'a lieu qu'à
                            // l'ouverture de la feuille.
                            let issueCount = ProfileDiagnostics.missingMods(
                                in: profile,
                                installedUniqueIds: installedIds,
                                backupNames: [:],
                                nexusHints: [:]).count
                            let isActive = vm.activeProfileId == profile.id
                            self.profileRow(profile, issueCount: issueCount, flattened: flattened)
                                .cardSurface(padding: 0)
                                .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.lg, style: .continuous)
                                    .stroke(AppDesign.Color.accent, lineWidth: isActive ? 1.5 : 0))
                                .animation(Motion.animation(.snappy), value: isActive)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, AppDesign.Spacing.lg)
                }
                ActivationHistorySection(viewModel: vm, localization: localization) // R5
                    .padding(.horizontal, 24)
                    .padding(.vertical, AppDesign.Spacing.lg)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        // Create
        .alert(localization.L(L10n.Profiles.createNewProfile), isPresented: $isShowingNewProfileAlert) {
            TextField(localization.L(L10n.Profiles.profileNamePlaceholder), text: $newProfileName)
            // Deux boutons plutôt qu'un : le contenu du profil se décide ici,
            // et « vide » vient en premier — c'est le cas courant, préparer une
            // autre configuration sans figer celle en cours.
            // Désactivés tant que le nom est vide. Avant, ils se contentaient
            // de ne rien faire : les deux boutons de création agissaient donc
            // exactement comme « Annuler », sans que rien ne le dise. Le champ
            // arrive de toute façon pré-rempli (voir le bouton « Ajouter »),
            // donc le cas ne se présente qu'à qui efface délibérément.
            Button(localization.L(L10n.Profiles.createEmpty)) { createProfile(seed: .empty) }
                .disabled(trimmedNewProfileName.isEmpty)
            Button(localization.L(L10n.Profiles.createFromCurrent)) { createProfile(seed: .currentlyEnabledMods) }
                .disabled(trimmedNewProfileName.isEmpty)
            Button(localization.L(L10n.Profiles.cancel), role: .cancel) { newProfileName = "" }
        } message: {
            Text(localization.L(L10n.Profiles.newProfileNote))
        }
        // Rename
        .alert(localization.L(L10n.Profiles.renameTitle), isPresented: Binding(
            get: { renamingProfile != nil },
            set: { if !$0 { renamingProfile = nil } }
        )) {
            TextField(localization.L(L10n.Profiles.profileNamePlaceholder), text: $renameText)
            Button(localization.L(L10n.Profiles.save)) {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let p = renamingProfile, !name.isEmpty { vm.renameProfile(id: p.id, newName: name) }
                renamingProfile = nil
            }
            Button(localization.L(L10n.Profiles.cancel), role: .cancel) { renamingProfile = nil }
        }
        // Delete confirmation
        .confirmationDialog(
            profileToDelete.map { String(format: localization.L(L10n.Profiles.deleteConfirm), $0.name) } ?? "",
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
                Button(String(format: localization.L(L10n.Profiles.deleteActivateNamed), successor.name)) {
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
                   ? localization.L(L10n.Profiles.delete)
                   : localization.L(L10n.Profiles.deleteWithoutActivating),
                   role: .destructive) {
                if let p = profileToDelete { vm.deleteProfile(id: p.id) }
                profileToDelete = nil
            }
            Button(localization.L(L10n.Profiles.cancel), role: .cancel) { profileToDelete = nil }
        } message: {
            // La phrase sur les configs n'apparaît que s'il y a quelque chose
            // à perdre : l'annoncer à vide apprendrait au lecteur à ne plus
            // la lire, le jour où elle compte.
            Text(profileDeletionMessage)
        }
        // Import des favoris dans le profil **actif** : les mods s'activeront
        // sur le disque immédiatement, il faut le dire avant.
        .confirmationDialog(
            profileImportingFavorites.map {
                String(format: localization.L(L10n.Profiles.importFavoritesConfirm), $0.name)
            } ?? "",
            isPresented: Binding(
                get: { profileImportingFavorites != nil },
                set: { if !$0 { profileImportingFavorites = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(localization.L(L10n.Profiles.importFavoritesConfirmAction)) {
                if let p = profileImportingFavorites { runFavoriteImport(into: p) }
                profileImportingFavorites = nil
            }
            Button(localization.L(L10n.Profiles.cancel), role: .cancel) { profileImportingFavorites = nil }
        }
        // Import des mods « à écarter » dans le profil **actif** —
        // exactement la même porte que les favoris : les mods s'activeront sur
        // le disque dans la foulée, il faut le dire avant.
        .confirmationDialog(
            profileImportingBlacklisted.map {
                String(format: localization.L(L10n.Profiles.importBlacklistedConfirm), $0.name)
            } ?? "",
            isPresented: Binding(
                get: { profileImportingBlacklisted != nil },
                set: { if !$0 { profileImportingBlacklisted = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(localization.L(L10n.Profiles.importBlacklistedConfirmAction)) {
                if let p = profileImportingBlacklisted { runBlacklistedImport(into: p) }
                profileImportingBlacklisted = nil
            }
            Button(localization.L(L10n.Profiles.cancel), role: .cancel) { profileImportingBlacklisted = nil }
        }
        // La couverture française lit les fichiers de traduction de tous les
        // mods des profils : elle se mesure ici, à l'ouverture de la page, et
        // jamais au scan — le lancement est déjà le moment le plus chargé.
        .task { vm.refreshProfileTranslationCoverage() }
        .sheet(item: $profileSheet) { request in
            ProfileDiagnosticsView(
                viewModel: vm,
                localization: localization,
                profile: request.profile,
                isPresented: Binding(get: { profileSheet != nil },
                                     set: { if !$0 { profileSheet = nil } }),
                onOpenTranslation: { folderName in
                    vm.openTranslation(forFolder: folderName)
                    currentTab = .mods
                },
                focus: request.focus)
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
        return ProfileConfigOverview.load(profileId: target.id, installed: vm.mods.flattenedMods).total
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
        newProfileName = localization.L(L10n.Profiles.defaultNewName)
        isShowingNewProfileAlert = true
    }

    private func createProfile(seed: ProfileSeed) {
        let name = trimmedNewProfileName
        guard !name.isEmpty else { return }
        vm.createProfile(name: name, seed: seed)
        newProfileName = ""
    }
}
