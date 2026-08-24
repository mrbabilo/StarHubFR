import SwiftUI

/// Les mods qu'un profil réclame et qui ne sont plus installés.
///
/// Sans cet écran, un profil qui a perdu des mods s'applique en silence : le
/// jeu démarre amputé, et rien ne dit lesquels manquent. C'est d'autant plus
/// sensible que ces mods sont souvent des **cadres** dont d'autres dépendent
/// (SpaceCore, Json Assets, GMCM) — leur absence casse plus que leur propre
/// fonctionnalité.
struct ProfileMissingModsView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let profile: ModProfile
    @Binding var isPresented: Bool

    /// Calculé une fois à l'ouverture : la résolution lit l'index des
    /// sauvegardes sur le disque, ce qu'on ne refait pas à chaque rendu.
    @State private var missing: [MissingProfileMod] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: vm.L(L10n.Profiles.missingTitle), profile.name))
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
                    ForEach(missing) { mod in
                        row(mod)
                        Divider().padding(.leading, 20)
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
        .onAppear { missing = vm.missingMods(in: profile) }
        // La restauration relance un scan **asynchrone** : recalculer juste
        // après l'avoir lancée lit encore l'ancien `vm.mods`, et le mod
        // restauré resterait affiché comme manquant. On refait le calcul quand
        // le parc a réellement changé.
        .onChange(of: vm.mods.count) { _, _ in missing = vm.missingMods(in: profile) }
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
                    .disabled(vm.isDownloadingFromNexus)
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
