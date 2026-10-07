import SwiftUI

/// « Extensions principales » des réglages : les mods dont l'app a besoin,
/// puis les extensions courantes, chacun avec son rôle, son état lu par
/// `UniqueID` et de quoi l'installer ; enfin les outils d'extraction.
struct AppExtensionsSettingsSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var probeFailure: String?

    var body: some View {
        StandardSection(title: localization.L(L10n.Home.coreExtensions),
                        icon: ("puzzlepiece.extension.fill", .purple)) {
            VStack(alignment: .leading, spacing: 0) {
                group(.requiredByApp, title: L10n.AppExtensions.groupRequired)
                group(.common, title: L10n.AppExtensions.groupCommon)
                CoreToolRow(title: localization.L(L10n.Home.toolUnar),
                            status: viewModel.unarInstalled ? .enabledAndInstalled : .notInstalled,
                            tooltip: localization.L(L10n.Home.toolUnarTooltip),
                            installCommand: "brew install unar")
                separator
                CoreToolRow(title: localization.L(L10n.Home.toolSevenZip),
                            status: viewModel.sevenZipInstalled ? .enabledAndInstalled : .notInstalled,
                            tooltip: localization.L(L10n.Home.toolSevenZipTooltip),
                            installCommand: "brew install sevenzip")
            }
            .padding(.vertical, -8)
        }
    }

    private var separator: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1)
            .padding(.leading, 12).padding(.vertical, 2)
    }

    private func group(_ group: AppExtension.Group, title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localization.L(title))
                .font(AppDesign.Font.footnote.weight(.semibold)).foregroundColor(.secondary)
                .padding(.horizontal, AppDesign.Spacing.sm).padding(.top, AppDesign.Spacing.md)
            ForEach(AppExtension.catalog.filter { $0.group == group }, id: \.uniqueId) { ext in
                row(ext)
                separator
            }
        }
    }

    private func row(_ ext: AppExtension) -> some View {
        let presence = ext.presence(in: viewModel.mods)
        return SplitRow(spacing: AppDesign.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppDesign.Spacing.xs) {
                    Text(ext.name).font(AppDesign.Font.body)
                    if ext.recommended {
                        Text(localization.L(L10n.AppExtensions.recommended))
                            .font(AppDesign.Font.caption).foregroundColor(.secondary)
                    }
                }
                Text(localization.L(ext.purposeKey))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                status(presence)
                if ext.source == .app, let probeFailure {
                    Text(probeFailure).font(AppDesign.Font.footnote).foregroundColor(AppDesign.Color.error)
                }
            }
        } trailing: {
            action(ext, presence: presence)
        }
        .padding(.vertical, AppDesign.Spacing.xs)
        .padding(.horizontal, AppDesign.Spacing.sm)
    }

    private func status(_ presence: ModPresence) -> some View {
        let (key, glyph, tint): (String, String, Color) = switch presence {
        case .enabled: (L10n.AppExtensions.statusEnabled, "checkmark.circle.fill", AppDesign.Color.installed)
        case .paused: (L10n.AppExtensions.statusPaused, "minus.circle.fill", AppDesign.Color.warning)
        case .absent: (L10n.AppExtensions.statusAbsent, "xmark.circle.fill", AppDesign.Color.error)
        }
        let version = switch presence {
        case .enabled(_, let v), .paused(_, let v): v.isEmpty ? "" : " · v\(v)"
        case .absent: ""
        }
        return Label(localization.L(key) + version, systemImage: glyph)
            .font(AppDesign.Font.footnote).foregroundStyle(tint)
    }

    @ViewBuilder
    private func action(_ ext: AppExtension, presence: ModPresence) -> some View {
        switch ext.source {
        case .nexus:
            if let url = ext.installURL {
                Button(localization.L(presence == .absent ? L10n.AppExtensions.install
                                                           : L10n.AppExtensions.nexusPage)) {
                    NSWorkspace.shared.open(url)
                }
                .help(url.absoluteString)
            }
        case .smapi:
            if presence == .absent {
                Button(localization.L(L10n.AppExtensions.reinstallSmapi)) {
                    viewModel.navigationStore.pendingSettingsSection = .smapi
                }
            }
        case .app:
            let bundled = ProbeBundle.bundledFolder(resourcesURL: Bundle.main.resourceURL)
                .flatMap(ProbeBundle.version(ofFolder:))
            switch ProbeBundle.action(bundled: bundled, presence: presence) {
            case .install:
                Button(localization.L(L10n.AppExtensions.install)) { installProbe() }
            case .update:
                Button(localization.L(L10n.AppExtensions.update)) { installProbe() }
            case .unavailable, .upToDate, .newerInstalled:
                EmptyView()
            }
        }
    }

    private func installProbe() {
        guard !viewModel.isGameRunning() else {
            probeFailure = localization.L(L10n.Performance.gameRunning); return
        }
        do {
            try ProbeBundle.installBundled(resourcesURL: Bundle.main.resourceURL,
                                           gameDir: viewModel.gameDir, mods: viewModel.mods)
            probeFailure = nil
            viewModel.scanMods(gameDir: viewModel.gameDir)
        } catch ProbeBundle.InstallError.noGameFolder {
            probeFailure = localization.L(L10n.Settings.gameDirNotSet)
        } catch {
            probeFailure = String(format: localization.L(L10n.Performance.probeInstallFailed),
                                  error is ProbeBundle.InstallError ? ProbeBundle.folderName : error.localizedDescription)
        }
    }
}
