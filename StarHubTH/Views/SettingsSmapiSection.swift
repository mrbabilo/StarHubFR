import SwiftUI

/// Réglages › SMAPI : état, installation, désinstallation. Sorti de
/// `SettingsView` (plafond de taille) pour porter la confirmation de
/// « Désinstaller » : un clic suffisait à retirer SMAPI (audit UX E10).
struct SettingsSmapiSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject var smapiInstaller: SmapiInstaller
    @State private var confirmUninstall = false

    init(vm model: StarHubTHViewModel, localization: LocalizationStore) {
        self.viewModel = model
        self.localization = localization
        self.smapiInstaller = model.smapiInstaller
    }

    var body: some View {
        // SMAPI Settings
        StandardSection(title: localization.L(L10n.Home.smapiManager), icon: ("shippingbox.fill", .indigo)) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.L(L10n.Home.smapiStatus))
                            .font(AppDesign.Font.body)
                        if let version = viewModel.smapiInstalledVersion {
                            Text(String(format: localization.L(L10n.Home.smapiInstalled), version))
                                .font(AppDesign.Font.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(localization.L(L10n.Home.smapiNotInstalled))
                                .font(AppDesign.Font.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if smapiInstaller.isInstalling {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    } else if viewModel.smapiInstalledVersion == nil {
                        Button(localization.L(L10n.Home.installSmapi)) { viewModel.installSmapi() }
                    } else {
                        Button(localization.L(L10n.Home.uninstall), role: .destructive) { confirmUninstall = true }
                    }
                }

                if smapiInstaller.isInstalling {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: smapiInstaller.progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                            .animation(Motion.animation(.easeInOut), value: smapiInstaller.progress)
                        Text(localization.L(smapiInstaller.statusMessage))
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 12)
                }
            }
        }
        .confirmationDialog(localization.L(L10n.Home.uninstallConfirmTitle), isPresented: $confirmUninstall) {
            Button(localization.L(L10n.Home.uninstall), role: .destructive) { viewModel.uninstallSmapi() }
        } message: {
            Text(localization.L(L10n.Home.uninstallConfirmMessage))
        }
    }
}
