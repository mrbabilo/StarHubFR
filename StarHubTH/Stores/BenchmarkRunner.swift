import AppKit
import Foundation

struct BenchmarkSetup: Equatable {
    var sideB: BenchmarkSideB
    var perSide: Int
    var saveA: SaveGameInfo
    var saveB: SaveGameInfo
    /// Profil de base activé pour A (`BenchmarkSides.stateA`) ; `nil` : le parc tel quel.
    var baseProfileIds: [String]? = nil
}

enum BenchmarkFailure: Equatable {
    case neverStarted, timeout, noLine, apply, launch, copy, stopped
}

/// Benchmark automatique des chargements (spec 2026-09-30 §5). Bascule par
/// `applyEnabledFolders` — le chemin de la bissection : pas de modale, un
/// résultat —, lance le jeu, suit son processus en deux temps, restaure
/// l'état A quoi qu'il arrive. Les configs par profil ne sont pas appliquées
/// pendant la série (contrepartie écrite dans la spec).
@MainActor
@Observable
final class BenchmarkRunner {
    enum Phase: Equatable {
        case idle
        case preparing
        case running(index: Int)
        case restoring
        case finished(BenchmarkOutcome)
        case failed(BenchmarkFailure)
    }

    private(set) var phase: Phase = .idle
    private(set) var runs: [BenchmarkRun] = []
    /// La série en cours, pour la ligne « ce qui change entre A et B ».
    private(set) var setup: BenchmarkSetup?
    /// L'état observé de chaque run : démarré, jeu vu, dernier jalon de
    /// chargement lu dans `loads.jsonl`, durée à la sortie. Le panneau et le
    /// statut inline le lisent — la preuve que la série vit.
    struct RunObservation: Equatable {
        var startedAt: Date?
        var duration: TimeInterval?
        var gameSeen = false
        var milestone: String?
    }
    private(set) var observations: [RunObservation] = []
    /// Instantané d'une série interrompue (plantage, restauration partielle).
    private(set) var interrupted: BenchmarkSnapshot?
    /// Sauvegardes d'origine dont la taille ou la date a bougé pendant la série.
    private(set) var touchedSaves: [String] = []

    var isActive: Bool {
        switch phase {
        case .preparing, .running, .restoring: return true
        case .idle, .finished, .failed: return false
        }
    }

    /// Le parc courant du ViewModel — le panneau y résout le nom du mod mis
    /// en pause pour sa ligne « ce qui change entre A et B ».
    var viewModelMods: [ModItem] { viewModel.mods }

    private unowned let viewModel: StarHubTHViewModel
    private let directory: URL? = AppSupport.directory
    private let files = ProbeFiles()
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var activity: NSObjectProtocol?

    static let pollSeconds: UInt64 = 5
    static let neverStartedSeconds: TimeInterval = 90
    static let maxRunSeconds: TimeInterval = 480
    /// Au-delà, l'utilisateur a pu passer à une autre app exprès : on ne
    /// reprend plus le premier plan.
    static let focusRetrySeconds: TimeInterval = 60
    /// Restauration : attendre la fermeture d'un jeu apparu en retard.
    static let restoreWaitSeconds: TimeInterval = 60

    init(viewModel: StarHubTHViewModel) { self.viewModel = viewModel }

    /// Au démarrage de l'app : plan oublié effacé d'office (un lancement
    /// manuel ne doit jamais être détourné), instantané restant = série
    /// interrompue.
    func checkForInterruptedSession() {
        removePlan()
        interrupted = BenchmarkSnapshotStore.load(from: directory)
    }

    func restoreInterrupted() {
        guard let snapshot = interrupted, !isActive else { return }
        phase = .restoring
        Task {
            let restored = await restore(snapshot)
            if restored { interrupted = nil }
            phase = .idle
        }
    }

