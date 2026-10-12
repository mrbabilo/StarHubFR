import Testing
import Foundation
@testable import StarHubTHCore

/// P1 T6 — l'orchestration de la paire pilotée, runtime entièrement factice :
/// horloge pilotée, aucune I/O réelle, `pollOnce` appelé par le test (la
/// boucle interne dort — le `sleep` factice suspend, il n'avance pas
/// l'horloge, sinon la boucle tournerait en rond jusqu'au faux « stalled »).
@Suite @MainActor struct GuidedPilotRunnerTests {
    private final class Fake {
        var launched = 0
        var gestures: [GuidedPilotGesture] = []
        var undone: [GuidedPilotGesture] = []
        var gestureSucceeds = true
        var undoSucceeds = true
        var profileApplied: [UUID] = []
        var profileSucceeds = true
        var states: [UUID: PilotMeasurementState] = [:]
        var kept: [UUID: Int] = [:]
        var attention = 0
        var quits = 0
        var planRemovals = 0
        var now = Date(timeIntervalSince1970: 0)
        var writtenPlans: [GuidedPlan] = []
        var gameRunning = false
        /// Suspend dans les lectures : deux sondages s'y croisent vraiment.
        var suspendReads = false
    }

    private func runtime(_ fake: Fake) -> GuidedPilotRuntime {
        .init(isGameRunning: { fake.gameRunning },
              launchGame: { fake.launched += 1; return true },
              applyLaunchProfile: { fake.profileApplied.append($0); return fake.profileSucceeds },
              performGesture: { fake.gestures.append($0); return fake.gestureSucceeds },
              undoGesture: { fake.undone.append($0); return fake.undoSucceeds },
              writePlan: { fake.writtenPlans.append($0) },
              removePilotPlan: { fake.planRemovals += 1 },
              measurementState: { id in
                  if fake.suspendReads { await Task.yield(); await Task.yield() }
                  return fake.states[id] ?? .none
              },
              keptMinutes: { fake.kept[$0] ?? 0 },
              quitGame: { fake.quits += 1 },
              now: { fake.now },
              sleep: { _ in try? await Task.sleep(for: .seconds(3600)) },
              requestUserAttention: { fake.attention += 1 },
              log: { _ in })
    }

