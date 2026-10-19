import SwiftUI

/// La page « Sauvegardes des mods » (I-T8) : sauvegardes d'installation, de
/// configuration et fichiers récupérables, autrefois deux entrées de la barre
/// latérale et une feuille ouverte depuis la première.
///
/// Hôte seulement : chaque segment est la vue qui existait déjà, inchangée
/// sauf la feuille devenue segment. Le segment choisi vit dans
/// `NavigationStore` pour survivre au changement d'onglet.
///
/// Le segment Fichiers lit aussi les seules copies du rapport d'Entretien
/// (toutes les sessions, mods désinstallés compris) ; l'Entretien y renvoie
/// au lieu de dupliquer « Remettre le fichier ».
struct BackupsView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// R8 — le mod demandé par l'éditeur de config ; vit le temps de la page.
    @State private var configFilter: String?

    var body: some View {
        VStack(spacing: 0) {
            // En-tête commun des pages (audit UX 2026-10-02) : un seul titre,
            // ici ; les segments gardent leurs actions, pas un second titre.
            PageHeader(icon: "arrow.uturn.backward.circle.fill",
                       title: localization.L(L10n.ModInstall.manageBackups),
                       subtitle: localization.L(L10n.Backups.pageSubtitle)) {
                // R1 — le poids et le geste qui le réduit vivent dans l'Entretien.
                Button(localization.L(L10n.Maintenance.backupsFreeSpaceLink)) { navigation.openMaintenance() }
                    .buttonStyle(.link).clickableCursor().focusRing(cornerRadius: 4)
                    .font(AppDesign.Font.footnote)
            }
                .padding(.horizontal, AppDesign.Spacing.xl)
                .padding(.top, AppDesign.Spacing.md)
            Picker(localization.L(L10n.A11y.backupsSegment), selection: Binding(get: { navigation.backupsSegment },
                                          set: { navigation.backupsSegment = $0 })) {
                ForEach(BackupsSegment.allCases, id: \.self) { segment in
                    Text(label(segment)).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, AppDesign.Spacing.xl)
            .padding(.vertical, AppDesign.Spacing.sm)

            Divider()

            switch navigation.backupsSegment {
            case .install:
                ModInstallBackupsView(vm: vm, localization: localization)
            case .config:
                ModConfigBackupsView(vm: vm, localization: localization, modFilter: $configFilter)
            case .files:
                RecoverableFilesView(viewModel: vm, localization: localization)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppDesign.Color.windowBg)
        .onAppear(perform: consumeConfigFocus)
        .onChange(of: navigation.pendingConfigBackupsFocus) { _, _ in consumeConfigFocus() }
    }

    private var navigation: NavigationStore { vm.navigationStore }

    /// Consommée une fois (patron `pendingLogFocus`) : revenir par la barre
    /// latérale ne garde pas le filtre.
    private func consumeConfigFocus() {
        guard let folder = navigation.pendingConfigBackupsFocus else { return }
        configFilter = folder
        navigation.pendingConfigBackupsFocus = nil
    }

    private func label(_ segment: BackupsSegment) -> String {
        switch segment {
        case .install: return localization.L(L10n.Backups.segmentInstall)
        case .config:  return localization.L(L10n.Backups.segmentConfig)
        case .files:   return localization.L(L10n.Backups.segmentFiles)
        }
    }
}
