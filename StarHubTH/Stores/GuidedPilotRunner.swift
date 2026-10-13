import Foundation
import Observation

/// P1 — la paire de mesures guidées jouée d'un clic (spec §7) : plan « avant »
/// piloté, lancement, attente de la mesure close **et** du jeu fermé, geste,
/// plan « après », lancement, rapport. La machine d'états est
/// `GuidedPilotPlan` ; ce type ne fait qu'appliquer ses transitions et les
/// persister (`GuidedPilotStateStore`) pour la reprise après plantage.
@MainActor
@Observable
public final class GuidedPilotRunner {
    public static let pollSeconds: TimeInterval = 15
    public static let busyKey = "guided-pilot-active"

    public private(set) var state: GuidedPilotPlan = .initial
    /// La dernière écriture de l'état a échoué : pas de reprise après
    /// plantage — l'écran le dit au lieu de la promettre (spec §7).
    public private(set) var persistenceFailed = false
    /// Le dernier refus de `start`/`resume` ; `nil` après un départ.
    public private(set) var lastRefusal: GuidedPilotRefusal?
    /// Le disque portait `.applying` au démarrage : le geste a pu partir à moitié.
    private var interruptedWhileApplying = false

    public var isActive: Bool {
        switch state.phase {
        case .running, .applying: return true
        case .idle, .reporting, .failed, .interrupted: return false
        }
    }

    /// Une série en vol, ou interrompue et pas encore tranchée : le parc peut
    /// être côté « après », aucun autre travail de performance ne démarre.
    public var busyReasonKey: String? {
        isActive || state.phase == .interrupted ? Self.busyKey : nil
    }

    /// Le parc est possiblement côté « après » et l'état d'avant est relevé :
    /// retour arrière à proposer — rapport compris (la paire finit sur le
    /// côté « après »). Sans relevé, aucun bouton qui échouerait à coup sûr.
    public var canRollback: Bool {
        guard state.undo != nil else { return false }
        switch state.phase {
        case .failed, .interrupted, .reporting: return state.gestureRan || interruptedWhileApplying
        default: return false
        }
    }

    /// Le côté en échec (jeu fermé, minutes figées, arrêt) ou en vol au
    /// plantage se relance ; un geste raté ou à moitié parti ne se reprend pas.
    public var canResume: Bool {
        state.resumableStep != nil && !(state.phase == .interrupted && interruptedWhileApplying)
    }

    @ObservationIgnored private let stateDirectory: URL?
    @ObservationIgnored private let runtime: GuidedPilotRuntime
    @ObservationIgnored private var currentPlanId: UUID?
    @ObservationIgnored private var lastKept = 0
    /// Le jeu du côté en cours a été vu ouvert : seule sa fermeture compte
    /// comme une sortie (la notification d'un jeu précédent arrive en retard).
    @ObservationIgnored private var gameSeen = false
    /// Lancement du côté en cours, et jeu passé devant : on ne cherche à
    /// l'activer que la première minute (ensuite, l'utilisateur a pu passer
    /// à autre chose exprès — patron `BenchmarkRunner.focusRetrySeconds`).
    @ObservationIgnored private var sideLaunchedAt: Date?
    @ObservationIgnored private var gameBroughtFront = false
    public static let focusRetrySeconds: TimeInterval = 60
    /// Le lancement du côté en cours : les étapes affichées se datent dessus.
    public var currentSideLaunchedAt: Date? { sideLaunchedAt }
    /// Une sortie de jeu plus tardive que ce délai après le lancement du côté
    /// est la sienne, même jamais vu ouvert (quitté avant le premier sondage) ;
    /// plus tôt, c'est la notification retardée (3 s) du jeu précédent.
    public static let staleExitSeconds: TimeInterval = 10
    /// Mesure close mais jeu resté ouvert (garde-fou de la sonde raté) : au-delà,
    /// le pilote le ferme lui-même.
    public static let finishedOpenSeconds: TimeInterval = 60
    @ObservationIgnored private var finishedOpenSince: Date?
    @ObservationIgnored private var quitRequested = false
    /// Un sondage, un lancement ou un retour arrière en cours : la boucle et
    /// la sortie du jeu se croisent au-delà d'un `await` — un seul geste.
    @ObservationIgnored private var working = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// Sommeil système empêché pendant la série (patron du benchmark) :
    /// l'utilisateur n'est pas devant.
    @ObservationIgnored private var activity: NSObjectProtocol?

