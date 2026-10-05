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
    /// Le fichier existe mais est illisible : le geste « réparer » réécrit
    /// depuis les défauts (jamais une option fausse posée en silence).
    @State private var corrupted = false
    @State private var unavailable = false

    private var configURL: URL? {
        guard !vm.gameDir.isEmpty else { return nil }
        let modsRoot = URL(fileURLWithPath: vm.gameDir, isDirectory: true)
            .appendingPathComponent("Mods", isDirectory: true)
        let presence: ModPresence = mod.isEnabled
            ? .enabled(folderName: mod.folderName, version: mod.version)
            : .paused(folderName: mod.folderName, version: mod.version)
        guard let folder = ProbeBundle.target(modsRoot: modsRoot, presence: presence) else { return nil }
        return folder.appendingPathComponent("config.json")
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
                .onChange(of: harmony) { _, newValue in write(harmony: newValue, textures: textures) }
                Toggle(isOn: $textures) {
                    optionLabel(L10n.Mods.probeOptionsTextures, L10n.Mods.probeOptionsTexturesHelp)
                }
                .onChange(of: textures) { _, newValue in write(harmony: harmony, textures: newValue) }
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
                            write(harmony: harmony, textures: textures, repair: true)
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
        guard let url = configURL else {
            unavailable = true
            return
        }
        guard let data = FileManager.default.contents(atPath: url.path) else {
            unavailable = true
            return
        }
        switch ProbeOptions.read(data) {
        case .success(let options):
            harmony = options.measureHarmonyPatches
            textures = options.measureTextures
        case .failure:
            corrupted = true
        }
    }

    /// L'écriture : ouvre les droits (le parc pose parfois ses dossiers en
    /// 0555), réécrit **canoniquement** — et en cas de corruption, `repair`
    /// part des valeurs affichées et rend un JSON valable.
    private func write(harmony: Bool, textures: Bool, repair: Bool = false) {
        guard let url = configURL else { return }
        let fm = FileManager.default
        ModZipInstaller.grantOwnerWriteAccess(in: url.deletingLastPathComponent())
        do {
            let data = try ProbeOptions.rewritten(
                original: repair ? nil : fm.contents(atPath: url.path),
                measureHarmonyPatches: harmony,
                measureTextures: textures)
            try data.write(to: url, options: .atomic)
            corrupted = false
        } catch {
            vm.log("Options de la sonde non écrites : \(error)", level: .warning)
        }
    }
}
