import SwiftUI

/// L'alerte « une nouvelle release existe » — une sheet sur la fenêtre
/// principale, jamais une troisième fenêtre : le dépôt connaît les pièges du
/// cycle de vie des fenêtres au lancement, on n'en ajoute pas. Les deux
/// boutons acquittent le tag : l'alerte se montre une fois par release.
struct AppUpdateAlertView: View {
     var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let release: GitHubRelease

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: localization.L(L10n.AppUpdate.title), release.tagName))
                .font(.system(size: 16, weight: .semibold))
            if let excerpt = AppReleasePolicy.firstParagraph(of: release.body) {
                Text(excerpt)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button(localization.L(L10n.AppUpdate.later)) {
                    vm.acknowledgeRelease(release)
                }
                .keyboardShortcut(.cancelAction)
                Button(localization.L(L10n.AppUpdate.seeRelease)) {
                    if let url = URL(string: release.htmlURL) {
                        NSWorkspace.shared.open(url)
                    }
                    vm.acknowledgeRelease(release)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
