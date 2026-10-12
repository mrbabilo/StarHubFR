import Foundation
import Observation

/// Ce que la sonde a rendu pour un plan guidé : rien, mesure en cours, mesure close.
public enum PilotMeasurementState: Equatable, Sendable {
    case none, running, finished
}

/// Tout ce que le runner touche hors de lui-même (spec P1 §7) : le ViewModel
/// branche le réel (T7), les tests un faux. Closures isolées au main : le VM
/// qu'elles capturent l'est, et une closure `async` non isolée s'exécuterait
/// hors du main.
public struct GuidedPilotRuntime {
    public var isGameRunning: @MainActor () -> Bool
    /// Benchmark, bissection, profil qui s'applique, plan guidé manuel en
    /// attente : deux travaux de masse sur le parc ne se croisent jamais.
    public var isOtherWorkBusy: @MainActor () -> Bool
    public var launchGame: @MainActor () -> Bool
    /// Le profil de la mesure, appliqué **avant** le « avant » (spec §7) —
    /// hors geste : un échec bloque le lancement, sans retour arrière à offrir.
    public var applyLaunchProfile: @MainActor (UUID) async -> Bool
    /// Le geste entre les deux côtés, jeu fermé ; vrai = appliqué en entier.
    public var performGesture: @MainActor (GuidedPilotGesture) async -> Bool
    /// L'inverse du geste (réactivation, réécriture du réglage d'avant).
    public var undoGesture: @MainActor (GuidedPilotGesture) async -> Bool
    public var writePlan: @MainActor (GuidedPlan) throws -> Void
    /// Efface `guided-plan.json` s'il est piloté : resté sur disque, il
    /// conduirait un lancement manuel ultérieur.
    public var removePilotPlan: @MainActor () -> Void
    public var measurementState: @MainActor (UUID) async -> PilotMeasurementState
    /// Minutes gardées du côté en cours : la progression du watchdog.
    public var keptMinutes: @MainActor (UUID) async -> Int
    public var quitGame: @MainActor () async -> Void
    public var now: @MainActor () -> Date
    public var sleep: @MainActor (TimeInterval) async -> Void
    public var requestUserAttention: @MainActor () -> Void
    public var log: @MainActor (String) -> Void

