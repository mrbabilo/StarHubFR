import SwiftUI

/// R5 — les états d'avant chaque geste de masse, et le retour à l'un d'eux.
///
/// La différence avec l'état actuel ne se calcule qu'à la confirmation : une
/// ligne par instantané (50 au plus) fois ~900 mods à chaque rendu ne
/// servirait à rien tant que personne ne clique.
struct ActivationHistorySection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var showsAll = false
    @State private var pendingRestore: PendingRestore?

    private struct PendingRestore {
        let snapshot: ActivationSnapshot
        let enabling: Int
        let pausing: Int
    }

    private static let collapsedCount = 5

    var body: some View {
        let snapshots = viewModel.activationHistory.snapshots
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            SectionHeader(title: localization.L(L10n.ActivationHistory.title),
                          countText: "\(snapshots.count)",
                          moreTitle: snapshots.count > Self.collapsedCount
                              ? localization.L(showsAll ? L10n.ActivationHistory.showLess
                                                        : L10n.ActivationHistory.showAll)
                              : nil,
                          moreDisabled: false) { showsAll.toggle() }
            Text(localization.L(L10n.ActivationHistory.subtitle))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let failure = viewModel.activationHistory.failure {
                Text(String(format: localization.L(L10n.ActivationHistory.writeFailed), failure))
                    .font(.caption).foregroundStyle(AppDesign.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if snapshots.isEmpty {
                Text(localization.L(L10n.ActivationHistory.empty))
                    .font(AppDesign.Font.body).foregroundStyle(.secondary)
            } else {
                ForEach(showsAll ? snapshots : Array(snapshots.prefix(Self.collapsedCount))) { snapshot in
                    row(snapshot).cardSurface(padding: AppDesign.Spacing.sm)
                }
            }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }), titleVisibility: .visible) {
            Button(localization.L(L10n.ActivationHistory.confirmButton)) {
                if let pending = pendingRestore { viewModel.restoreActivation(pending.snapshot) }
                pendingRestore = nil
            }
            Button(localization.L(L10n.Profiles.cancel), role: .cancel) { pendingRestore = nil }
        } message: {
            Text(confirmMessage)
        }
    }

    private func row(_ snapshot: ActivationSnapshot) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Button {
                viewModel.activationHistory.setPinned(snapshot.id, !snapshot.pinned)
            } label: {
                Image(systemName: snapshot.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(snapshot.pinned ? AppDesign.Color.accent : .secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(localization.L(snapshot.pinned ? L10n.ActivationHistory.unpinHelp
                                                 : L10n.ActivationHistory.pinHelp))
            VStack(alignment: .leading, spacing: 2) {
                Text(gestureLabel(snapshot)).font(AppDesign.Font.body).lineLimit(2)
                Text(snapshot.takenAt.formatted(date: .abbreviated, time: .shortened)
                     + " · " + String(format: localization.L(L10n.ActivationHistory.activeCount),
                                      snapshot.enabledFolders.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: AppDesign.Spacing.sm)
            Button(localization.L(L10n.ActivationHistory.restore)) {
                let moves = ActivationRestore.moves(to: snapshot, installed: viewModel.scanStore.mods)
                pendingRestore = PendingRestore(
                    snapshot: snapshot,
                    enabling: moves.filter { $0.direction == .enable }.count,
                    pausing: moves.filter { $0.direction == .disable }.count)
            }
            .disabled(viewModel.bulkToggleProgress != nil || viewModel.isApplyingProfile)
            .help(localization.L(L10n.ActivationHistory.restoreHelp))
        }
    }

    private func gestureLabel(_ snapshot: ActivationSnapshot) -> String {
        let detail = snapshot.detail ?? ""
        switch snapshot.gesture {
        case .bulkEnable: return String(format: localization.L(L10n.ActivationHistory.gestureBulkEnable), detail)
        case .bulkDisable: return String(format: localization.L(L10n.ActivationHistory.gestureBulkDisable), detail)
        case .profile: return String(format: localization.L(L10n.ActivationHistory.gestureProfile), detail)
        case .restore: return localization.L(L10n.ActivationHistory.gestureRestore)
        }
    }

    private var confirmTitle: String {
        guard let pending = pendingRestore else { return "" }
        return String(format: localization.L(L10n.ActivationHistory.confirmTitle),
                      pending.snapshot.takenAt.formatted(date: .abbreviated, time: .shortened))
    }

    private var confirmMessage: String {
        guard let pending = pendingRestore else { return "" }
        var message = String(format: localization.L(L10n.ActivationHistory.confirmMessage),
                             pending.enabling, pending.pausing)
        if let active = viewModel.activeProfileId, active != pending.snapshot.activeProfileId,
           let name = viewModel.modProfiles.first(where: { $0.id == active })?.name {
            message += "\n\n" + String(format: localization.L(L10n.ActivationHistory.leavesProfile), name)
        }
        return message
    }
}