    public init(stateDirectory: URL?, runtime: GuidedPilotRuntime) {
        self.stateDirectory = stateDirectory
        self.runtime = runtime
    }

    // MARK: — Commandes

    /// Faux = refusé avant tout effet (jeu ouvert, série en cours, profil ou
    /// plan non posé, lancement refusé) : le parc et le disque n'ont pas bougé.
    @discardableResult
    public func start(draft: GuidedPlanDraft, gesture: GuidedPilotGesture?) async -> Bool {
        guard !working, canStart else { return refuse(.seriesPending) }
        if let refusal = preflight() { return refuse(refusal) }
        if let gesture, runtime.refusesGesture(gesture) { return refuse(.gestureRefused) }
        working = true
        defer { working = false }
        if let profile = draft.launchProfileId {
            guard await runtime.applyLaunchProfile(profile) else {
                runtime.log("Mesure pilotée : profil de la mesure non appliqué, rien lancé.")
                return refuse(.profileNotApplied)
            }
            guard canStart else { return refuse(.seriesPending) }
            if runtime.isGameRunning() { return refuse(.gameRunning) }
        }
        let plan = makePlan(draft, role: .before, pairedWith: nil)
        guard launch(plan) else { return false }
        reset()
        state.begin(draft: draft, gesture: gesture, now: runtime.now())
        state.setBeforePlan(plan.id)
        sideLaunched(plan.id)
        persist()
        beginActivity()
        runtime.log("Mesure pilotée « \(draft.name) » : côté avant lancé.")
        startLoop()
        return true
    }

    /// Relance le côté en échec ou interrompu, apparié au même « avant » ;
    /// le geste n'est pas rejoué (il a réussi, ou n'a pas eu lieu).
    @discardableResult
    public func resume() async -> Bool {
        guard !working, canResume, let step = state.resumableStep, let draft = state.beforeDraft
        else { return refuse(.seriesPending) }
        if let refusal = preflight() { return refuse(refusal) }
        let pairedWith = step == .after ? state.beforePlanId : nil
        if step == .after, pairedWith == nil { return refuse(.seriesPending) }
        working = true
        defer { working = false }
        let plan = makePlan(draft, role: step == .after ? .after : .before, pairedWith: pairedWith)
        guard launch(plan) else { return false }
        lastRefusal = nil
        state.resume(now: runtime.now())
        interruptedWhileApplying = false
        if step == .before { state.setBeforePlan(plan.id) }
        sideLaunched(plan.id)
        persist()
        beginActivity()
        runtime.log("Mesure pilotée : côté \(step == .after ? "après" : "avant") relancé.")
        startLoop()
        return true
    }

    /// Un sondage : progression, mesure close, sortie du jeu, watchdog. La
    /// boucle interne l'appelle toutes les `pollSeconds` ; la sortie du jeu
    /// aussi, sans attendre.
    public func pollOnce() async {
        guard !working, case .running(let step) = state.phase, let id = currentPlanId else { return }
        working = true
        defer { working = false }
        if runtime.isGameRunning() {
            gameSeen = true
            if !gameBroughtFront, let launched = sideLaunchedAt,
               runtime.now().timeIntervalSince(launched) <= Self.focusRetrySeconds {
                gameBroughtFront = runtime.activateGame()
            }
        }
        let kept = await runtime.keptMinutes(id)
        guard isStill(step, id) else { return }
        if kept > lastKept {
            lastKept = kept
            state.noteProgress(now: runtime.now())
            persist()
        }
        let measured = await runtime.measurementState(id)
        guard isStill(step, id) else { return }
        if measured == .finished {
            // La sonde quitte d'elle-même : aucun geste disque jeu ouvert.
            guard !runtime.isGameRunning() else {
                let since = finishedOpenSince ?? runtime.now()
                finishedOpenSince = since
                if !quitRequested, runtime.now().timeIntervalSince(since) > Self.finishedOpenSeconds {
                    quitRequested = true
                    runtime.log("Mesure pilotée : mesure close, jeu toujours ouvert — fermeture.")
                    await runtime.quitGame()
                }
                return
            }
            await sideFinished()
        } else if gameSeen, !runtime.isGameRunning() {
            fail(.gameQuit, "le jeu s'est fermé sans rendre sa mesure")
        } else if state.isStalled(now: runtime.now()) {
            fail(.stalled, "minutes gardées figées")
            await runtime.quitGame()
        }
    }