    /// Nil = libre ; sinon la raison, déjà traduite.
    func busyReason() -> String? {
        if SloDiagnosticSnapshotStore.hasPending(in: directory)
            || viewModel.isGameRunning() || viewModel.bisection.state != nil || viewModel.bulkToggleProgress != nil
            || viewModel.isApplyingProfile || viewModel.unresolvedApplyJournal != nil
            || files.guidedPlan() != nil || interrupted != nil {
            return viewModel.localization.L(L10n.Benchmark.refBusy)
        }
        if UserDefaults.standard.string(forKey: UDKey.launchProfile) == "Vanilla" {
            return viewModel.localization.L(L10n.Benchmark.refVanilla)
        }
        return nil
    }

    func start(_ setup: BenchmarkSetup) {
        guard !isActive, busyReason() == nil,
              BenchmarkSides.refusal(setup.sideB, mods: viewModel.mods) == nil else { return }
        stopRequested = false
        touchedSaves = []
        runs = []
        self.setup = setup
        phase = .preparing
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Benchmark des chargements")
        BenchmarkPanelController.shared.show(runner: self, localization: viewModel.localization)
        Task { await run(setup) }
    }

    /// Le lancement en cours finit ; la série s'arrête ensuite et restaure.
    func stop() { stopRequested = true }

    // MARK: — Série

    private func run(_ setup: BenchmarkSetup) async {
        let mods = viewModel.mods
        // L'instantané garde le parc **réel** : avec un profil de base, A n'est
        // pas l'état d'origine, et c'est l'origine que la fin remet.
        let original = BenchmarkSides.foldersA(mods)
        let stateA = BenchmarkSides.stateA(mods, baseProfileIds: setup.baseProfileIds)
        let foldersA = BenchmarkSides.foldersA(stateA)
        let foldersB = BenchmarkSides.foldersB(setup.sideB, foldersA: foldersA, mods: stateA)
        let sameSave = setup.saveA.folderName == setup.saveB.folderName
        let originals = [setup.saveA, setup.saveB].compactMap { SaveFileStamp.read($0.fileURL) }

        // Copies d'abord : l'instantané doit les connaître pour les jeter.
        let savesDir = setup.saveA.fileURL.deletingLastPathComponent().deletingLastPathComponent()
        guard let copyA = await clone(setup.saveA) else {
            await finish(.failed(.copy), snapshot: nil)
            return
        }
        var copyB = copyA
        if !sameSave {
            guard let made = await clone(setup.saveB) else {
                trash([savesDir.appendingPathComponent(copyA).path])
                await finish(.failed(.copy), snapshot: nil)
                return
            }
            copyB = made
        }
        let copyPaths = Array(Set([copyA, copyB])).map { savesDir.appendingPathComponent($0).path }
        let snapshot = BenchmarkSnapshot(enabledFolders: original, activeProfileId: viewModel.activeProfileId,
                                         saveCopies: copyPaths, originals: originals, startedAt: Date())
        // Sans filet de restauration, rien ne bascule.
        guard BenchmarkSnapshotStore.save(snapshot, in: directory) else {
            trash(copyPaths)
            await finish(.failed(.copy), snapshot: nil)
            return
        }
        // Relecture finale : aucun profil actif pendant la série — l'état B ne
        // doit jamais pouvoir être « adopté » dans un profil (l'instantané
        // porte l'id, la restauration le remet).
        viewModel.restoreActiveProfileAfterBenchmark(nil)

        runs = BenchmarkSequence.runs(perSide: setup.perSide, sameState: setup.sideB == .sameState)
        observations = runs.map { _ in RunObservation() }
        // Dernier état appliqué **et** relu sur le disque. Le premier lancement
        // applique toujours (sa relecture confronte le parc en mémoire au
        // disque) ; ensuite, un état inchangé ne bouge rien : le relire à
        // nouveau coûterait un scan complet du parc par lancement (« Aucun
        // changement », chauffes). Pendant la série, seul le jeu tourne.
        var applied: Set<String>?
        for (index, run) in runs.enumerated() {
            if stopRequested {
                await finish(.failed(.stopped), snapshot: snapshot)
                return
            }
            phase = .running(index: index)
            observations[index].startedAt = Date()
            observations[index].milestone = nil
            let target = Set(run.side.isA ? foldersA : foldersB)
            if target != applied {
                guard await apply(run.side.isA ? foldersA : foldersB) else {
                    await finish(.failed(.apply), snapshot: snapshot)
                    return
                }
                // La bascule voyage par UniqueID : vérifier le disque, pas faire
                // confiance au mouvement (un doublon manqué vaudrait B = A en silence).
                guard Set(viewModel.mods.filter(\.isEnabled).map(\.folderName)) == target else {
                    viewModel.log("Benchmark : l'état appliqué diffère de la cible.", level: .error)
                    await finish(.failed(.apply), snapshot: snapshot)
                    return
                }
                applied = target
            }
            let plan = BenchmarkPlanFile(runId: run.id, saveName: run.side.isA ? copyA : copyB,
                                         expiresAt: Date().addingTimeInterval(BenchmarkPlanFile.lifetime))
            do {
                try plan.write(to: files.benchmarkPlanURL)
            } catch {
                viewModel.log("Benchmark : plan non écrit (\(error.localizedDescription)).", level: .error)
                await finish(.failed(.launch), snapshot: snapshot)
                return
            }
            guard viewModel.launchGame(honoringCloseAfterLaunch: false, fromBenchmark: true) else {
                await finish(.failed(.launch), snapshot: snapshot)
                return
            }
            if let failure = await waitForGame(runId: run.id, index: index) {
                await finish(.failed(failure), snapshot: snapshot)
                return
            }
            observations[index].duration = observations[index].startedAt.map { Date().timeIntervalSince($0) }
            // Le plan a servi (lu à l'Entry de la sonde) : le retirer tout de
            // suite — un lancement manuel lancé dans la foulée ne doit pas
            // pouvoir être détourné.
            removePlan()
            guard BenchmarkVerdict.hasCompleteSave(files.loads().records, runId: run.id) else {
                await finish(.failed(.noLine), snapshot: snapshot)
                return
            }
        }
        let outcome = BenchmarkVerdict.evaluate(records: files.loads().records, runs: runs, sameSave: sameSave)
        await finish(.finished(outcome), snapshot: snapshot)
    }

