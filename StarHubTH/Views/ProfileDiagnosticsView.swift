import SwiftUI

/// Ce qui empêchera ce profil de tourner tel quel : les mods qu'il réclame et
/// qui ne sont plus installés, et les dépendances requises qu'il laisse de côté.
///
/// Sans cet écran, un profil qui a perdu des mods s'applique en silence : le
/// jeu démarre amputé, et rien ne dit lesquels manquent. C'est d'autant plus
/// sensible que ces mods sont souvent des **cadres** dont d'autres dépendent
/// (SpaceCore, Json Assets, GMCM) — leur absence casse plus que leur propre
/// fonctionnalité.
struct ProfileDiagnosticsView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let profile: ModProfile
    @Binding var isPresented: Bool

    /// Calculé une fois à l'ouverture : la résolution lit l'index des
    /// sauvegardes sur le disque, ce qu'on ne refait pas à chaque rendu.
    @State private var missing: [MissingProfileMod] = []
    @State private var gaps: [ProfileDependencyGap] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: vm.L(L10n.Profiles.diagnosticTitle), profile.name))
                    .font(.system(size: 16, weight: .semibold))
                Text(vm.L(L10n.Profiles.missingNote) + " " + vm.L(L10n.Profiles.missingRestoreNote))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    if !missing.isEmpty {
                        sectionHeader(vm.L(L10n.Profiles.sectionMissing))
                        ForEach(missing) { mod in
                            row(mod)
                            Divider().padding(.leading, 20)
                        }
                    }
                    if !gaps.isEmpty {
                        sectionHeader(vm.L(L10n.Profiles.sectionDependencies))
                        ForEach(gaps) { gap in
                            gapRow(gap)
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button(vm.L(L10n.Main.ok)) { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 460)
        .onAppear { reload() }
        // La restauration relance un scan **asynchrone** : recalculer juste
        // après l'avoir lancée lit encore l'ancien `vm.mods`, et le mod
        // restauré resterait affiché comme manquant. On refait le calcul quand
        // le parc a réellement changé.
        .onChange(of: vm.mods.count) { _, _ in reload() }
        // Ajouter une dépendance au profil change le profil, pas le parc : le
        // compte de mods est le signal qui l'annonce.
        .onChange(of: vm.modProfiles) { _, _ in reload() }
    }

    private func reload() {
        // Le profil est relu depuis le ViewModel : celui que la feuille porte
        // est une copie prise à l'ouverture, et ne verrait pas les dépendances
        // qu'on vient d'y ajouter.
        let current = vm.modProfiles.first { $0.id == profile.id } ?? profile
        missing = vm.missingMods(in: current)
        gaps = ProfileDiagnostics.dependencyGaps(in: current, installedMods: vm.mods.flattenedMods)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    /// Une dépendance requise que le profil ne retient pas. Deux cas, deux
    /// gestes : l'ajouter au profil quand elle est installée, la télécharger
    /// quand elle ne l'est pas — et là, on ne sait pas encore où.
    private func gapRow(_ gap: ProfileDependencyGap) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(gap.displayName)
                    .font(.system(size: 13))
                Text(String(format: vm.L(L10n.Profiles.requiredByCount),
                            Int64(gap.requiredBy.count),
                            gap.requiredBy.prefix(3).joined(separator: ", ")))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if gap.isInstalled {
                // Ajouter une dépendance à un profil **actif** déplace un
                // dossier et relance un scan : le voile de progression vit dans
                // la fenêtre, donc derrière cette feuille. Sans ce témoin, le
                // clic n'aurait aucun effet visible pendant plusieurs secondes.
                if vm.isApplyingProfile {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(vm.L(L10n.Profiles.addToProfile)) {
                        vm.addModToProfile(id: profile.id, uniqueId: gap.uniqueId)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .pointingHandCursor()
                }
            } else {
                Text(vm.L(L10n.Profiles.dependencyNotInstalled))
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func row(_ mod: MissingProfileMod) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.displayName)
                    .font(.system(size: 13))
                // L'identifiant reste visible : c'est ce que l'utilisateur
                // retrouvera dans un manifeste ou dans un journal SMAPI, et
                // pour les profils d'avant c'est parfois tout ce qu'on a.
                Text(mod.uniqueId)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            if mod.isBundledWithSmapi {
                // Proposer Nexus ici serait un mauvais conseil : ce mod revient
                // avec une réinstallation de SMAPI, et n'a pas de page à lui.
                Text(vm.L(L10n.Profiles.missingBundled))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                if mod.hasBackup {
                    Button(vm.L(L10n.Profiles.missingRestore)) {
                        vm.restoreMissingModFromBackup(uniqueId: mod.uniqueId)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .pointingHandCursor()
                }
                if let nexusId = mod.nexusModId, let id = Int(nexusId) {
                    Button(vm.L(L10n.ModInstall.depDownload)) {
                        vm.downloadModFromNexus(nexusId: id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    // L'API refuse tout lien direct à un compte non premium :
                    // proposer le bouton reviendrait à promettre un échec.
                    .disabled(vm.isDownloadingFromNexus || vm.nexusDirectDownloadUnavailable)
                    .help(vm.nexusDirectDownloadUnavailable ? vm.L(L10n.Mods.premiumOnlyHint) : "")
                    .pointingHandCursor()
                } else if !mod.hasBackup {
                    Text(vm.L(L10n.Profiles.missingUnknown))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
