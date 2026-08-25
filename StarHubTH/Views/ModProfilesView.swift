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
                        Button(vm.L(L10n.Profiles.addProfile)) { isShowingNewProfileAlert = true }
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
                    Button(vm.L(L10n.Profiles.addProfile)) { isShowingNewProfileAlert = true }
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
            Button(vm.L(L10n.Profiles.createEmpty)) { createProfile(seed: .empty) }
            Button(vm.L(L10n.Profiles.createFromCurrent)) { createProfile(seed: .currentlyEnabledMods) }
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
            Button(vm.L(L10n.Profiles.delete), role: .destructive) {
                if let p = profileToDelete { vm.deleteProfile(id: p.id) }
                profileToDelete = nil
            }
            Button(vm.L(L10n.Profiles.cancel), role: .cancel) { profileToDelete = nil }
        } message: {
            Text(vm.L(L10n.Profiles.deleteNote))
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
        .sheet(item: $profileShowingMissing) { profile in
            ProfileDiagnosticsView(
                vm: vm,
                profile: profile,
                isPresented: Binding(get: { profileShowingMissing != nil },
                                     set: { if !$0 { profileShowingMissing = nil } }))
        }
    }

    private func createProfile(seed: ProfileSeed) {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { vm.createProfile(name: name, seed: seed) }
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
                Button(vm.L(L10n.Profiles.importFavorites)) { onImportFavorites() }
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
            if !vm.isDefaultProfile(profile.id) {
                Divider()
                Button(vm.L(L10n.Profiles.delete), role: .destructive) { onDelete() }
            }
        }
    }
}
