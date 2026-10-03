import SwiftUI

/// Sous une ligne de mise à jour : la version proposée est déjà installée,
/// sous un nouvel identifiant ou dans le mod qui a remplacé celui-ci
/// (`UpdateAlreadyInstalled`, Core, testé). Muette sinon.
struct UpdateAlreadyInstalledNote: View {
    let update: NexusUpdateChecker.ModUpdate
    let mods: [ModItem]
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        if let text {
            Label(text, systemImage: "checkmark.seal")
                .font(AppDesign.Font.footnote)
                .foregroundColor(AppDesign.Color.info)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var text: String? {
        switch UpdateAlreadyInstalled.explain(uniqueId: update.uniqueId, nexusModId: update.nexusModId,
                                              latestVersion: update.latestVersion, in: mods) {
        case .renamed(_, let uniqueId, let version):
            String(format: localization.L(L10n.Updates.alreadyInstalledRenamed), version, uniqueId)
        case .supersededBy(let name, let version):
            String(format: localization.L(L10n.Updates.alreadyInstalledSuperseded), name, version)
        case nil:
            nil
        }
    }
}
