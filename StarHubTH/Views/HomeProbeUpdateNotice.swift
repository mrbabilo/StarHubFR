import SwiftUI

/// L'accueil propose la mise à jour de la sonde dès que l'app en livre une
/// plus récente que celle du dossier Mods : sinon on ne la découvrait qu'en
/// ouvrant Performances, et des correctifs de la sonde (0.9.29, 0.9.30)
/// restaient sans effet. Même geste que la carte Sonde de Performances
/// (`ProbeBundle`), même confirmation ; rien n'apparaît hors mise à jour.
struct HomeProbeUpdateNotice: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var confirming = false
    @State private var failure: String?
    @State private var installedNote: String?

    private var update: (from: String, to: String)? {
        let bundled = ProbeBundle.bundledFolder(resourcesURL: Bundle.main.resourceURL)
            .flatMap(ProbeBundle.version(ofFolder:))
        let presence = ModPresence.resolve(uniqueId: ModPresence.probeId, in: viewModel.mods)
        guard case .update(let from, let to) = ProbeBundle.action(bundled: bundled, presence: presence) else { return nil }
        return (from, to)
    }

    var body: some View {
        if let installedNote {
            notice { Text(installedNote).font(AppDesign.Font.caption).foregroundColor(.secondary) }
        } else if let update {
            notice {
                VStack(alignment: .leading, spacing: 10) {
                    Text(localization.L(L10n.Home.probeUpdateBody))
                        .font(AppDesign.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(String(format: localization.L(L10n.Performance.probeUpdate), update.from, update.to)) {
                        failure = nil; confirming = true
                    }
                    .buttonStyle(.borderedProminent).focusRing(cornerRadius: 5).controlSize(.small)
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .font(AppDesign.Font.footnote).foregroundColor(AppDesign.Color.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .confirmationDialog(localization.L(L10n.Performance.probeInstallConfirmTitle),
                                isPresented: $confirming) {
                Button(String(format: localization.L(L10n.Performance.probeUpdate), update.from, update.to)) {
                    install(update.to)
                }
            } message: {
                Text(String(format: localization.L(L10n.Performance.probeInstallConfirm), ProbeBundle.folderName))
            }
        }
    }

    private func notice<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        StandardSection(title: localization.L(L10n.Performance.probeTitle),
                        icon: ("gauge.with.dots.needle.67percent", AppDesign.Color.accent)) {
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 40)
    }

    private func install(_ version: String) {
        guard !viewModel.isGameRunning() else {
            failure = localization.L(L10n.Performance.gameRunning); return
        }
        do {
            try ProbeBundle.installBundled(resourcesURL: Bundle.main.resourceURL,
                                           gameDir: viewModel.gameDir, mods: viewModel.mods)
            installedNote = String(format: localization.L(L10n.Performance.probeUpdatedRelaunch), version)
            Task { await viewModel.rescanInBackground(includeRepair: false) } // X125
        } catch {
            failure = String(format: localization.L(L10n.Performance.probeInstallFailed),
                             error is ProbeBundle.InstallError ? ProbeBundle.folderName : error.localizedDescription)
        }
    }
}
