import SwiftUI

/// Les deux avertissements de la feuille d'installation qui portent sur les
/// dépendances, posés en une ligne dans `InstallPreview` (verrouillé par le
/// cliquet de taille) :
/// - A1-T1 — l'archive ne porte pas l'identifiant attendu : le MAIN le plus
///   récent d'une page n'est pas toujours celui qui convient (variantes,
///   fork). On n'installe pas en silence — « Installer » reste possible à
///   dessein ;
/// - l'archive livre un mod plus ancien que ce qu'exige un mod actif
///   (`DependencyVersionCheck`) : SMAPI refuserait ce dernier. Même choix —
///   prévenir, laisser décider — et un lien de recherche, la version qui
///   convient vivant souvent sur une autre page (fork).
struct DependencyArchiveWarnings: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let detectedMods: [DetectedMod]
    /// Les identifiants attendus d'un téléchargement de dépendance ; `nil`
    /// hors de ce cas.
    let expectedIds: [String]?

    /// Le verdict des versions minimales parcourt tout le parc : calculé une
    /// fois par état du parc (`ScanStore.modsRevision`) et par contenu
    /// d'archive, pas à chaque rendu de la feuille. Référence non observée : la remplir dans `body` ne
    /// redemande pas de rendu.
    private final class UnmetCache {
        var key: String?
        var value: [DependencyVersionCheck.Unmet] = []
    }
    @State private var cache = UnmetCache()

    private var unmet: [DependencyVersionCheck.Unmet] {
        let detected = detectedMods.map { ($0.uniqueId, $0.manifest.name, $0.manifest.version) }
        let key = "\(viewModel.scanStore.modsRevision)|" + detected.map { "\($0.0)@\($0.2)" }.joined(separator: ",")
        if cache.key != key {
            cache.value = DependencyVersionCheck.unmet(detected: detected, mods: viewModel.scanStore.mods)
            cache.key = key
        }
        return cache.value
    }

    var body: some View {
        let missing = expectedIds.map {
            MissingDependencies.absent(expected: $0, in: detectedMods.map(\.uniqueId))
        } ?? []
        let unmet = unmet
        if !missing.isEmpty || !unmet.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !missing.isEmpty {
                    warning(String(format: localization.L(L10n.ModInstall.expectedMissing),
                                   missing.joined(separator: ", ")))
                }
                ForEach(unmet) { entry in
                    warning(String(format: localization.L(L10n.ModInstall.dependencyTooOld),
                                   entry.requiredBy, entry.name, entry.required, entry.found))
                    if let url = MissingDependencies.searchPage(for: entry.name) {
                        Link(localization.L(L10n.ModInstall.dependencyTooOldSearch), destination: url)
                            .font(AppDesign.Font.caption)
                            .pointingHandCursor()
                    }
                }
            }
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(AppDesign.Font.caption)
            .foregroundColor(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
