import AppKit
import Combine
import Foundation

/// P1 T7 — le pilotage branché sur l'app : l'accesseur du runner et son
/// runtime réel. Que des délégations (F1-T2) : la logique vit dans
/// `GuidedPilotRunner` (Core, testé). Aucun état dans le ViewModel : le
/// runner vit ici, un par ViewModel (l'app n'en a qu'un).
extension StarHubTHViewModel {
    var pilot: GuidedPilotRunner { GuidedPilotLive.runner(for: self) }

    /// Série en vol, ou interrompue et pas encore tranchée : le parc peut être
    /// côté « après » — tout geste manuel sur le parc ou le jeu est refusé.
    func refuseDuringPilot() -> Bool {
        guard GuidedPilotLive.existingRunner(for: self)?.busyReasonKey != nil else { return false }
        showModal(message: localization.L(L10n.PerformancePilot.locked))
        return true
    }
}

@MainActor
enum GuidedPilotLive {
    @MainActor private static var runners: [ObjectIdentifier: GuidedPilotRunner] = [:]
    @MainActor private static var exitObservers: [ObjectIdentifier: AnyCancellable] = [:]

    /// Créé à la demande (patron `benchmark`). La sortie du jeu sonde tout de
    /// suite, onglet affiché ou non ; la boucle interne du runner (15 s)
    /// reste le filet.
    static func runner(for viewModel: StarHubTHViewModel) -> GuidedPilotRunner {
        let key = ObjectIdentifier(viewModel)
        if let existing = runners[key] { return existing }
        let created = GuidedPilotRunner(stateDirectory: AppSupport.directory, runtime: runtime(viewModel))
        runners[key] = created
        exitObservers[key] = GameExit.publisher.sink { [weak created] in
            guard let created else { return }
            Task { await created.gameExited() }
        }
        return created
    }

    /// Les refus du benchmark pour le même mécanisme (`applyEnabledFolders`
    /// travaille par UniqueID) : pause à dépendants, profil sans la sonde,
    /// identifiants partagés. Le revert d'un réglage ne bascule rien.
    static func refusal(for gesture: GuidedPilotGesture, _ viewModel: StarHubTHViewModel) -> BenchmarkRefusal? {
        switch gesture {
        case .pauseMod(let folder, _):
            return BenchmarkSides.refusal(.pauseMod(folderName: folder), mods: viewModel.mods)
        case .applyProfile(let ids):
            return BenchmarkSides.refusal(.profile(enabledModIds: ids), mods: viewModel.mods)
        case .revertConfig:
            return nil
        }
    }

    /// Sans le créer : une garde de bascule ne doit pas instancier le pilotage.
    static func existingRunner(for viewModel: StarHubTHViewModel) -> GuidedPilotRunner? {
        runners[ObjectIdentifier(viewModel)]
    }

