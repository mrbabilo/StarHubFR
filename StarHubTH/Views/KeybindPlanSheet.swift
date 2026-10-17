import SwiftUI
import AppKit

/// Plan de raccourcis (spec 2026-10-15 §4-§6) — la proposition, son
/// application aux vrais `config.json`, et son annulation. Toute la logique
/// vit dans `KeybindPlanService` et le solveur (testés en Core) ; cette
/// feuille ne fait que choisir, montrer et dire.
///
/// Choix tenus ici, et pourquoi :
/// - **Rapport courant à l'application.** `apply` reçoit le rapport de
///   `KeybindScanService` au moment du clic, jamais celui du calcul : sinon
///   la garde de péremption du service comparerait un rapport à lui-même.
///   Pendant un scan, le rapport publié est encore l'ancien — « Appliquer »
///   est alors grisé.
/// - **Exclusions passées telles quelles** (`excluding:`), sans recalcul :
///   recalculer pour les retirer redistribuerait les touches des autres
///   lignes sous les yeux de l'utilisateur.
/// - **Motif dit avant le clic** : jeu ouvert, scan en cours, tout décoché —
///   la légende à gauche du pied le nomme. Le jeu est relu à l'ouverture,
///   après chaque action et au retour dans l'app (on quitte le jeu ailleurs :
///   sans cette relecture, le bouton resterait grisé). Pas de minuteur.
/// - **`canUndo` lit le disque** (liste des sauvegardes) : relu aux mêmes
///   moments et gardé en `@State`, jamais lu dans `body`. Il pilote
///   « Annuler le plan », pas l'état `.applied` : le service survit à la
///   feuille, une feuille rouverte recalcule un plan et l'annulation reste
///   possible.
/// - **Vue clavier non reprise** : `KeybindKeyboardGroup` prend bien des
///   réglages quelconques, mais un état « après plan » fidèle exigerait de
///   recalculer les conflits (logique de scanner dupliquée), et ses touches
///   ouvrent l'éditeur d'un autre onglet sous la feuille. Liste seule.
struct KeybindPlanSheet: View {
    let viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// `ObservableObject`, pas `@Observable` : sans `@ObservedObject`, le
    /// rapport rescanné après l'application ne redessinerait pas la feuille.
    @ObservedObject private var scanService: KeybindScanService
    private let service: KeybindPlanService
    private let familyStore: KeybindFamilyStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: KeybindPlanMode = .conflictsOnly
    /// `PlannedMove.id` décochés par l'utilisateur.
    @State private var excluded: Set<String> = []
    @State private var gameRunning = false
    @State private var canUndo = false
    /// Les déplacements cochés au clic d'« Appliquer » : le plan disparaît à
    /// l'état `.applied`, et le service compte en **mods** (un mod réécrit en
    /// entier ou sauté en entier) — le verdict compte en raccourcis.
    @State private var submittedMoves: [PlannedMove] = []
    /// `nil` = ouverture par défaut : déplié quand aucun déplacement n'est
    /// possible (c'est alors toute la réponse), replié sinon.
    @State private var unmovableExpanded: Bool?
    /// Posé au clic, avant la tâche : un second clic mis en file ne relance
    /// rien (le service a sa propre garde, celle-ci grise les boutons).
    @State private var busy = false

    init(viewModel: StarHubTHViewModel, localization: LocalizationStore) {
        self.viewModel = viewModel
        self.localization = localization
        self.scanService = viewModel.keybindScanService
        self.service = viewModel.keybindPlanService
        self.familyStore = viewModel.keybindFamilyStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .padding(AppDesign.Spacing.lg)
        .frame(minWidth: 520, idealWidth: 640, minHeight: 420, idealHeight: 560)
        .onAppear {
            refreshEnvironment()
            if service.state != .applying { recompute() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshEnvironment()
        }
        // Un scan qui se termine sous un plan prêt (ou pas encore calculé)
        // le rendrait périmé : recalcul. Un verdict affiché reste affiché.
        .onChange(of: scanService.isScanning) { _, scanning in
            guard !scanning else { return }
            switch service.state {
            case .idle, .ready: recompute()
            case .computing, .applying, .applied, .undone, .failed: break
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.KeybindPlan.title))
                .font(AppDesign.Font.headline(.semibold))
            Picker(localization.L(L10n.KeybindPlan.title), selection: $mode) {
                Text(localization.L(L10n.KeybindPlan.modeConflicts)).tag(KeybindPlanMode.conflictsOnly)
                Text(localization.L(L10n.KeybindPlan.modeFull)).tag(KeybindPlanMode.fullLayout)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(service.state == .applying)
            .onChange(of: mode) { _, _ in recompute() }
        }
    }

    @ViewBuilder private var content: some View {
        if scanService.report == nil {
            message(localization.L(scanService.isScanning ? L10n.Keybinds.scanning : L10n.KeybindPlan.noReport))
        } else {
            switch service.state {
            case .idle, .computing, .applying:
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let plan):
                planList(plan)
            case .applied(let result):
                verdict(appliedSummary(result), skipped: result.skipped)
            case .undone(let result):
                verdict(counted(L10n.KeybindPlan.undone, result.restored, skipped: result.skipped.count),
                        skipped: result.skipped)
            case .failed(let failure):
                statusRow(icon: "exclamationmark.triangle.fill", color: AppDesign.Color.warning,
                          text: KeybindPlanText.failure(failure, localization.L))
            }
        }
    }

