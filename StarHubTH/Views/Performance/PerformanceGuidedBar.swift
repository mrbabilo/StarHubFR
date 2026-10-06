import SwiftUI

/// D5-A — la mesure guidée en tête de l'onglet : bouton, plan en attente,
/// étape suivante du protocole ; ou pourquoi la sonde ne peut pas guider.
struct PerformanceGuidedBar: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    @State private var draft: GuidedPlanDraft?
    @State private var message: String?

    /// `nil` tant que le scan n'a pas fini : « sonde non installée » serait
    /// faux pendant qu'il court.
    private var readiness: GuidedReadiness? {
        let scan = viewModel.scanStore
        let probe = scan.mods.flattenedMods.first {
            $0.uniqueId.caseInsensitiveCompare(GuidedProtocol.probeId) == .orderedSame
        }
        if probe == nil && (scan.scanProgress != nil || scan.mods.isEmpty) { return nil }
        return GuidedProtocol.readiness(probeVersion: probe?.version, isEnabled: probe?.isEnabled ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            // Un plan en attente reste visible et abandonnable, sonde prête
            // ou non : sinon il resterait sur disque, hors d'atteinte.
            if case .planPending(let plan) = store.protocolState { pending(plan) }
            switch readiness {
            case .missing: note(localization.L(L10n.Performance.guidedMissing))
            case .paused: note(localization.L(L10n.Performance.guidedPaused))
            case .outdated(let version):
                note(String(format: localization.L(L10n.Performance.guidedOutdated), version))
            case .ready: ready
            case nil: EmptyView()
            }
            if let message { note(message) }
        }
        .sheet(item: Binding(get: { draft.map(DraftBox.init) }, set: { draft = $0?.draft })) { box in
            PerformanceGuidedSheet(viewModel: viewModel, localization: localization, draft: box.draft,
                                   canLaunch: launchProfile != "Vanilla") { final, launch in
                prepare(final, launch: launch)
            }
        }
    }

    @ViewBuilder
    private var ready: some View {
        switch store.protocolState {
        case .planPending:
            EmptyView()   // affiché au-dessus, quel que soit l'état de la sonde
        case .beforeDone(let before):
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: localization.L(L10n.Performance.guidedBeforeDone),
                            placeName(before.location ?? GuidedProtocol.fallbackLocation),
                            before.keptAt?.count ?? 0, outcomeName(before.outcome)))
                    .font(AppDesign.Font.footnote)
                Button(localization.L(L10n.Performance.guidedAfterButton)) {
                    draft = GuidedPlanDraft(name: defaultName(), role: .after,
                                            location: GuidedProtocol.safeLocation(before.location),
                                            pairedWith: before.id)
                }
                .clickableCursor()
                .disabled(viewModel.isBenchmarkActive)
            }
        case .idle:
            AdaptiveLabels {
                Button {
                    draft = GuidedPlanDraft(name: defaultName(), role: .before,
                                            location: GuidedProtocol.fallbackLocation, pairedWith: nil)
                } label: { Label(primaryTitle, systemImage: "play.circle") }
                .help(primaryTitle).clickableCursor().disabled(viewModel.isBenchmarkActive)
            }
        }
    }

    private var primaryTitle: String {
        let count = Set(store.sides.map(\.session)).count
        let key = count == 0 ? L10n.PerformanceEvidence.startMeasurement
            : count == 1 ? L10n.PerformanceEvidence.secondMeasurement : L10n.PerformanceEvidence.compareChange
        return localization.L(key)
    }

    @ViewBuilder
    private func pending(_ plan: GuidedPlan) -> some View {
        SplitRow {
            Text(String(format: localization.L(L10n.Performance.guidedPending), plan.name,
                        placeName(plan.location)))
                .font(AppDesign.Font.footnote)
        } trailing: {
            Button(localization.L(L10n.Performance.guidedAbandon)) {
                do {
                    try store.abandonPlan()
                    message = nil
                } catch {
                    message = String(format: localization.L(L10n.Performance.guidedAbandonFailed),
                                     error.localizedDescription)
                }
            }
            .clickableCursor()
        }
        // Profil Vanilla : le jeu partirait sans SMAPI, le plan attendrait en vain.
        if launchProfile == "Vanilla" { note(localization.L(L10n.Performance.guidedVanilla)) }
    }

    private var launchProfile: String {
        UserDefaults.standard.string(forKey: UDKey.launchProfile) ?? "SMAPI"
    }

    private func prepare(_ final: GuidedPlanDraft, launch: Bool) {
        do {
            try store.prepare(final)
            message = nil
            guard launch else { return }
            // Profil choisi : l'état de mods du profil est appliqué **avant**
            // le lancement, puis laissé actif — c'est le profil sous lequel on
            // joue la mesure. « Préparer seulement » ne l'applique pas.
            if let profileId = final.launchProfileId {
                let ids = viewModel.modProfiles.first { $0.id == profileId }?.enabledModIds ?? []
                let folders = BenchmarkSides.foldersA(BenchmarkSides.stateA(viewModel.mods, baseProfileIds: ids))
                viewModel.applyEnabledFolders(folders) { _ in viewModel.launchGame() }
            } else {
                viewModel.launchGame()
            }
        } catch {
            message = String(format: localization.L(L10n.Performance.guidedWriteFailed), error.localizedDescription)
        }
    }

    private func defaultName() -> String {
        String(format: localization.L(L10n.Performance.measureDefaultName),
               Date().formatted(date: .abbreviated, time: .shortened))
    }

    private func outcomeName(_ outcome: ProbeMeasurement.Outcome?) -> String {
        localization.L(outcome == .noisy ? L10n.Performance.outcomeNoisy : L10n.Performance.outcomeStable)
    }

    private func placeName(_ location: String) -> String {
        PerformanceGuidedSheet.placeName(location, localization: localization)
    }

    private func note(_ text: String) -> some View {
        PerformanceFormatting.note(text)
    }

    private struct DraftBox: Identifiable {
        let draft: GuidedPlanDraft
        var id: String { "\(draft.role)|\(draft.location)|\(draft.pairedWith?.uuidString ?? "")" }
    }
}

