import SwiftUI

/// La page « Diagnostic & Performances » (D4-T4 §3a) : Santé · Journal ·
/// Performances (plan 4),
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
    /// L'onglet Performances (D4-T4 plan 4) : possédé ici, jamais par le
    /// ViewModel ; l'onglet reste monté, la paire choisie survit.
    @State private var performance = ProbePerformanceStore()

    private var segment: Binding<DiagnosticsSegment> {
        Binding(get: { viewModel.navigationStore.diagnosticsSegment },
                set: { viewModel.navigationStore.diagnosticsSegment = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            // En-tête commun des pages (audit UX 2026-10-02) : la version de
            // SMAPI et l'âge du journal que les trois onglets lisent.
            PageHeader(icon: "terminal.fill", title: localization.L(L10n.Logs.logs),
                       subtitle: headerSummary)
                .padding(.horizontal, AppDesign.Spacing.xl)
                .padding(.top, AppDesign.Spacing.md)
            Picker("", selection: segment) {
                ForEach(DiagnosticsSegment.allCases, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, AppDesign.Spacing.xl)
            .padding(.vertical, AppDesign.Spacing.sm)
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
                tab(.performance) {
                    PerformanceView(viewModel: viewModel, localization: localization, store: performance)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppDesign.Color.windowBg)
    }

    /// « SMAPI 4.1.10 · journal du 02/10 15:20 » : ce que les onglets lisent.
    private var headerSummary: String {
        let smapi = viewModel.smapiInstalledVersion.map { "SMAPI \($0)" }
            ?? localization.L(L10n.Logs.headerNoSmapi)
        guard let date = viewModel.smapiLogDate else {
            return "\(smapi) · \(localization.L(L10n.Logs.headerNoLog))"
        }
        return "\(smapi) · " + String(format: localization.L(L10n.Logs.headerLogDate),
                                         DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short))
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
