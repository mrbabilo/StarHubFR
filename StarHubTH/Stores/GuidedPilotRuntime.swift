import Foundation

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
    /// Les refus du benchmark pour le même mécanisme (pause à dépendants,
    /// profil sans la sonde, identifiants partagés) : vrai = refusé.
    public var refusesGesture: @MainActor (GuidedPilotGesture) -> Bool
    /// Le jeu part d'un `Process` bash, derrière StarHubFR : sans ce geste,
    /// chaque minute est « hors focus ». Vrai = le jeu est déjà devant.
    public var activateGame: @MainActor () -> Bool
    public var launchGame: @MainActor () -> Bool
    /// Le profil de la mesure, appliqué **avant** le « avant » (spec §7) —
    /// hors geste : un échec bloque le lancement, sans retour arrière à offrir.
    public var applyLaunchProfile: @MainActor (UUID) async -> Bool
    /// Le geste entre les deux côtés, jeu fermé ; vrai = appliqué en entier.
    public var performGesture: @MainActor (GuidedPilotGesture) async -> Bool
    /// L'état d'avant le geste, relevé juste avant lui ; `nil` = rien à défaire.
    public var captureUndo: @MainActor (GuidedPilotGesture) -> GuidedPilotUndo?
    /// L'inverse du geste, depuis l'état relevé (persisté avec la série).
    public var undoGesture: @MainActor (GuidedPilotGesture, GuidedPilotUndo?) async -> Bool
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
                refusesGesture: @escaping @MainActor (GuidedPilotGesture) -> Bool,
                activateGame: @escaping @MainActor () -> Bool,
                launchGame: @escaping @MainActor () -> Bool,
                applyLaunchProfile: @escaping @MainActor (UUID) async -> Bool,
                performGesture: @escaping @MainActor (GuidedPilotGesture) async -> Bool,
                captureUndo: @escaping @MainActor (GuidedPilotGesture) -> GuidedPilotUndo?,
                undoGesture: @escaping @MainActor (GuidedPilotGesture, GuidedPilotUndo?) async -> Bool,
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
        self.refusesGesture = refusesGesture
        self.activateGame = activateGame
        self.launchGame = launchGame
        self.applyLaunchProfile = applyLaunchProfile
        self.performGesture = performGesture
        self.captureUndo = captureUndo
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