    private func draft(profile: UUID? = nil) -> GuidedPlanDraft {
        .init(name: "P", role: .before, location: "Farm", pairedWith: nil,
              saveName: "Ferme_1", launchProfileId: profile)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pilot-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func fullPairRunsBothSidesAndCallsAttention() async {
        let fake = Fake()
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        #expect(await runner.start(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i")))
        fake.states[fake.writtenPlans[0].id] = .finished
        await runner.pollOnce()
        #expect(fake.gestures.count == 1)
        fake.states[fake.writtenPlans[1].id] = .finished
        await runner.pollOnce()
        #expect(runner.state.phase == .reporting)
        #expect(fake.attention == 1)
        #expect(fake.launched == 2)
    }

    /// La sonde 0.9.25 refuse `Version != 1` : un plan v2 « de forme » mais
    /// écrit en version 2 retomberait en protocole humain — sans erreur.
    @Test func writtenPlansCarryPilotFieldsAndPairing() async {
        let fake = Fake()
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i"))
        fake.states[fake.writtenPlans[0].id] = .finished
        await runner.pollOnce()
        let before = fake.writtenPlans[0], after = fake.writtenPlans[1]
        let anchor = GuidedProtocol.warpAnchor(for: "Farm")
        for plan in [before, after] {
            #expect(plan.version == 1)
            #expect(plan.autoPilot == true)
            #expect(plan.warp == anchor.map { GuidedPlanWarp(x: $0.x, y: $0.y) })
            #expect(plan.location == "Farm" && plan.saveName == "Ferme_1")
        }
        #expect(before.role == .before && before.pairedWith == nil)
        #expect(after.role == .after && after.pairedWith == before.id)
    }

    /// La sonde écrit la mesure close puis quitte — le processus vit encore
    /// jusqu'à 10 s : aucun geste disque tant que le jeu est ouvert.
    @Test func noGestureWhileGameStillRunning() async {
        let fake = Fake()
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i"))
        fake.gameRunning = true
        fake.states[fake.writtenPlans[0].id] = .finished
        await runner.pollOnce()
        #expect(fake.gestures.isEmpty)
        #expect(runner.state.phase == .running(step: .before))
        fake.gameRunning = false
        await runner.gameExited()
        #expect(fake.gestures.count == 1)
        #expect(runner.state.phase == .running(step: .after))
    }

    @Test func gameQuitWithoutMeasurementFailsAndNeverGestures() async {
        let fake = Fake()
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i"))
        fake.gameRunning = true
        await runner.pollOnce()     // jeu vu
        fake.gameRunning = false
        await runner.gameExited()   // jeu fermé, aucune mesure close
        #expect(runner.state.phase == .failed(.gameQuit))
        #expect(fake.gestures.isEmpty)
        #expect(fake.planRemovals == 1)   // un lancement manuel ne sera pas piloté
    }

    /// Une sortie de jeu jamais vu pendant ce côté (la notification du jeu
    /// « avant » arrivée après le lancement du « après ») n'est pas une sortie
    /// du côté en cours : seul le watchdog tranche alors.
    @Test func exitOfAnUnseenGameIsIgnored() async {
        let fake = Fake()
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i"))
        await runner.gameExited()
        #expect(runner.state.phase == .running(step: .before))
    }

    @Test func stalledWatchdogAbortsBeforeGesturing() async {
        let fake = Fake()
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i"))
        fake.now += 601   // aucune progression
        await runner.pollOnce()
        #expect(runner.state.phase == .failed(.stalled))
        #expect(fake.gestures.isEmpty)
        #expect(fake.quits == 1)
    }

    @Test func progressResetsTheWatchdog() async {
        let fake = Fake()
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i"))
        fake.now += 500
        fake.kept[fake.writtenPlans[0].id] = 1
        await runner.pollOnce()
        fake.now += 500   // 1 000 s depuis le lancement, 500 depuis la minute
        await runner.pollOnce()
        #expect(runner.state.phase == .running(step: .before))
    }

    @Test func failedGestureStopsThePair() async {
        let fake = Fake()
        fake.gestureSucceeds = false
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i"))
        fake.states[fake.writtenPlans[0].id] = .finished
        await runner.pollOnce()
        #expect(runner.state.phase == .failed(.applyFailed))
        #expect(fake.launched == 1)
        #expect(runner.canRollback)
    }

    @Test func failedConfigRevertIsNamed() async {
        let fake = Fake()
        fake.gestureSucceeds = false
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: .revertConfig(modId: "m", sha: "abc"))
        fake.states[fake.writtenPlans[0].id] = .finished
        await runner.pollOnce()
        #expect(runner.state.phase == .failed(.revertFailed))
    }

