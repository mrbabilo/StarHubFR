import SwiftUI
import UniformTypeIdentifiers

/// P5-5a (audit UX 2026-10-16) — une archive déposée sur la fenêtre ouvre la
/// feuille d'installation sur elle, depuis n'importe quelle page. Plusieurs
/// archives : la première, puis « Archive suivante (n) » du bilan. Même file
/// (`pendingDropQueue`) et même tri aux octets que le dépôt dans la feuille ;
/// la feuille reste le point de décision, rien ne s'installe sans elle.
struct ArchiveDropTarget: ViewModifier {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var isTargeted = false

    private var refusal: ArchiveDropRefusal? { viewModel.archiveDropRefusal }

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                // Refusé : le bandeau a dit pourquoi pendant le survol.
                guard refusal == nil else { return false }
                DroppedFileURLs.load(from: providers) { urls in present(urls) }
                return true
            }
            .overlay { if isTargeted { banner } }
    }

    /// Le chargement des URL est asynchrone : la garde se relit à l'arrivée.
    private func present(_ urls: [URL]) { viewModel.presentDroppedArchives(urls) }

    private var banner: some View {
        let refused = refusal
        return ZStack {
            RoundedRectangle(cornerRadius: AppDesign.Radius.lg)
                .strokeBorder(refused == nil ? Color.accentColor : AppDesign.Color.warning, lineWidth: 2)
                .background(Color.accentColor.opacity(refused == nil ? 0.08 : 0))
            Label(refused.map { $0.message(localization) } ?? localization.L(L10n.ArchiveDrop.hint),
                  systemImage: refused == nil ? "arrow.down.doc.fill" : "nosign")
                .font(AppDesign.Font.headline)
                .multilineTextAlignment(.center)
                .padding(AppDesign.Spacing.lg)
                .frame(maxWidth: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDesign.Radius.md))
        }
        .padding(AppDesign.Spacing.md)
        .allowsHitTesting(false)
    }
}

extension View {
    func archiveDropTarget(viewModel: StarHubTHViewModel, localization: LocalizationStore) -> some View {
        modifier(ArchiveDropTarget(viewModel: viewModel, localization: localization))
    }
}

/// Les URL d'un dépôt, dans l'ordre des providers : chaque archive a sa fiche.
/// Partagé par la fenêtre et la feuille d'installation.
enum DroppedFileURLs {
    @MainActor
    static func load(from providers: [NSItemProvider], accumulated: [URL] = [],
                     completion: @escaping @MainActor @Sendable ([URL]) -> Void) {
        guard let provider = providers.first else { completion(accumulated); return }
        // `NSItemProvider` non `Sendable` : la file se transporte explicitement
        // (P5-L6), consommée une à une sur l'acteur.
        nonisolated(unsafe) let rest = Array(providers.dropFirst())
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var urls = accumulated
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                urls.append(url)
            }
            let carried = urls
            Task { @MainActor in
                load(from: rest, accumulated: carried, completion: completion)
            }
        }
    }
}