    public init(isGameRunning: @escaping @MainActor () -> Bool,
                isOtherWorkBusy: @escaping @MainActor () -> Bool,
                launchGame: @escaping @MainActor () -> Bool,
                applyLaunchProfile: @escaping @MainActor (UUID) async -> Bool,
                performGesture: @escaping @MainActor (GuidedPilotGesture) async -> Bool,
                undoGesture: @escaping @MainActor (GuidedPilotGesture) async -> Bool,
                writePlan: @escaping @MainActor (GuidedPlan) throws -> Void,
                removePilotPlan: @escaping @MainActor () -> Void,
                measurementState: @escaping @MainActor (UUID) async -> PilotMeasurementState,
                keptMinutes: @escaping @MainActor (UUID) async -> Int,
                quitGame: @escaping @MainActor () async -> Void,
                now: @escaping @MainActor () -> Date = Date.init,
                sleep: @escaping @MainActor (TimeInterval) async -> Void = { seconds in
                    // Annulée : la boucle relit `Task.isCancelled` et sort.
                    do { try await Task.sleep(for: .seconds(seconds)) } catch {}
                },
                requestUserAttention: @escaping @MainActor () -> Void,
                log: @escaping @MainActor (String) -> Void) {
        self.isGameRunning = isGameRunning
        self.isOtherWorkBusy = isOtherWorkBusy
        self.launchGame = launchGame
        self.applyLaunchProfile = applyLaunchProfile
        self.performGesture = performGesture
        self.undoGesture = undoGesture
        self.writePlan = writePlan
        self.removePilotPlan = removePilotPlan
        self.measurementState = measurementState
        self.keptMinutes = keptMinutes
        self.quitGame = quitGame
        self.now = now
        self.sleep = sleep
        self.requestUserAttention = requestUserAttention
        self.log = log
    }
}

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

    /// Le parc est possiblement côté « après » : retour arrière à proposer.
    public var canRollback: Bool {
        switch state.phase {
        case .failed, .interrupted: return state.gestureRan || interruptedWhileApplying
        default: return false
        }
    }

    @ObservationIgnored private let stateDirectory: URL?
    @ObservationIgnored private let runtime: GuidedPilotRuntime
    @ObservationIgnored private var beforePlanId: UUID?
    @ObservationIgnored private var currentPlanId: UUID?
    @ObservationIgnored private var lastKept = 0
    /// Le jeu du côté en cours a été vu ouvert : seule sa fermeture compte
    /// comme une sortie (la notification d'un jeu précédent arrive en retard).
    @ObservationIgnored private var gameSeen = false
    /// Un sondage, un lancement ou un retour arrière en cours : la boucle et
    /// la sortie du jeu se croisent au-delà d'un `await` — un seul geste.
    @ObservationIgnored private var working = false
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init(stateDirectory: URL?, runtime: GuidedPilotRuntime) {
        self.stateDirectory = stateDirectory
        self.runtime = runtime
    }

    // MARK: — Commandes

    /// Faux = refusé avant tout effet (jeu ouvert, série en cours, profil ou
    /// plan non posé, lancement refusé) : le parc et le disque n'ont pas bougé.
    @discardableResult
    public func start(draft: GuidedPlanDraft, gesture: GuidedPilotGesture?) async -> Bool {
        guard !working, canStart, !runtime.isGameRunning(), !runtime.isOtherWorkBusy() else { return false }
        working = true
        defer { working = false }
        if let profile = draft.launchProfileId {
            guard await runtime.applyLaunchProfile(profile) else {
                runtime.log("Mesure pilotée : profil de la mesure non appliqué, rien lancé.")
                return false
            }
            guard canStart, !runtime.isGameRunning() else { return false }
        }
        let plan = makePlan(draft, role: .before, pairedWith: nil)
        do { try runtime.writePlan(plan) } catch {
            runtime.log("Mesure pilotée : plan non écrit (\(error.localizedDescription)).")
            return false
        }
        guard runtime.launchGame() else {
            runtime.removePilotPlan()
            runtime.log("Mesure pilotée : lancement du jeu refusé.")
            return false
        }
        reset()
        state.begin(draft: draft, gesture: gesture, now: runtime.now())
        beforePlanId = plan.id
        currentPlanId = plan.id
        persist()
        runtime.log("Mesure pilotée « \(draft.name) » : côté avant lancé.")
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
        if runtime.isGameRunning() { gameSeen = true }
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
            guard !runtime.isGameRunning() else { return }
            await sideFinished()
        } else if gameSeen, !runtime.isGameRunning() {
            fail(.gameQuit, "le jeu s'est fermé sans rendre sa mesure")
        } else if state.isStalled(now: runtime.now()) {
            fail(.stalled, "minutes gardées figées")
            await runtime.quitGame()
        }
    }

    /// Branché sur `GameExit.publisher` (T7) : sonde tout de suite.
    public func gameExited() async { await pollOnce() }

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
            guard await runtime.undoGesture(gesture) else {
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
        guard await runtime.performGesture(gesture) else {
            state.gestureFailed(Self.failure(for: gesture), now: runtime.now())
            terminate("geste entre les deux côtés non appliqué")
            return
        }
        state.gestureApplied(now: runtime.now())
        let plan = makePlan(draft, role: .after, pairedWith: beforePlanId)
        do { try runtime.writePlan(plan) } catch {
            fail(.noMeasurement, "plan « après » non écrit (\(error.localizedDescription))")
            return
        }
        currentPlanId = plan.id
        lastKept = 0
        gameSeen = false
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
        runtime.log("Mesure pilotée : \(reason).")
    }

    private func reset() {
        loop?.cancel()
        state = .initial
        interruptedWhileApplying = false
        beforePlanId = nil
        currentPlanId = nil
        lastKept = 0
        gameSeen = false
        GuidedPilotStateStore.clear(in: stateDirectory)
    }

    private func persist() { GuidedPilotStateStore.save(state, in: stateDirectory) }

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