    private static func runtime(_ viewModel: StarHubTHViewModel) -> GuidedPilotRuntime {
        let files = ProbeFiles()
        return GuidedPilotRuntime(
            isGameRunning: { [weak viewModel] in viewModel?.isGameRunning() ?? true },
            isOtherWorkBusy: { [weak viewModel] in
                guard let viewModel else { return true }
                // Un plan guidé manuel en attente serait écrasé par le plan piloté.
                let manualPlanPending = files.guidedPlan().map { $0.autoPilot != true } ?? false
                return viewModel.benchmark.isActive || viewModel.benchmark.interrupted != nil
                    || viewModel.bisection.state != nil || viewModel.bisection.isApplying
                    || viewModel.bisection.interruptedSnapshot != nil
                    || viewModel.bulkToggleProgress != nil || viewModel.isApplyingProfile || viewModel.unresolvedApplyJournal != nil
                    || SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: AppSupport.directory)
                    || manualPlanPending
            },
            refusesGesture: { [weak viewModel] gesture in
                guard let viewModel else { return true }
                return refusal(for: gesture, viewModel) != nil
            },
            activateGame: { bringGameToFront() },
            // `fromBenchmark` : lancement sans modale ni refus « série en
            // cours » — c'est la série qui lance.
            launchGame: { [weak viewModel] in viewModel?.launchGame(honoringCloseAfterLaunch: false, fromBenchmark: true) ?? false },
            applyLaunchProfile: { [weak viewModel] id in
                guard let viewModel else { return false }
                let ids = viewModel.modProfiles.first { $0.id == id }?.enabledModIds ?? []
                return await apply(BenchmarkSides.foldersA(BenchmarkSides.stateA(viewModel.mods, baseProfileIds: ids)), viewModel)
            },
            performGesture: { [weak viewModel] gesture in
                guard let viewModel, !viewModel.isGameRunning() else { return false }
                return await perform(gesture, viewModel)
            },
            captureUndo: { [weak viewModel] gesture in
                guard let viewModel else { return nil }
                return capture(gesture, viewModel)
            },
            undoGesture: { [weak viewModel] gesture, saved in
                guard let viewModel, !viewModel.isGameRunning(), let saved else { return false }
                return await undo(gesture, saved, viewModel)
            },
            writePlan: { try $0.write(to: files.guidedPlanURL) },
            removePilotPlan: { [weak viewModel] in
                guard let plan = files.guidedPlan(), plan.autoPilot == true else { return }
                do { try GuidedPlan.remove(at: files.guidedPlanURL, ifId: plan.id) } catch {
                    viewModel?.log("Mesure pilotée : plan non effacé (\(error.localizedDescription)).", level: .warning)
                }
            },
            measurementState: { id in
                let measurements = await Task.detached { files.guidedMeasurements().measurements }.value
                return GuidedPilotProbeReads.measurementState(planId: id, in: measurements)
            },
            // `timings.jsonl` seul : le compte gardé ne dépend pas des coûts
            // (`mod-costs.jsonl`, des dizaines de Mo, non relu ici).
            keptMinutes: { id in
                let plan = files.guidedPlan()
                let session = await Task.detached {
                    ProbeSessions.decode(timings: FileManager.default.contents(atPath: files.timingsURL.path),
                                         costs: nil).sessions.last
                }.value
                return GuidedPilotProbeReads.keptMinutes(plan: plan, planId: id, session: session)
            },
            quitGame: { await terminateGame() },
            requestUserAttention: { NSApp.requestUserAttention(.criticalRequest) },
            log: { [weak viewModel] in viewModel?.log($0) })
    }

    // MARK: — Gestes

    private static func perform(_ gesture: GuidedPilotGesture, _ viewModel: StarHubTHViewModel) async -> Bool {
        switch gesture {
        case .pauseMod(let folder, _):
            return await apply(BenchmarkSides.foldersA(viewModel.mods).filter { $0 != folder }, viewModel)
        case .applyProfile(let ids):
            return await apply(BenchmarkSides.foldersA(BenchmarkSides.stateA(viewModel.mods, baseProfileIds: ids)), viewModel)
        case .revertConfig(let modId, let sha):
            guard let mod = ProbePerformanceActions.target(modId: modId, in: viewModel.mods) else { return false }
            let outcome = ProbePerformanceActions.revertConfig(
                of: mod, toSha: sha, configsDirectory: ProbeFiles().configsDirectory, gameDir: viewModel.gameDir,
                gameRunning: viewModel.isGameRunning(), backups: ModConfigBackupManager.shared)
            return outcome == .reverted
        }
    }

    /// L'état d'avant, relevé juste avant le geste (persisté avec la série) :
    /// les dossiers actifs — une pause ne réactive donc qu'un mod qui l'était.
    private static func capture(_ gesture: GuidedPilotGesture, _ viewModel: StarHubTHViewModel) -> GuidedPilotUndo? {
        switch gesture {
        case .pauseMod, .applyProfile:
            return GuidedPilotUndo(enabledFolders: BenchmarkSides.foldersA(viewModel.mods))
        case .revertConfig(let modId, _):
            guard let mod = ProbePerformanceActions.target(modId: modId, in: viewModel.mods) else { return nil }
            let url = configURL(mod, viewModel)
            // Illisible ou absent : pas de retour arrière possible pour ce réglage.
            do {
                return GuidedPilotUndo(configPath: url.path, configText: try String(contentsOf: url, encoding: .utf8))
            } catch { return nil }
        }
    }

    private static func undo(_ gesture: GuidedPilotGesture, _ saved: GuidedPilotUndo,
                             _ viewModel: StarHubTHViewModel) async -> Bool {
        switch gesture {
        case .pauseMod, .applyProfile:
            guard let folders = saved.enabledFolders else { return false }
            return await apply(folders, viewModel)
        case .revertConfig:
            guard let path = saved.configPath, let text = saved.configText else { return false }
            do { try text.write(toFile: path, atomically: true, encoding: .utf8) } catch { return false }
            return true
        }
    }

    /// Le jeu part d'un `Process` bash : sans ce geste, StarHubFR garde le
    /// premier plan (patron `BenchmarkRunner.bringGameToFront`, activation
    /// coopérative de macOS 14). Vrai quand le jeu est déjà devant.
    private static func bringGameToFront() -> Bool {
        guard let game = NSWorkspace.shared.runningApplications
            .first(where: { GameProcess.isGame(localizedName: $0.localizedName) }) else { return false }
        if game.isActive { return true }
        NSApp.yieldActivation(to: game)
        game.activate()
        return false
    }

    /// Le chemin du benchmark et de la bissection : pas de modale, un résultat.
    private static func apply(_ folders: [String], _ viewModel: StarHubTHViewModel) async -> Bool {
        await withCheckedContinuation { continuation in
            viewModel.applyEnabledFolders(folders) { continuation.resume(returning: $0 == .complete) }
        }
    }

    private static func configURL(_ mod: ModItem, _ viewModel: StarHubTHViewModel) -> URL {
        URL(fileURLWithPath: viewModel.gameDir)
            .appendingPathComponent("Mods", isDirectory: true)
            .appendingPathComponent(mod.physicalFolderName, isDirectory: true)
            .appendingPathComponent("config.json")
    }

    /// Watchdog : fermeture demandée, puis forcée 10 s plus tard (patron
    /// `BenchmarkRunner.terminateGame`).
    private static func terminateGame() async {
        let game = NSWorkspace.shared.runningApplications.filter { GameProcess.isGame(localizedName: $0.localizedName) }
        game.forEach { $0.terminate() }
        do { try await Task.sleep(for: .seconds(10)) } catch { return }
        game.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }
}