/// La feuille : nom, lieu, lancer ou préparer seulement.
struct PerformanceGuidedSheet: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State var draft: GuidedPlanDraft
    let canLaunch: Bool
    let onConfirm: (GuidedPlanDraft, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saveFolder = ""
    @State private var profileId: UUID?

    init(viewModel: StarHubTHViewModel, localization: LocalizationStore, draft: GuidedPlanDraft,
         canLaunch: Bool, onConfirm: @escaping (GuidedPlanDraft, Bool) -> Void) {
        self.viewModel = viewModel
        self.localization = localization
        _draft = State(initialValue: draft)
        self.canLaunch = canLaunch
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(L10n.Performance.guidedSheetTitle)).font(AppDesign.Font.headline(.semibold))
            Text(localization.L(L10n.Performance.guidedSheetHint))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            Text(String(format: localization.L(L10n.Performance.guidedSheetDuration),
                        GuidedProtocol.minimumKeptMinutes, GuidedProtocol.maximumKeptMinutes))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            TextField(localization.L(L10n.Performance.guidedName), text: $draft.name)
            // Une mesure « après » garde le lieu de sa mesure « avant ».
            if draft.role == .before {
                Picker(localization.L(L10n.Performance.guidedLocation), selection: $draft.location) {
                    ForEach(GuidedProtocol.locations, id: \.self) { place in
                        Text(Self.placeName(place, localization: localization)).tag(place)
                    }
                }
            } else {
                Text(Self.placeName(draft.location, localization: localization)).font(AppDesign.Font.body(.medium))
            }
            Picker(localization.L(L10n.Performance.guidedSave), selection: $saveFolder) {
                Text(localization.L(L10n.Performance.guidedSaveNone)).tag("")
                ForEach(viewModel.saves) { Text($0.folderName).tag($0.folderName) }
            }
            Picker(localization.L(L10n.Performance.guidedProfile), selection: $profileId) {
                Text(localization.L(L10n.Performance.guidedProfileParc)).tag(UUID?.none)
                ForEach(viewModel.modProfiles) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            if profileId != nil {
                Text(localization.L(L10n.Performance.guidedProfileNote))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !canLaunch {
                Text(localization.L(L10n.Performance.guidedVanilla))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
            WrapHStack(spacing: AppDesign.Spacing.sm) {
                Button(localization.L(L10n.Performance.confirmCancel), role: .cancel) { dismiss() }
                Button(localization.L(L10n.Performance.guidedPrepareOnly)) { confirm(launch: false) }
                if canLaunch {
                    Button(localization.L(L10n.Performance.guidedLaunch)) { confirm(launch: true) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(AppDesign.Spacing.lg)
        .frame(minWidth: 420)
        .onAppear {
            // Comme la feuille benchmark : la liste se relit à l'ouverture,
            // le choix reprend quand elle arrive.
            viewModel.reloadSaves()
            if saveFolder.isEmpty { saveFolder = viewModel.saves.first?.folderName ?? "" }
        }
        .onChange(of: viewModel.saves) { _, saves in
            if saves.first(where: { $0.folderName == saveFolder }) == nil {
                saveFolder = saves.first?.folderName ?? ""
            }
        }
    }

    private func confirm(launch: Bool) {
        var final = draft
        final.name = final.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if final.name.isEmpty { final.name = Self.placeName(draft.location, localization: localization) }
        final.saveName = saveFolder.isEmpty ? nil : saveFolder
        final.launchProfileId = profileId
        onConfirm(final, launch)
        dismiss()
    }

    static func placeName(_ location: String, localization: LocalizationStore) -> String {
        switch location {
        case "Farm": return localization.L(L10n.Performance.locationFarm)
        case "FarmHouse": return localization.L(L10n.Performance.locationFarmhouse)
        case "Town": return localization.L(L10n.Performance.locationTown)
        case "Beach": return localization.L(L10n.Performance.locationBeach)
        case "Forest": return localization.L(L10n.Performance.locationForest)
        case "Mountain": return localization.L(L10n.Performance.locationMountain)
        default: return location
        }
    }
}
