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

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(get: { vm.navigationStore.backupsSegment },
                                          set: { vm.navigationStore.backupsSegment = $0 })) {
                ForEach(BackupsSegment.allCases, id: \.self) { segment in
                    Text(label(segment)).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            switch vm.navigationStore.backupsSegment {
            case .install:
                ModInstallBackupsView(vm: vm, localization: localization)
            case .config:
                ModConfigBackupsView(vm: vm, localization: localization)
            case .files:
                RecoverableFilesView(vm: vm, localization: localization)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func label(_ segment: BackupsSegment) -> String {
        switch segment {
        case .install: return localization.L(L10n.Backups.segmentInstall)
        case .config:  return localization.L(L10n.Backups.segmentConfig)
        case .files:   return localization.L(L10n.Backups.segmentFiles)
        }
    }
}