    /// Branché sur `GameExit.publisher` (T7) : sonde tout de suite. Le jeu du
    /// côté a pu fermer avant le premier sondage : passé `staleExitSeconds`
    /// après son lancement, la sortie est la sienne.
    public func gameExited() async {
        if !gameSeen, let launched = sideLaunchedAt,
           runtime.now().timeIntervalSince(launched) > Self.staleExitSeconds {
            gameSeen = true
        }
        await pollOnce()
    }

    /// Arrête la série sans geste ; le jeu reste ouvert, au joueur de le fermer.
    public func stop() {
        guard case .running = state.phase else { return }
        state.sideFailed(.stopped, now: runtime.now())
        terminate("série arrêtée")
    }

    /// Au démarrage de l'app. Le disque n'est **pas** réécrit : un second
    /// redémarrage doit encore voir `.applying` et proposer le retour arrière.
    public func checkForInterruptedSession() {
        guard let saved = GuidedPilotStateStore.load(from: stateDirectory) else { return }
        interruptedWhileApplying = saved.phase == .applying
        var plan = saved
        plan.interrupt()
        state = plan
        if plan.phase == .interrupted { runtime.removePilotPlan() }
    }

    /// « Reprendre » : remet le parc côté « avant » si le geste a pu partir,
    /// puis efface la série. Un retour arrière raté garde l'état (et le disque).
    public func restoreOrRollback() async {
        guard !working, !isActive, !runtime.isGameRunning() else { return }
        working = true
        defer { working = false }
        if canRollback, let gesture = state.gesture {
            guard await runtime.undoGesture(gesture, state.undo) else {
                runtime.log("Mesure pilotée : retour arrière non appliqué.")
                return
            }
        }
        reset()
    }

    /// « Annuler » / rapport lu : retour au repos, parc laissé tel quel.
    public func dismiss() {
        guard !working, !isActive else { return }
        reset()
    }

    // MARK: — Transitions

    private func preflight() -> GuidedPilotRefusal? {
        if runtime.isGameRunning() { return .gameRunning }
        return runtime.otherWorkReason().map(GuidedPilotRefusal.otherWork)
    }

    private func refuse(_ refusal: GuidedPilotRefusal) -> Bool { lastRefusal = refusal; return false }

    /// Plan écrit, jeu lancé ; un échec se nomme, sans plan piloté laissé.
    private func launch(_ plan: GuidedPlan) -> Bool {
        do { try runtime.writePlan(plan) } catch {
            runtime.log("Mesure pilotée : plan non écrit (\(error.localizedDescription)).")
            return refuse(.planNotWritten)
        }
        guard runtime.launchGame() else {
            runtime.removePilotPlan()
            runtime.log("Mesure pilotée : lancement du jeu refusé.")
            return refuse(.launchRefused)
        }
        return true
    }

    private var canStart: Bool {
        switch state.phase {
        case .idle, .reporting: return true
        case .failed: return !canRollback
        case .running, .applying, .interrupted: return false
        }
    }

    private func isStill(_ step: GuidedPilotPlan.Step, _ id: UUID) -> Bool {
        state.phase == .running(step: step) && currentPlanId == id
    }