    /// Spec §7 : le profil de la mesure s'applique **avant** le « avant », hors
    /// geste — un échec bloque le lancement (précédent X132) sans proposer de
    /// faux retour arrière.
    @Test func launchProfileAppliesBeforeFirstLaunchAndBlocksOnFailure() async {
        let fake = Fake()
        let profile = UUID()
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        #expect(await runner.start(draft: draft(profile: profile), gesture: nil))
        #expect(fake.profileApplied == [profile])
        #expect(fake.launched == 1)

        let failing = Fake()
        failing.profileSucceeds = false
        let refused = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(failing))
        #expect(await refused.start(draft: draft(profile: profile), gesture: nil) == false)
        #expect(failing.launched == 0 && failing.writtenPlans.isEmpty)
        #expect(refused.state.phase == .idle)
        #expect(refused.canRollback == false)
    }

    @Test func refusesToStartWhileGameRuns() async {
        let fake = Fake()
        fake.gameRunning = true
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        #expect(await runner.start(draft: draft(), gesture: nil) == false)
        #expect(fake.launched == 0)
    }

    @Test func singleSideWithoutGestureReportsAfterOneRun() async {
        let fake = Fake()
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: nil)
        fake.states[fake.writtenPlans[0].id] = .finished
        await runner.pollOnce()
        #expect(runner.state.phase == .reporting)
        #expect(fake.launched == 1)
    }

    /// Deux sondages concurrents (boucle + sortie du jeu) : un seul geste.
    @Test func concurrentPollsGestureOnce() async {
        let fake = Fake()
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i"))
        fake.states[fake.writtenPlans[0].id] = .finished
        fake.suspendReads = true
        async let first: Void = runner.pollOnce()
        async let second: Void = runner.gameExited()
        _ = await (first, second)
        #expect(fake.gestures.count == 1)
        #expect(fake.launched == 2)
        // La mesure close du « avant » ne clôt pas le « après » au passage.
        #expect(runner.state.phase == .running(step: .after))
    }

    @Test func stopFailsWithoutGesture() async {
        let fake = Fake()
        let runner = GuidedPilotRunner(stateDirectory: nil, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i"))
        runner.stop()
        #expect(runner.state.phase == .failed(.stopped))
        fake.states[fake.writtenPlans[0].id] = .finished
        await runner.pollOnce()
        #expect(fake.gestures.isEmpty)
    }

    @Test func interruptedSessionResumesFromDisk() async {
        let fake = Fake()
        let dir = temporaryDirectory()
        var plan = GuidedPilotPlan.initial
        plan.begin(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i"),
                   now: Date(timeIntervalSince1970: 0))
        plan.sideFinished(now: Date(timeIntervalSince1970: 60))
        GuidedPilotStateStore.save(plan, in: dir)
        let runner = GuidedPilotRunner(stateDirectory: dir, runtime: runtime(fake))
        runner.checkForInterruptedSession()
        #expect(runner.state.phase == .interrupted)
        #expect(runner.isActive == false)
        #expect(runner.canRollback)
        // Le disque garde `.applying` : un second redémarrage le voit encore.
        let again = GuidedPilotRunner(stateDirectory: dir, runtime: runtime(fake))
        again.checkForInterruptedSession()
        #expect(again.canRollback)
    }

    @Test func rollbackUndoesTheGestureAndClears() async {
        let fake = Fake()
        let dir = temporaryDirectory()
        let runner = GuidedPilotRunner(stateDirectory: dir, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i"))
        fake.states[fake.writtenPlans[0].id] = .finished
        fake.gestureSucceeds = false
        await runner.pollOnce()
        await runner.restoreOrRollback()
        #expect(fake.undone == [.pauseMod(folderName: "S", modId: "i")])
        #expect(runner.state.phase == .idle)
        #expect(GuidedPilotStateStore.hasPending(in: dir) == false)
    }

    @Test func failedRollbackKeepsTheState() async {
        let fake = Fake()
        fake.undoSucceeds = false
        let dir = temporaryDirectory()
        let runner = GuidedPilotRunner(stateDirectory: dir, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: .pauseMod(folderName: "S", modId: "i"))
        fake.states[fake.writtenPlans[0].id] = .finished
        fake.gestureSucceeds = false
        await runner.pollOnce()
        await runner.restoreOrRollback()
        #expect(runner.state.phase == .failed(.applyFailed))
        #expect(GuidedPilotStateStore.hasPending(in: dir))
    }

    @Test func dismissReturnsToIdleAndClearsDisk() async {
        let fake = Fake()
        let dir = temporaryDirectory()
        let runner = GuidedPilotRunner(stateDirectory: dir, runtime: runtime(fake))
        await runner.start(draft: draft(), gesture: nil)
        fake.states[fake.writtenPlans[0].id] = .finished
        await runner.pollOnce()
        runner.dismiss()
        #expect(runner.state.phase == .idle)
        #expect(GuidedPilotStateStore.hasPending(in: dir) == false)
    }
}
