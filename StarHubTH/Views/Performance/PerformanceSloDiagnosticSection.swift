import AppKit
import Charts
import SwiftUI

/// D2-T4 — prépare une session SLO réversible puis présente les seules
/// observations déjà calculées par le Core.
struct PerformanceSloDiagnosticSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: SloDiagnosticSessionStore
    let runtime: () -> SloDiagnosticRuntime

    @State private var pendingPreparation: SloDiagnosticPreparation?
    @State private var pendingProbe: ProbeBundle.Action?
    @State private var confirmRecovery = false
    @State private var hoverDetail: String?
    @State private var selectedDetail: String?

    private var nexusActivity: SloDiagnosticNexusActivity {
        if viewModel.downloadingNexusModId == SloDiagnosticContract.nexusId {
            return .downloading(modId: SloDiagnosticContract.nexusId)
        }
        if viewModel.pendingDownloadedZip != nil,
           viewModel.pendingNexusSource?.modId == SloDiagnosticContract.nexusId {
            return .awaitingInstall(modId: SloDiagnosticContract.nexusId)
        }
        return .idle
    }

    private var presentation: SloDiagnosticPresentation {
        .make(state: store.state,
              directDownloadUnavailable: viewModel.nexusDirectDownloadUnavailable,
              nexusActivity: nexusActivity)
    }

    var body: some View {
        PerformanceCard {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                Label(localization.L(L10n.PerformanceSloDiagnostic.title),
                      systemImage: "waveform.path.ecg.rectangle")
                    .font(AppDesign.Font.headline(.semibold))
                Text(localization.L(L10n.PerformanceSloDiagnostic.subtitle))
                    .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                status
                if case .report(let report) = store.state { reportView(report) }
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingPreparation != nil },
            set: { if !$0 { pendingPreparation = nil } })) {
                if let preparation = pendingPreparation { confirmation(preparation) }
            }
        .confirmationDialog(localization.L(L10n.PerformanceSloDiagnostic.probeConfirmTitle),
                            isPresented: Binding(get: { pendingProbe != nil },
                                                 set: { if !$0 { pendingProbe = nil } })) {
            Button(localization.L(L10n.PerformanceSloDiagnostic.installProbe)) {
                installProbe()
            }
        }
        .confirmationDialog(localization.L(L10n.PerformanceSloDiagnostic.restoreConfirmTitle),
                            isPresented: $confirmRecovery) {
            Button(localization.L(L10n.PerformanceSloDiagnostic.restore), role: .destructive) {
                Task { await store.confirmOverwriteAndRestore(runtime: runtime()) }
            }
        } message: {
            Text(localization.L(L10n.PerformanceSloDiagnostic.restoreConfirmBody))
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Label(statusTitle, systemImage: statusIcon)
                .font(AppDesign.Font.body(.semibold))
                .foregroundStyle(statusTint)
            Text(statusDetail).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action = presentation.action {
                AdaptiveLabels {
                    Button { perform(action) } label: {
                        Label(actionTitle(action), systemImage: actionIcon(action))
                    }
                    .buttonStyle(.borderedProminent)
                    .help(actionTitle(action))
                }
            }
            if case .recoveryBlocked = store.state {
                Button {
                    let folder = URL(fileURLWithPath: viewModel.gameDir)
                        .appendingPathComponent("Mods", isDirectory: true)
                    NSWorkspace.shared.open(folder)
                } label: {
                    Label(localization.L(L10n.PerformanceSloDiagnostic.openMods),
                          systemImage: "folder")
                }.help(localization.L(L10n.PerformanceSloDiagnostic.openMods))
            }
        }
    }

    private var statusTitle: String {
        let key: String
        switch presentation.kind {
        case .missing: key = L10n.PerformanceSloDiagnostic.missing
        case .downloading: key = L10n.PerformanceSloDiagnostic.downloading
        case .awaitingInstall: key = L10n.PerformanceSloDiagnostic.awaitingInstall
        case .paused: key = L10n.PerformanceSloDiagnostic.paused
        case .ready: key = L10n.PerformanceSloDiagnostic.ready
        case .incompatible: key = L10n.PerformanceSloDiagnostic.incompatible
        case .probeRequired: key = L10n.PerformanceSloDiagnostic.probeRequired
        case .blocked: key = L10n.PerformanceSloDiagnostic.blocked
        case .preparing: key = L10n.PerformanceSloDiagnostic.preparing
        case .waitingForGame: key = L10n.PerformanceSloDiagnostic.waiting
        case .running: key = L10n.PerformanceSloDiagnostic.running
        case .restoring: key = L10n.PerformanceSloDiagnostic.restoring
        case .recovery: key = L10n.PerformanceSloDiagnostic.recovery
        case .failed: key = L10n.PerformanceSloDiagnostic.failed
        case .report: key = L10n.PerformanceSloDiagnostic.reportTitle
        }
        return localization.L(key)
    }

    private var statusDetail: String {
        switch presentation.kind {
        case .missing: return localization.L(L10n.PerformanceSloDiagnostic.missingDetail)
        case .paused: return localization.L(L10n.PerformanceSloDiagnostic.pausedDetail)
        case .ready: return localization.L(L10n.PerformanceSloDiagnostic.readyDetail)
        case .running: return localization.L(L10n.PerformanceSloDiagnostic.runningDetail)
        case .recovery: return localization.L(L10n.PerformanceSloDiagnostic.recoveryDetail)
        case .report:
            return store.lastReceipt?.completedAt.formatted(date: .abbreviated, time: .shortened)
                ?? localization.L(L10n.PerformanceSloDiagnostic.reportDetail)
        default: return localization.L(L10n.PerformanceSloDiagnostic.genericDetail)
        }
    }

    private var statusIcon: String {
        switch presentation.kind {
        case .ready, .report: "checkmark.circle.fill"
        case .running: "waveform"
        case .preparing, .waitingForGame, .restoring, .downloading: "clock.arrow.circlepath"
        case .missing, .paused, .probeRequired, .awaitingInstall: "info.circle"
        case .incompatible, .blocked, .recovery, .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusTint: Color {
        switch presentation.kind {
        case .ready, .report: AppDesign.Color.success
        case .incompatible, .recovery, .failed: AppDesign.Color.warning
        default: .secondary
        }
    }

    private func perform(_ action: SloDiagnosticPresentationAction) {
        switch action {
        case .download(let id, let uniqueId):
            viewModel.expectAndDownloadNexusMod(nexusId: id, uniqueId: uniqueId)
        case .openPage(let url, let id, let uniqueId):
            viewModel.expectNexusMod(nexusId: id, uniqueId: uniqueId)
            NSWorkspace.shared.open(url)
        case .installProbe(let action): pendingProbe = action
        case .confirm(let preparation): pendingPreparation = preparation
        case .retry:
            Task {
                await store.reload(mods: viewModel.mods,
                                   gameDir: URL(fileURLWithPath: viewModel.gameDir),
                                   runtime: runtime())
            }
        case .restore: confirmRecovery = true
        }
    }

    private func actionTitle(_ action: SloDiagnosticPresentationAction) -> String {
        switch action {
        case .download: localization.L(L10n.PerformanceSloDiagnostic.install)
        case .openPage: localization.L(L10n.PerformanceSloDiagnostic.openNexus)
        case .installProbe: localization.L(L10n.PerformanceSloDiagnostic.installProbe)
        case .confirm: localization.L(L10n.PerformanceSloDiagnostic.prepare)
        case .retry: localization.L(L10n.PerformanceSloDiagnostic.retry)
        case .restore: localization.L(L10n.PerformanceSloDiagnostic.restore)
        }
    }

    private func actionIcon(_ action: SloDiagnosticPresentationAction) -> String {
        switch action {
        case .download, .installProbe: "arrow.down.circle"
        case .openPage: "safari"
        case .confirm: "play.fill"
        case .retry: "arrow.clockwise"
        case .restore: "arrow.uturn.backward"
        }
    }

    private func confirmation(_ preparation: SloDiagnosticPreparation) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
            Text(localization.L(L10n.PerformanceSloDiagnostic.confirmTitle))
                .font(AppDesign.Font.viewTitle)
            Label(localization.L(L10n.PerformanceSloDiagnostic.confirmEnable),
                  systemImage: "checkmark.circle")
            Label(localization.L(L10n.PerformanceSloDiagnostic.confirmConfig),
                  systemImage: "slider.horizontal.3")
            if !preparation.slo.activatedSiblingNames.isEmpty {
                Text(String(format: localization.L(L10n.PerformanceSloDiagnostic.confirmSiblings),
                            preparation.slo.activatedSiblingNames.joined(separator: ", ")))
                    .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            }
            Label(localization.L(L10n.PerformanceSloDiagnostic.confirmRestore),
                  systemImage: "arrow.uturn.backward.circle")
            HStack {
                Button(localization.L(L10n.PerformanceSloDiagnostic.cancel)) {
                    pendingPreparation = nil
                }
                Spacer()
                Button(localization.L(L10n.PerformanceSloDiagnostic.launch)) {
                    pendingPreparation = nil
                    Task { await store.start(preparation, runtime: runtime()) }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(AppDesign.Spacing.xl).frame(minWidth: 460, maxWidth: 620)
    }

    private func installProbe() {
        defer { pendingProbe = nil }
        let presence = ModPresence.resolve(uniqueId: ModPresence.probeId, in: viewModel.mods)
        let root = URL(fileURLWithPath: viewModel.gameDir).appendingPathComponent("Mods")
        guard let source = ProbeBundle.bundledFolder(resourcesURL: Bundle.main.resourceURL),
              let target = ProbeBundle.target(modsRoot: root, presence: presence) else { return }
        do {
            try ProbeBundle.install(from: source, into: target)
            viewModel.scanMods(gameDir: viewModel.gameDir)
        } catch { return }
    }

    private func reportView(_ report: SloDiagnosticReport) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Divider()
            reportRows(report)
            loadChart(report)
            warpChart(report)
            timeline(localization.L(L10n.PerformanceSloDiagnostic.frames),
                     marks: report.frameMarks, unit: "ms")
            timeline(localization.L(L10n.PerformanceSloDiagnostic.memory),
                     marks: report.memoryMarks, unit: "MB")
            cacheChart(report)
            Text(hoverDetail ?? selectedDetail ?? " ")
                .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail).frame(minHeight: 16)
            let options = detailOptions(report)
            if !options.isEmpty {
                Picker(localization.L(L10n.PerformanceEvidence.point), selection: $selectedDetail) {
                    Text("—").tag(Optional<String>.none)
                    ForEach(options, id: \.self) { Text($0).tag(Optional($0)) }
                }.pickerStyle(.menu)
            }
            DisclosureGroup(localization.L(L10n.PerformanceSloDiagnostic.limitations)) {
                ForEach(report.limitations, id: \.self) { limitation in
                    Text(limitationText(limitation)).font(AppDesign.Font.footnote)
                }
            }
        }
    }

    private func reportRows(_ report: SloDiagnosticReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            reportRow(L10n.PerformanceSloDiagnostic.observedWait,
                      report.primaryWait.map { "\(PerformanceFormatting.number($0.durationMs)) ms · \($0.label)" })
            reportRow(L10n.PerformanceSloDiagnostic.cacheUsed,
                      report.imageCache.map { $0.used ? localization.L(L10n.PerformanceSloDiagnostic.yes) : localization.L(L10n.PerformanceSloDiagnostic.no) })
            reportRow(L10n.PerformanceSloDiagnostic.gameplay,
                      report.steadyGameplay.map { "\($0.sampleCount) · P50 \(PerformanceFormatting.number($0.medianFrameMs)) ms · P99 \(PerformanceFormatting.number($0.p99FrameMs)) ms" })
            reportRow(L10n.PerformanceSloDiagnostic.memory,
                      report.memory.map { "\(PerformanceFormatting.number($0.maximumWorkingSetMB)) MB / \(PerformanceFormatting.number($0.softLimitMB)) MB" })
        }
    }

    private func reportRow(_ key: String, _ value: String?) -> some View {
        SplitRow { Text(localization.L(key)) } trailing: {
            Text(value ?? localization.L(L10n.PerformanceSloDiagnostic.insufficient))
                .monospacedDigit().foregroundStyle(value == nil ? .secondary : .primary)
        }.font(AppDesign.Font.footnote)
    }

    @ViewBuilder private func loadChart(_ report: SloDiagnosticReport) -> some View {
        if report.loadScopeMarks.count >= 2 {
            Text(localization.L(L10n.PerformanceSloDiagnostic.loads)).font(AppDesign.Font.body(.semibold))
            Chart(Array(report.loadScopeMarks.enumerated()), id: \.offset) { _, mark in
                BarMark(x: .value("ms", mark.durationMs), y: .value("scope", mark.label))
                    .foregroundStyle(by: .value("source", mark.source.rawValue))
                    .accessibilityLabel("\(mark.label), \(PerformanceFormatting.number(mark.durationMs)) ms")
            }.chartXAxisLabel("ms").chartLegend(.hidden).frame(height: 150)
        }
    }

    @ViewBuilder private func warpChart(_ report: SloDiagnosticReport) -> some View {
        if let marks = report.warpMarks, marks.count >= 2 {
            Text(localization.L(L10n.PerformanceSloDiagnostic.warps)).font(AppDesign.Font.body(.semibold))
            Chart {
                ForEach(Array(marks.enumerated()), id: \.offset) { index, value in
                    PointMark(x: .value("transition", index + 1), y: .value("ms", value))
                        .accessibilityLabel("\(index + 1), \(PerformanceFormatting.number(value)) ms")
                }
                if let median = report.warps?.medianMs {
                    RuleMark(y: .value("median", median)).lineStyle(StrokeStyle(dash: [4, 4]))
                }
            }.chartYAxisLabel("ms").frame(height: 120)
        }
    }

    @ViewBuilder private func timeline(_ title: String, marks: [SloChartMark], unit: String) -> some View {
        if marks.count >= 2 {
            Text(title).font(AppDesign.Font.body(.semibold))
            Chart(marks, id: \.at) { mark in
                LineMark(x: .value("time", mark.at), y: .value(unit, mark.value))
                PointMark(x: .value("time", mark.at), y: .value(unit, mark.value))
                    .accessibilityLabel("\(mark.at.formatted(date: .omitted, time: .shortened)), \(PerformanceFormatting.number(mark.value)) \(unit)")
            }
            .chartYAxisLabel(unit).frame(height: 120)
            .chartOverlay { proxy in
                ChartHover(proxy: proxy) { point in
                    guard let date: Date = proxy.value(atX: point.x),
                          let nearest = marks.min(by: {
                              abs($0.at.timeIntervalSince(date)) < abs($1.at.timeIntervalSince(date))
                          }) else { hoverDetail = nil; return }
                    hoverDetail = "\(title) · \(nearest.at.formatted(date: .omitted, time: .shortened)) · \(PerformanceFormatting.number(nearest.value)) \(unit)"
                } onEnd: { hoverDetail = nil } onTap: { selectedDetail = hoverDetail }
            }
        }
    }

    @ViewBuilder private func cacheChart(_ report: SloDiagnosticReport) -> some View {
        if let cache = report.imageCache, cache.snapshot.limitMB > 0 {
            Text(localization.L(L10n.PerformanceSloDiagnostic.cacheCapacity))
                .font(AppDesign.Font.body(.semibold))
            Chart {
                BarMark(x: .value("MB", cache.snapshot.usedMB), y: .value("cache", "Image"))
                RuleMark(x: .value("limit", cache.snapshot.limitMB))
                    .foregroundStyle(AppDesign.Color.warning)
            }.chartXAxisLabel("MB").frame(height: 80)
        }
    }

    private func limitationText(_ value: SloDiagnosticLimitation) -> String {
        switch value {
        case .singleSession, .noControlRun: localization.L(L10n.PerformanceSloDiagnostic.singleRun)
        case .sloLogMissing, .probeMissing, .loadEvidenceMissing, .diagnosticsIncomplete:
            localization.L(L10n.PerformanceSloDiagnostic.insufficient)
        case .patchesNotMeasured, .shortGameplay, .transitionWindowsUnknown,
             .nestedScopes, .sessionInterrupted:
            localization.L(L10n.PerformanceSloDiagnostic.partial)
        }
    }

    private func detailOptions(_ report: SloDiagnosticReport) -> [String] {
        let frames = report.frameMarks.map {
            "\(localization.L(L10n.PerformanceSloDiagnostic.frames)) · \($0.at.formatted(date: .omitted, time: .shortened)) · \(PerformanceFormatting.number($0.value)) ms"
        }
        let memory = report.memoryMarks.map {
            "\(localization.L(L10n.PerformanceSloDiagnostic.memory)) · \($0.at.formatted(date: .omitted, time: .shortened)) · \(PerformanceFormatting.number($0.value)) MB"
        }
        return frames + memory
    }
}