    private func planList(_ plan: KeybindPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                if plan.moves.isEmpty {
                    if plan.unmovable.isEmpty {
                        statusRow(icon: "checkmark.circle.fill", color: AppDesign.Color.success,
                                  text: localization.L(mode == .fullLayout ? L10n.KeybindPlan.emptyFull
                                                                           : L10n.KeybindPlan.empty))
                    } else {
                        statusRow(icon: AppDesign.Status.info.symbol, color: .secondary,
                                  text: localization.L(L10n.KeybindPlan.noneMovable))
                    }
                } else {
                    Text(String(format: localization.L(L10n.KeybindPlan.moves), plan.moves.count))
                        .font(AppDesign.Font.footnote(.semibold)).foregroundColor(.secondary)
                    ForEach(plan.moves) { move in
                        KeybindPlanRow(move: move, isIncluded: inclusion(move.id),
                                       hasCorrection: familyStore.families[move.modID] != nil,
                                       localize: localization.L) { setFamily($0, for: move.modID) }
                    }
                }
                if !plan.unmovable.isEmpty {
                    unmovableGroup(plan)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, AppDesign.Spacing.sm)
        }
    }

    private func unmovableGroup(_ plan: KeybindPlan) -> some View {
        DisclosureGroup(isExpanded: Binding(get: { unmovableExpanded ?? plan.moves.isEmpty },
                                            set: { unmovableExpanded = $0 })) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                ForEach(plan.unmovable, id: \.rowID) { setting in
                    KeybindPlanUnmovableRow(setting: setting,
                                            hasCorrection: familyStore.families[setting.modID] != nil,
                                            localize: localization.L) { setFamily($0, for: setting.modID) }
                }
            }
            .padding(.top, AppDesign.Spacing.xs)
        } label: {
            Text(String(format: localization.L(L10n.KeybindPlan.unmovable), plan.unmovable.count))
                .font(AppDesign.Font.body(.semibold))
        }
        .padding(.top, AppDesign.Spacing.xs)
    }

    /// Le verdict d'une application ou d'une annulation, chaque mod sauté
    /// nommé avec sa raison, puis ce que la nouvelle analyse a trouvé.
    private func verdict(_ summary: String, skipped: [KeybindPlanService.Skip]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                statusRow(icon: skipped.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                          color: skipped.isEmpty ? AppDesign.Color.success : AppDesign.Color.warning,
                          text: summary)
                ForEach(Array(skipped.enumerated()), id: \.offset) { _, skip in
                    Text("· " + KeybindPlanText.skip(skip, name: modName(skip.folderName), localization.L))
                        .font(AppDesign.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                KeybindPlanRemaining(report: scanService.report, isScanning: scanService.isScanning,
                                     localization: localization)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Pied

    private var footer: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            // « Jeu ouvert » ne vaut que tant qu'il l'est : `gameRunning` est
            // relu au retour dans l'app, le refus s'efface avec lui.
            if let refusal = service.refusal, refusal != .gameRunning || gameRunning {
                Text(KeybindPlanText.failure(refusal, localization.L))
                    .font(AppDesign.Font.footnote).foregroundColor(AppDesign.Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SplitRow(spacing: AppDesign.Spacing.sm) {
                if let motive = disabledMotive {
                    Text(motive)
                        .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                        .lineLimit(2)
                }
            } trailing: {
                footerButtons
            }
        }
    }

    @ViewBuilder private var footerButtons: some View {
        if canUndo {
            Button(localization.L(L10n.KeybindPlan.undo), action: undo)
                .buttonStyle(.bordered).focusRing()
                .disabled(gameRunning || busy)
                .help(localization.L(L10n.KeybindPlan.undoHint))
        }
        if showsRecompute {
            Button(localization.L(L10n.KeybindPlan.recompute), action: recompute)
                .buttonStyle(.bordered).focusRing()
                .disabled(scanService.report == nil || scanService.isScanning)
        }
        Button(localization.L(L10n.KeybindPlan.close)) { dismiss() }
            .keyboardShortcut(.cancelAction)
        if readyMoves?.isEmpty == false {
            Button(localization.L(L10n.KeybindPlan.apply), action: apply)
                .buttonStyle(.borderedProminent).focusRing()
                .disabled(!canApply)
                .help(localization.L(L10n.KeybindPlan.applyHint))
        }
    }

    /// Recalculer n'a de sens qu'une fois le plan consommé ou refusé : un
    /// plan prêt se recalcule déjà au changement de mode ou de famille.
    private var showsRecompute: Bool {
        switch service.state {
        case .applied, .undone, .failed: true
        case .idle, .computing, .ready, .applying: false
        }
    }

    /// Les déplacements du plan prêt ; `nil` hors de l'état `.ready`.
    private var readyMoves: [PlannedMove]? {
        guard case .ready(let plan) = service.state else { return nil }
        return plan.moves
    }

    private var includedCount: Int {
        (readyMoves ?? []).filter { !excluded.contains($0.id) }.count
    }

    private var canApply: Bool {
        !busy && !gameRunning && scanService.report != nil && !scanService.isScanning && includedCount > 0
    }

    /// Pourquoi un bouton du pied est grisé, dit avant le clic.
    private var disabledMotive: String? {
        let applicable = readyMoves?.isEmpty == false
        if gameRunning, canUndo || applicable {
            return localization.L(L10n.KeybindPlan.applyGameOpen)
        }
        guard applicable else { return nil }
        if scanService.isScanning { return localization.L(L10n.Keybinds.scanning) }
        if includedCount == 0 { return localization.L(L10n.KeybindPlan.allExcluded) }
        return nil
    }

    // MARK: - Actions

    private func inclusion(_ id: String) -> Binding<Bool> {
        Binding(get: { !excluded.contains(id) },
                set: { included in
                    if included { excluded.remove(id) } else { excluded.insert(id) }
                })
    }

    /// Lit ce qui ne se lit pas dans `body` : le jeu (processus) et
    /// l'annulation possible (liste des sauvegardes sur disque).
    /// Raccourcis écrits = déplacements soumis dont le mod n'est pas sauté.
    private func appliedSummary(_ result: KeybindPlanService.AppliedResult) -> String {
        let skippedMods = Set(result.skipped.map(\.folderName))
        let written = submittedMoves.filter { !skippedMods.contains($0.modID) }.count
        return counted(L10n.KeybindPlan.applied, written, skipped: submittedMoves.count - written)
    }

    /// « 1 raccourci écrit, 2 sautés » : chaque compte accordé (`_one`), la
    /// partie « sautés » tue quand il n'y en a aucun.
    private func counted(_ key: String, _ count: Int, skipped: Int) -> String {
        let head = localization.plural(key, count)
        return skipped == 0 ? head : head + ", " + localization.plural(L10n.KeybindPlan.skippedCount, skipped)
    }

    /// Le nom du mod d'un saut, connu par les déplacements soumis ; le
    /// dossier sinon (annulation après réouverture de la feuille).
    private func modName(_ folderName: String) -> String {
        submittedMoves.first { $0.modID == folderName }?.modName ?? folderName
    }

    private func refreshEnvironment() {
        gameRunning = viewModel.isGameRunning()
        canUndo = service.canUndo
    }

    private func recompute() {
        guard let report = scanService.report else { return }
        service.compute(report: report, familyStore: familyStore, mode: mode)
        if case .ready(let plan) = service.state {
            excluded.formIntersection(plan.moves.map(\.id))
        }
        refreshEnvironment()
    }

    private func setFamily(_ family: KeybindFamily?, for modID: String) {
        familyStore.set(family, for: modID)
        recompute()
    }

    private func apply() {
        // Le rapport **du clic** : c'est lui que le service compare à celui
        // du calcul.
        guard !busy, let report = scanService.report, !scanService.isScanning else { return }
        busy = true
        let excluding = excluded
        submittedMoves = (readyMoves ?? []).filter { !excluding.contains($0.id) }
        Task {
            await service.apply(report: report, gameDir: viewModel.gameDir, mods: viewModel.mods,
                                excluding: excluding, rescan: rescan)
            busy = false
            refreshEnvironment()
        }
    }

    private func undo() {
        guard !busy else { return }
        busy = true
        Task {
            await service.undo(gameDir: viewModel.gameDir, mods: viewModel.mods, rescan: rescan)
            busy = false
            refreshEnvironment()
        }
    }

    private var rescan: @MainActor () -> Void {
        { [viewModel] in viewModel.keybindScanService.scan(mods: viewModel.mods, gameDir: viewModel.gameDir) }
    }

    // MARK: - Briques

    private func message(_ text: String) -> some View {
        Text(text)
            .font(AppDesign.Font.body).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.sm) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).font(AppDesign.Font.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