    private func sideFinished() async {
        state.sideFinished(now: runtime.now())
        switch state.phase {
        case .reporting:
            runtime.removePilotPlan()
            GuidedPilotStateStore.clear(in: stateDirectory)
            loop?.cancel()
            endActivity()
            runtime.requestUserAttention()
            runtime.log("Mesure pilotée : rapport prêt.")
        case .applying:
            persist()
            await applyGestureAndLaunchAfter()
        default:
            break
        }
    }

    private func applyGestureAndLaunchAfter() async {
        guard let gesture = state.gesture, let draft = state.beforeDraft else { return }
        // Relevé **avant** le geste et persisté : un plantage pendant
        // `applying` laisse le retour arrière possible (Review Focus 4).
        state.recordUndo(runtime.captureUndo(gesture))
        persist()
        guard await runtime.performGesture(gesture) else {
            state.gestureFailed(Self.failure(for: gesture), now: runtime.now())
            terminate("geste entre les deux côtés non appliqué")
            return
        }
        state.gestureApplied(now: runtime.now())
        let plan = makePlan(draft, role: .after, pairedWith: state.beforePlanId)
        do { try runtime.writePlan(plan) } catch {
            fail(.noMeasurement, "plan « après » non écrit (\(error.localizedDescription))")
            return
        }
        sideLaunched(plan.id)
        guard runtime.launchGame() else {
            fail(.noMeasurement, "lancement du côté après refusé")
            return
        }
        persist()
        runtime.log("Mesure pilotée : geste appliqué, côté après lancé.")
    }

    private static func failure(for gesture: GuidedPilotGesture) -> GuidedPilotPlan.Failure {
        if case .revertConfig = gesture { return .revertFailed }
        return .applyFailed
    }

    private func fail(_ failure: GuidedPilotPlan.Failure, _ reason: String) {
        state.sideFailed(failure, now: runtime.now())
        terminate(reason)
    }

    /// Fin en échec : plan piloté effacé, état gardé sur disque (le retour
    /// arrière reste proposé après un redémarrage), boucle arrêtée.
    private func terminate(_ reason: String) {
        runtime.removePilotPlan()
        persist()
        loop?.cancel()
        endActivity()
        runtime.log("Mesure pilotée : \(reason).")
    }

    private func reset() {
        loop?.cancel()
        endActivity()
        state = .initial
        interruptedWhileApplying = false
        currentPlanId = nil
        lastKept = 0
        gameSeen = false
        sideLaunchedAt = nil
        gameBroughtFront = false
        persistenceFailed = false
        lastRefusal = nil
        GuidedPilotStateStore.clear(in: stateDirectory)
    }

    private func sideLaunched(_ planId: UUID) {
        currentPlanId = planId
        lastKept = 0
        gameSeen = false
        gameBroughtFront = false
        sideLaunchedAt = runtime.now()
        finishedOpenSince = nil
        quitRequested = false
    }

    /// Écran gardé allumé aussi : une mise en veille de l'écran ou un
    /// verrouillage rendrait la fenêtre du jeu inactive (minutes « hors focus »).
    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled],
            reason: "Mesure pilotée")
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func persist() { persistenceFailed = !GuidedPilotStateStore.save(state, in: stateDirectory) }

    private func makePlan(_ draft: GuidedPlanDraft, role: ProbeMeasurement.Role, pairedWith: UUID?) -> GuidedPlan {
        GuidedPlan(id: UUID(), name: draft.name, role: role, location: draft.location,
                   pairedWith: pairedWith, saveName: draft.saveName, createdAt: runtime.now(),
                   autoPilot: true,
                   warp: GuidedProtocol.warpAnchor(for: draft.location).map { GuidedPlanWarp(x: $0.x, y: $0.y) })
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let sleep = self?.runtime.sleep else { return }
                await sleep(Self.pollSeconds)
                guard !Task.isCancelled, let self, self.isActive else { return }
                await self.pollOnce()
            }
        }
    }
}
