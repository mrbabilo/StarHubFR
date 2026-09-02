import SwiftUI

// MARK: - System Alerts View

/// Dedicated view for SMAPI system errors. These are also logged to the
/// Journaux tab (see StarHubTHViewModel.parseSMAPILog) so they remain
/// consultable after this banner is dismissed.
struct SystemAlertsView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @Binding var currentTab: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if vm.smapiErrors.isEmpty {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 28))
                            // Cette page parle du journal SMAPI, pas des mises
                            // à jour Nexus : l'ancienne clé disait « tous les
                            // mods sont à jour », hors sujet ici.
                            Text(vm.L(L10n.Updates.noAlerts))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                        .background(Color.green.opacity(0.06))
                        .cornerRadius(12)
                        // Vert ne veut pas dire véridique pour toujours : le
                        // journal date de la dernière partie, et l'utilisateur
                        // qui vient d'installer un mod veut pouvoir revoir.
                        recheckLogButton
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 16))
                            let errorText = String(format: vm.L(L10n.Updates.errorsFound), vm.smapiErrors.count)
                            Text(errorText)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                            recheckLogButton
                            Button(action: { currentTab = "Logs" }) {
                                Text(vm.L(L10n.Updates.viewLogs))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .pointingHandCursor()
                        }

                        Text(vm.L(L10n.Updates.errorDescription))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)

                        ForEach(vm.smapiErrors, id: \.self) { error in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color.secondary.opacity(0.5))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 6)
                                Text(error)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(12)
                }

                KeybindReportSection(vm: vm, currentTab: $currentTab)

                ModConflictSection(vm: vm)
            }
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Relit le journal SMAPI sans rescaner le parc — la page ne montre que
    /// ce que dit le journal, c'est lui seul qu'il faut relire.
    @ViewBuilder
    private var recheckLogButton: some View {
        HStack(spacing: 6) {
            Button(action: { vm.refreshSmapiLog() }) {
                Label(vm.L(L10n.Updates.recheckLog), systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .pointingHandCursor()
            .disabled(vm.isRefreshingSmapiLog)
            if vm.isRefreshingSmapiLog {
                ProgressView().controlSize(.small)
            }
        }
    }
}