    private func clone(_ save: SaveGameInfo) async -> String? {
        await Task.detached(priority: .userInitiated) { SaveManager.shared.cloneForBenchmark(info: save) }.value
    }

    /// Vrai si tous les dossiers ont trouvé leur place. `BisectionRestoreOutcome`
    /// n'est pas `Sendable` : seul le booléen traverse la continuation.
    private func apply(_ folders: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            viewModel.applyEnabledFolders(folders) { continuation.resume(returning: $0 == .complete) }
        }
    }

    /// Nil si la tâche a été annulée (traité comme un arrêt).
    private func sleep(seconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            return true
        } catch {
            return false
        }
    }

    /// Suivi en deux temps : `isGameRunning()` ne voit pas le jeu pendant ses
    /// premières secondes — « vu puis disparu » = fin ; jamais vu en 90 s =
    /// échec ; 8 min = fermeture forcée. Chaque sondage nourrit l'observation
    /// du run (jeu vu, dernier jalon lu dans `loads.jsonl`) : le panneau montre
    /// la vie pendant un lancement qui peut durer plusieurs minutes.
    private func waitForGame(runId: String, index: Int) async -> BenchmarkFailure? {
        let start = Date()
        var seen = false
        var seenAt = Date()
        var focused = false
        while true {
            guard await sleep(seconds: Self.pollSeconds) else { return .stopped }
            let running = viewModel.isGameRunning()
            if running && !seen { seenAt = Date() }
            if running { seen = true; observations[index].gameSeen = true }
            if seen {
                observations[index].milestone = latestMilestone(runId: runId)
            }
            // Une activation unique se perd au premier lancement (jeu à froid,
            // vu avant d'avoir fini de démarrer) : redemander à chaque
            // sondage jusqu'à ce qu'il soit devant.
            if running, !focused, Date().timeIntervalSince(seenAt) < Self.focusRetrySeconds {
                focused = bringGameToFront()
            }
            if seen && !running { return nil }
            let elapsed = Date().timeIntervalSince(start)
            if !seen && elapsed > Self.neverStartedSeconds { return .neverStarted }
            if elapsed > Self.maxRunSeconds {
                await terminateGame()
                return .timeout
            }
        }
    }

    /// Le dernier jalon écrit par la sonde pour ce run (`L0`…`L4` au menu
    /// titre, `S0`…`S9` au chargement). Lecture best-effort : un fichier
    /// absent ou à moitié écrit laisse le jalon précédent en place.
    private func latestMilestone(runId: String) -> String? {
        let records = files.loads().records
        guard let record = records.last(where: { $0.benchmarkRun == runId }) else { return nil }
        return record.milestones.last?.name
    }

    private func gameProcesses() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.localizedName?.caseInsensitiveCompare("Stardew Valley") == .orderedSame
        }
    }

    /// Le jeu part d'un `Process` bash : sans ce geste, StarHubFR garde le
    /// premier plan. Activation coopérative (macOS 14) : céder, puis demander.
    /// Vrai quand le jeu est déjà devant (plus rien à faire).
    private func bringGameToFront() -> Bool {
        guard let game = gameProcesses().first else { return false }
        if game.isActive { return true }
        NSApp.yieldActivation(to: game)
        game.activate()
        return false
    }

    private func terminateGame() async {
        let game = gameProcesses()
        game.forEach { $0.terminate() }
        _ = await sleep(seconds: 10)
        game.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    private func finish(_ end: Phase, snapshot: BenchmarkSnapshot?) async {
        phase = .restoring
        if let snapshot {
            let restored = await restore(snapshot)
            if !restored { interrupted = snapshot }
        }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        phase = end
        NSApp.requestUserAttention(.criticalRequest)
    }

    private func removePlan() {
        do {
            try BenchmarkPlanFile.remove(at: files.benchmarkPlanURL)
        } catch {
            viewModel.log("Benchmark : plan non effacé (\(error.localizedDescription)).", level: .warning)
        }
    }

    /// Corbeille, pas suppression : une copie jetée par erreur se récupère.
    private func trash(_ paths: [String]) {
        for path in paths where FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            } catch {
                viewModel.log("Benchmark : copie \(path) non jetée (\(error.localizedDescription)).", level: .warning)
            }
        }
    }

    /// Plan effacé, jeu attendu, état A réappliqué, profil actif remis,
    /// copies à la corbeille, originaux contrôlés. L'instantané n'est oublié
    /// qu'après une restauration complète (règle de
    /// `BisectionSnapshotStore.finish`). Rend vrai si restauré.
    private func restore(_ snapshot: BenchmarkSnapshot) async -> Bool {
        removePlan()
        // Un parc pas encore scanné, ou un instantané vide, déplacerait tout
        // ou rien en rendant « complet » : on garde l'instantané.
        guard !snapshot.enabledFolders.isEmpty, !viewModel.mods.isEmpty else { return false }
        // Un jeu apparu en retard (après « jamais lancé ») tient ses dossiers.
        let waitStart = Date()
        while viewModel.isGameRunning(), Date().timeIntervalSince(waitStart) < Self.restoreWaitSeconds {
            guard await sleep(seconds: Self.pollSeconds) else { break }
        }
        let complete = await apply(snapshot.enabledFolders)
        viewModel.restoreActiveProfileAfterBenchmark(snapshot.activeProfileId)
        trash(snapshot.saveCopies)
        viewModel.reloadSaves()
        touchedSaves = BenchmarkSaveCheck.changed(snapshot.originals)
        guard complete else { return false }
        return BenchmarkSnapshotStore.clear(in: directory)
    }
}
