import SwiftUI

/// La page « Diagnostic & Performances » (D4-T4 §3a) : Santé · Journal,
/// ouverte sur Santé. Le segment vit dans `NavigationStore` pour survivre au
/// changement de page, comme dans `BackupsView` (I-T8).
///
/// **À la différence de `BackupsView`, les onglets restent montés** : un
/// `switch` détruirait à chaque changement d'onglet les filtres, la recherche
/// et le défilement du journal, la carte repliée, les listes de la bissection
/// — tout ce que la page gardait tant qu'on y restait (consigne de l'auteur,
/// 2026-09-28 : ne perdre aucune fonctionnalité).
///
/// ⌘F : sur Journal, le champ de recherche porte son propre raccourci
/// (`searchFieldShortcut`) ; sur Santé, le champ est caché et désactivé, donc
/// cet hôte lie ⌘F — **seulement hors de Journal**, pour qu'un seul liage
/// soit actif à la fois (piège ⌘K du 2026-09-09) — et bascule sur Journal.
struct DiagnosticsView: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    private var segment: Binding<DiagnosticsSegment> {
        Binding(get: { viewModel.navigationStore.diagnosticsSegment },
                set: { viewModel.navigationStore.diagnosticsSegment = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: segment) {
                ForEach(DiagnosticsSegment.allCases, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(searchShortcutOutsideJournal)

            Divider()

            ZStack {
                tab(.health) {
                    DiagnosticsHealthView(viewModel: viewModel, localization: localization)
                }
                tab(.journal) {
                    VStack(spacing: 0) {
                        DiagnosticsHealthStrip(viewModel: viewModel, localization: localization)
                        Divider()
                        LogsView(viewModel: viewModel, localization: localization)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Un onglet non affiché : invisible, sans clic ni raccourci (un bouton
    /// désactivé ne déclenche pas son `keyboardShortcut` — ⌘F n'a donc
    /// qu'un liage actif), hors de VoiceOver. Son état survit. L'onglet
    /// affiché passe **au-dessus** (`zIndex`) : les vues AppKit du journal
    /// caché (défilement, texte sélectionnable qui impose le curseur I-beam)
    /// ne doivent pas s'interposer devant Santé.
    private func tab<Content: View>(_ value: DiagnosticsSegment,
                                    @ViewBuilder content: () -> Content) -> some View {
        let shown = viewModel.navigationStore.diagnosticsSegment == value
        return content()
            .zIndex(shown ? 1 : 0)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .disabled(!shown)
            .accessibilityHidden(!shown)
    }

    @ViewBuilder
    private var searchShortcutOutsideJournal: some View {
        if viewModel.navigationStore.diagnosticsSegment != .journal {
            Button("") { viewModel.navigationStore.focusLogSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func label(_ value: DiagnosticsSegment) -> String {
        switch value {
        case .health:  return localization.L(L10n.Logs.segmentHealth)
        case .journal: return localization.L(L10n.Logs.segmentJournal)
        case .performance: return localization.L(L10n.Logs.segmentPerformance)
        }
    }
}
