import SwiftUI

/// D4-T6 bis — les options de configuration de la sonde, sur sa fiche : un
/// Toggle par option connue, l'explication à côté, et une écriture **toujours
/// propre** (`ProbeOptions.rewritten`) — la config éditée à la main du
/// 2026-10-05 portait une virgule manquante que SMAPI rejetait en silence.
/// La sonde lit sa config à l'`Entry` : un changement dit « prend effet au
/// prochain lancement », jamais un mensonge d'immédiateté.
struct ProbeOptionsSection: View {
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem
    var vm: StarHubTHViewModel

    @State private var harmony = ProbeOptions.defaultHarmonyPatches
    @State private var textures = ProbeOptions.defaultTextures
    @State private var miniStats = ProbeOptions.defaultMiniStats
    /// Le fichier existe mais est illisible : le geste « réparer » réécrit
    /// depuis les défauts (jamais une option fausse posée en silence).
    @State private var corrupted = false
    @State private var unavailable = false

    private var configURL: URL? {
        ProbeOptionsFile.url(gameDir: vm.gameDir, presence: mod.isEnabled
            ? .enabled(folderName: mod.folderName, version: mod.version)
            : .paused(folderName: mod.folderName, version: mod.version))
    }

    private var options: ProbeOptions {
        ProbeOptions(measureHarmonyPatches: harmony, measureTextures: textures, showMiniStats: miniStats)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.Mods.probeOptionsTitle))
                .font(AppDesign.Font.headline(.semibold))
            if unavailable {
                Text(localization.L(L10n.Mods.probeOptionsUnavailable))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Toggle(isOn: $harmony) {
                    optionLabel(L10n.Mods.probeOptionsHarmony, L10n.Mods.probeOptionsHarmonyHelp)
                }
                .onChange(of: harmony) { _, _ in write() }
                Toggle(isOn: $textures) {
                    optionLabel(L10n.Mods.probeOptionsTextures, L10n.Mods.probeOptionsTexturesHelp)
                }
                .onChange(of: textures) { _, _ in write() }
                Toggle(isOn: $miniStats) {
                    optionLabel(L10n.Mods.probeOptionsMiniStats, L10n.Mods.probeOptionsMiniStatsHelp)
                }
                .onChange(of: miniStats) { _, _ in write() }
                Text(localization.L(L10n.Mods.probeOptionsLaunchNote))
                    .font(AppDesign.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if corrupted {
                    HStack(spacing: AppDesign.Spacing.sm) {
                        Label(localization.L(L10n.Mods.probeOptionsCorrupted),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(AppDesign.Color.warning)
                        Spacer()
                        Button(localization.L(L10n.Mods.probeOptionsRepair)) {
                            write(repair: true)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .onAppear { load() }
    }

    private func optionLabel(_ title: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(localization.L(title)).font(AppDesign.Font.footnote(.medium))
            Text(localization.L(help)).font(AppDesign.Font.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pointingHandCursor()
    }

    private func load() {
        switch ProbeOptionsFile.load(configURL) {
        case .options(let options):
            harmony = options.measureHarmonyPatches
            textures = options.measureTextures
            miniStats = options.showMiniStats
        case .corrupted: corrupted = true
        case .unavailable: unavailable = true
        }
    }

    /// En cas de corruption, `repair` part des valeurs affichées et rend un
    /// JSON valable (`ProbeOptionsFile.write`).
    private func write(repair: Bool = false) {
        guard let url = configURL else { return }
        do {
            try ProbeOptionsFile.write(options, to: url, repair: repair)
            corrupted = false
        } catch {
            vm.log("Options de la sonde non écrites : \(error)", level: .warning)
        }
    }
}
