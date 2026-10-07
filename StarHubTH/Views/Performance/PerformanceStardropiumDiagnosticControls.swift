import AppKit
import SwiftUI

struct PerformanceStardropiumDiagnosticControls: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: SloDiagnosticSessionStore
    let runtime: () -> SloDiagnosticRuntime
    @State private var preparation: SloDiagnosticPreparation?
    @State private var pendingConfirmation: PerformanceDiagnosticConfirmation?
    @State private var installFailed = false
    private typealias Keys = L10n.StardropiumDiagnostic

    private var activity: SloDiagnosticNexusActivity {
        let id = PerformanceDiagnosticKind.stardropium.nexusId
        if viewModel.downloadingNexusModId == id { return .downloading(modId: id) }
        if viewModel.pendingDownloadedZip != nil, viewModel.pendingNexusSource?.modId == id {
            return .awaitingInstall(modId: id)
        }
        return .idle
    }
    private var presentation: SloDiagnosticPresentation {
        .make(state: store.state, directDownloadUnavailable: viewModel.nexusDirectDownloadUnavailable,
              nexusActivity: activity, kind: .stardropium)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(statusKey)).font(AppDesign.Font.body(.semibold))
            Text(localization.L(detailKey)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            if let action = presentation.action {
                AdaptiveLabels {
                    Button { perform(action) } label: {
                        Label(localization.L(actionKey(action)), systemImage: actionIcon(action))
                    }.buttonStyle(.borderedProminent).help(localization.L(actionKey(action)))
                }
            }
            if installFailed {
                Text(localization.L(Keys.installFailed)).foregroundStyle(AppDesign.Color.warning)
            }
        }
        .sheet(isPresented: Binding(get: { preparation != nil }, set: { if !$0 { preparation = nil } })) {
            if let value = preparation { confirmation(value) }
        }
        .alert(localization.L(pendingConfirmation == .restore
                             ? L10n.PerformanceSloDiagnostic.restoreConfirmTitle
                             : L10n.PerformanceSloDiagnostic.probeConfirmTitle),
               isPresented: Binding(get: { pendingConfirmation != nil },
                                    set: { if !$0 { pendingConfirmation = nil } }),
               presenting: pendingConfirmation) { confirmation in
            switch confirmation {
            case .installProbe:
                Button(localization.L(L10n.PerformanceSloDiagnostic.installProbe)) { installProbe() }
            case .restore:
                Button(localization.L(L10n.PerformanceSloDiagnostic.restore), role: .destructive) {
                    Task { await store.confirmOverwriteAndRestore(runtime: runtime()) }
                }
            }
            Button(localization.L(L10n.PerformanceSloDiagnostic.cancel), role: .cancel) { }
        } message: { confirmation in
            if confirmation == .restore {
                Text(localization.L(Keys.restoreBody))
            }
        }
    }
    private var statusKey: String {
        switch presentation.kind {
        case .missing: Keys.missing
        case .downloading: Keys.downloading
        case .awaitingInstall: Keys.awaitingInstall
        case .paused, .ready: Keys.ready
        case .incompatible: Keys.incompatible
        case .probeRequired: L10n.PerformanceSloDiagnostic.probeRequired
        case .blocked: L10n.PerformanceSloDiagnostic.blocked
        case .preparing: L10n.PerformanceSloDiagnostic.preparing
        case .waitingForGame: L10n.PerformanceSloDiagnostic.waiting
        case .running: L10n.PerformanceSloDiagnostic.running
        case .restoring: L10n.PerformanceSloDiagnostic.restoring
        case .recovery: L10n.PerformanceSloDiagnostic.recovery
        case .failed: L10n.PerformanceSloDiagnostic.failed
        case .report: Keys.finished
        }
    }
    private var detailKey: String {
        if case .unavailable(.blocked("slo-diagnostic-pending")) = store.state {
            return L10n.PerformanceSloDiagnostic.pendingSlo
        }
        if case .recoveryBlocked(.gameDirectoryChanged) = store.state { return Keys.directoryChanged }
        if case .failed(.busy("game-directory-changed")) = store.state { return Keys.directoryChanged }
        if case .unavailable(.blocked("vanilla")) = store.state { return Keys.vanilla }
        if case .failed(let failure) = store.state {
            switch failure {
            case .snapshotWrite, .configWrite, .snapshotUnreadable: return Keys.writeFailed
            case .vanillaProfile: return Keys.vanilla
            case .launch: return Keys.launchFailed
            default: break
            }
        }
        return switch presentation.kind {
        case .missing: Keys.missingDetail
        case .incompatible: Keys.incompatibleDetail
        case .recovery: L10n.PerformanceSloDiagnostic.recoveryDetail
        case .blocked, .failed: Keys.blockedDetail
        case .running, .waitingForGame: Keys.playHint
        case .report: Keys.finishedDetail
        default: Keys.preparationDetail
        }
    }
    private func actionKey(_ action: SloDiagnosticPresentationAction) -> String {
        switch action {
        case .download: Keys.install
        case .openPage: Keys.openNexus
        case .installProbe: L10n.PerformanceSloDiagnostic.installProbe
        case .confirm: Keys.measure
        case .retry: L10n.PerformanceSloDiagnostic.retry
        case .restore: L10n.PerformanceSloDiagnostic.restore
        }
    }
    private func actionIcon(_ action: SloDiagnosticPresentationAction) -> String {
        switch action {
        case .download, .installProbe: "arrow.down.circle"
        case .openPage: "safari"
        case .confirm: "play.fill"
        case .retry: "arrow.clockwise"
        case .restore: "arrow.uturn.backward.circle"
        }
    }
    private func perform(_ action: SloDiagnosticPresentationAction) {
        switch action {
        case .download(let id, let uniqueId): viewModel.expectAndDownloadNexusMod(nexusId: id, uniqueId: uniqueId)
        case .openPage(let url, let id, let uniqueId):
            viewModel.expectNexusMod(nexusId: id, uniqueId: uniqueId); NSWorkspace.shared.open(url)
        case .installProbe: pendingConfirmation = .installProbe
        case .confirm(let value): preparation = value
        case .restore: pendingConfirmation = .restore
        case .retry:
            Task {
                let game = URL(fileURLWithPath: viewModel.gameDir)
                await store.reload(mods: viewModel.mods, gameDir: game, runtime: runtime(), preserveReport: false)
            }
        }
    }
    private func confirmation(_ value: SloDiagnosticPreparation) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(Keys.measure)).font(AppDesign.Font.viewTitle)
            Text(localization.L(Keys.preparationDetail))
            Text(localization.L(Keys.configDetail))
            if !value.slo.activatedSiblingNames.isEmpty {
                Text(String(format: localization.L(L10n.PerformanceSloDiagnostic.confirmSiblings),
                            value.slo.activatedSiblingNames.joined(separator: ", ")))
            }
            Text(localization.L(L10n.PerformanceSloDiagnostic.confirmRestore))
            Text(localization.L(Keys.playHint)).font(AppDesign.Font.footnote)
            HStack {
                Button(localization.L(L10n.PerformanceSloDiagnostic.cancel)) { preparation = nil }
                Spacer()
                Button(localization.L(L10n.PerformanceSloDiagnostic.launch)) {
                    preparation = nil
                    Task { await store.start(value, runtime: runtime()) }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(AppDesign.Spacing.xl).frame(minWidth: 460, maxWidth: 620)
    }
    private func installProbe() {
        let presence = ModPresence.resolve(uniqueId: ModPresence.probeId, in: viewModel.mods)
        let root = URL(fileURLWithPath: viewModel.gameDir).appendingPathComponent("Mods")
        guard let source = ProbeBundle.bundledFolder(resourcesURL: Bundle.main.resourceURL),
              let target = ProbeBundle.target(modsRoot: root, presence: presence) else { installFailed = true; return }
        do {
            try ProbeBundle.install(from: source, into: target)
            installFailed = false
            viewModel.scanMods(gameDir: viewModel.gameDir)
        } catch { installFailed = true }
    }
}
