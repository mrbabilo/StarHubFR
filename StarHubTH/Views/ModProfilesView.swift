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
        VStack(alignment: .leading, spacing: 20) {
            Text(vm.L(L10n.Profiles.titleFull))
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 10)

            // List Container
            VStack(spacing: 0) {
                if vm.modProfiles.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(vm.L(L10n.Profiles.noProfiles))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Button(vm.L(L10n.Profiles.addProfile)) { presentNewProfileAlert() }
                            .buttonStyle(.borderedProminent)
                            .pointingHandCursor()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    let flattened = vm.mods.flattenedMods
                    let installedIds = vm.mods.allUniqueIds
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
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            if !vm.modProfiles.isEmpty {
                HStack {
                    Spacer()
                    Button(vm.L(L10n.Profiles.addProfile)) { presentNewProfileAlert() }
                        .pointingHandCursor()
                }
            }

            Spacer()
        }
        .padding(30)
        .background(Color(nsColor: .windowBackgroundColor))
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
            // Le choix se fait donc ici, au moment où l'on décide. Réactiver
            // d'office aurait déplacé des centaines de dossiers sans qu'on l'ait
            // demandé — sur ce parc, plusieurs secondes de renommage.
            if let successor = deletionSuccessor {
                Button(String(format: vm.L(L10n.Profiles.deleteActivateDefault), successor.name)) {
                    if let p = profileToDelete {
                        vm.deleteProfile(id: p.id)
                        vm.applyProfile(id: successor.id)
                    }
                    profileToDelete = nil
                }
                .disabled(vm.isApplyingProfile)
            }
            Button(vm.L(L10n.Profiles.delete), role: .destructive) {
                if let p = profileToDelete { vm.deleteProfile(id: p.id) }
                profileToDelete = nil
            }
            Button(vm.L(L10n.Profiles.cancel), role: .cancel) { profileToDelete = nil }
        } message: {
            Text(vm.L(L10n.Profiles.deleteNote) + "\n" + vm.L(L10n.Profiles.deleteKeepsMods))
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
    private var deletionSuccessor: ModProfile? {
        guard let target = profileToDelete, vm.activeProfileId == target.id else { return nil }
        let remaining = vm.modProfiles.filter { $0.id != target.id }
        return remaining.first { vm.isDefaultProfile($0.id) } ?? remaining.first
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

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                    if isActive {
                        Text(vm.L(L10n.Profiles.active))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text(String(format: vm.L(L10n.Profiles.modCount), modCount))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    if issueCount > 0 {
                        Button(action: onShowMissing) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(String(format: vm.L(L10n.Profiles.issuesBadge), Int64(issueCount)))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }
                }
                // Sur sa propre ligne, et non à la suite des compteurs : sur le
                // profil « OK » la rangée porterait « 529 mods », « 6 anomalies »
                // et « FR 86 % · 50 à traduire » — trois fois plus de texte que
                // la colonne n'en tient à la largeur minimale de la fenêtre
                // (820 pt, dont 240 de barre latérale et ~230 de boutons).
                translationBadge
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
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { isHovered = $0 }
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
