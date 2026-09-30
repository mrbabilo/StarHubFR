import SwiftUI

/// Réglage d'un benchmark (spec §5, écran). Refus et avertissements calculés
/// par `BenchmarkSides` (Core, testé) ; la feuille ne fait qu'afficher.
struct PerformanceBenchmarkSheet: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var isPresented: Bool

    private enum Kind: Hashable { case pause, profile, same }
    @State private var kind: Kind = .same
    @State private var pauseFolder: String = ""
    @State private var profileId: UUID?
    @State private var perSide = BenchmarkSequence.defaultPerSide
    @State private var saveA: String = ""
    @State private var saveB: String = ""

    private static let parcKey = "parc"

    private var sideB: BenchmarkSideB? {
        switch kind {
        case .same: return .sameState
        case .pause: return pauseFolder.isEmpty ? nil : .pauseMod(folderName: pauseFolder)
        case .profile:
            return viewModel.modProfiles.first { $0.id == profileId }.map { .profile(enabledModIds: $0.enabledModIds) }
        }
    }

    private func save(_ folder: String) -> SaveGameInfo? { viewModel.saves.first { $0.folderName == folder } }

    private var refusal: String? {
        if let busy = viewModel.benchmark.busyReason() { return busy }
        guard let sideB, save(saveA) != nil, kind == .same || save(saveB) != nil else {
            return localization.L(L10n.Benchmark.refSaveMissing)
        }
        switch BenchmarkSides.refusal(sideB, mods: viewModel.mods) {
        case nil:
            return nil
        case .probeMissing:
            return localization.L(L10n.Benchmark.refProbeMissing)
        case .probeTooOld(let version):
            return String(format: localization.L(L10n.Benchmark.refProbeTooOld), version)
        case .probeInSideB:
            return localization.L(L10n.Benchmark.refProbeInB)
        case .dependents(let names):
            return String(format: localization.L(L10n.Benchmark.refDependents), names.joined(separator: ", "))
        case .unknownMod:
            return localization.L(L10n.Benchmark.refUnknownMod)
        }
    }

    private var cacheMods: [String] {
        guard let sideB else { return [] }
        let a = BenchmarkSides.foldersA(viewModel.mods)
        let b = BenchmarkSides.foldersB(sideB, foldersA: a, mods: viewModel.mods)
        return BenchmarkSides.cacheWarning(foldersA: a, foldersB: b, mods: viewModel.mods)
    }

    /// Les frères d'un composant de pack partent avec lui (le point vit sur
    /// l'entrée de tête).
    private var siblings: [String] {
        guard kind == .pause, let target = viewModel.mods.first(where: { $0.folderName == pauseFolder }),
              target.isGroup else { return [] }
        return target.components.map(\.name)
    }

    private var runCount: Int { BenchmarkSequence.runs(perSide: perSide, sameState: kind == .same).count }

    private var sideBKey: String? {
        switch kind {
        case .same, .pause: return Self.parcKey
        case .profile: return profileId?.uuidString
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(L10n.Benchmark.title)).font(AppDesign.Font.headline(.semibold))
            Picker(localization.L(L10n.Benchmark.sideB), selection: $kind) {
                Text(localization.L(L10n.Benchmark.sideSame)).tag(Kind.same)
                Text(localization.L(L10n.Benchmark.sidePause)).tag(Kind.pause)
                Text(localization.L(L10n.Benchmark.sideProfile)).tag(Kind.profile)
            }
            if kind == .pause {
                Picker(localization.L(L10n.Benchmark.sidePause), selection: $pauseFolder) {
                    Text("—").tag("")
                    ForEach(viewModel.mods.filter(\.isEnabled)) { Text($0.name).tag($0.folderName) }
                }
                if !siblings.isEmpty {
                    note(String(format: localization.L(L10n.Benchmark.siblings), siblings.joined(separator: ", ")))
                }
            }
            if kind == .profile {
                HStack {
                    Picker(localization.L(L10n.Benchmark.sideProfile), selection: $profileId) {
                        Text("—").tag(UUID?.none)
                        ForEach(viewModel.modProfiles) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Button(localization.L(L10n.Benchmark.createMinimal)) {
                        profileId = viewModel.createMinimalBenchmarkProfile()
                    }
                }
            }
            Stepper(String(format: localization.L(L10n.Benchmark.perSide), perSide), value: $perSide,
                    in: BenchmarkSequence.minimumPerSide...5)
            savePicker(L10n.Benchmark.saveA, selection: $saveA)
            if kind != .same { savePicker(L10n.Benchmark.saveB, selection: $saveB) }
            note(String(format: localization.L(L10n.Benchmark.duration), runCount,
                        Int((Double(runCount) * 3.5).rounded())))
            ForEach(cacheMods, id: \.self) { name in
                Label(String(format: localization.L(L10n.Benchmark.cacheWarning), name),
                      systemImage: "exclamationmark.triangle")
                    .font(AppDesign.Font.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let refusal {
                Text(refusal).font(AppDesign.Font.footnote).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(localization.L(L10n.Benchmark.cancel)) { isPresented = false }
                Button(localization.L(L10n.Benchmark.start)) { start() }
                    .disabled(refusal != nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppDesign.Spacing.lg)
        .frame(minWidth: 420)
        .onAppear { saveA = remembered(Self.parcKey) ?? viewModel.saves.first?.folderName ?? "" }
        .onChange(of: profileId) { _, _ in if let key = sideBKey { saveB = remembered(key) ?? saveB } }
    }

    private func savePicker(_ titleKey: String, selection: Binding<String>) -> some View {
        Picker(localization.L(titleKey), selection: selection) {
            Text("—").tag("")
            ForEach(viewModel.saves) { Text($0.folderName).tag($0.folderName) }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(AppDesign.Font.footnote).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func remembered(_ key: String) -> String? {
        let map = UserDefaults.standard.dictionary(forKey: UDKey.benchmarkSaveByProfile) as? [String: String]
        return map?[key].flatMap { save($0) != nil ? $0 : nil }
    }

    private func remember(_ folder: String, for key: String) {
        var map = UserDefaults.standard.dictionary(forKey: UDKey.benchmarkSaveByProfile) as? [String: String] ?? [:]
        map[key] = folder
        UserDefaults.standard.set(map, forKey: UDKey.benchmarkSaveByProfile)
    }

    private func start() {
        guard let sideB, let a = save(saveA) else { return }
        let b = kind == .same ? a : (save(saveB) ?? a)
        remember(a.folderName, for: Self.parcKey)
        if kind == .profile, let key = sideBKey { remember(b.folderName, for: key) }
        viewModel.benchmark.start(BenchmarkSetup(sideB: sideB, perSide: perSide, saveA: a, saveB: b))
        isPresented = false
    }
}
