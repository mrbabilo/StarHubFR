import Foundation

/// Le geste que le pilote exécute entre les deux côtés (spec P1 §7). Réversible
/// par construction — ce sont les gestes existants de l'analyse.
public enum GuidedPilotGesture: Codable, Equatable, Sendable {
    case pauseMod(folderName: String, modId: String)
    case applyProfile(baseProfileIds: [String])
    case revertConfig(modId: String, sha: String)
}

/// L'état d'avant le geste, relevé **juste avant** lui et persisté avec la
/// série : le retour arrière ne dépend pas de la mémoire de l'app (un
/// plantage pendant `applying` le laisse possible). Dossiers actifs pour une
/// pause ou un profil ; texte du `config.json` pour un revert.
public struct GuidedPilotUndo: Codable, Equatable, Sendable {
    public var enabledFolders: [String]?
    public var configPath: String?
    public var configText: String?

    public init(enabledFolders: [String]? = nil, configPath: String? = nil, configText: String? = nil) {
        self.enabledFolders = enabledFolders
        self.configPath = configPath
        self.configText = configText
    }
}

/// État du pilotage d'une paire de mesures guidées (spec P1 §7). Machine pure :
/// le runner applique les transitions, rien d'autre.
public struct GuidedPilotPlan: Codable, Equatable, Sendable {
    public enum Step: String, Codable, Sendable { case before, after }
    public enum Failure: Equatable, Codable, Sendable {
        case noMeasurement, stalled, applyFailed, revertFailed, gameQuit, stopped
    }
    public enum Phase: Equatable, Codable, Sendable {
        case idle
        case running(step: Step)
        case applying
        case reporting
        case failed(Failure)
        case interrupted
    }

    /// Minutes réelles sans progression avant abort (spec P1 §7).
    public static let watchdogSeconds: TimeInterval = 600

    public private(set) var phase: Phase = .idle
    /// Le « avant » tel que saisi ; le « après » est dérivé (role .after,
    /// pairedWith posé par le runner au moment de poser le plan).
    public var beforeDraft: GuidedPlanDraft?
    public private(set) var gesture: GuidedPilotGesture?
    /// Posé quand le geste a été tenté : la reprise sait si le parc est
    /// potentiellement côté « après » (spec P1 §7 — retour arrière proposé).
    public private(set) var gestureRan = false
    public private(set) var startedAt: Date?
    public private(set) var lastProgressAt: Date?
    /// Relevé avant le geste (`recordUndo`) ; `nil` = rien à défaire.
    public private(set) var undo: GuidedPilotUndo?
    /// Le plan « avant » : le « après » s'y apparie, reprise comprise.
    public private(set) var beforePlanId: UUID?
    /// Le plan « après » : avec `beforePlanId`, la paire que la fin de série
    /// affiche, sans deviner parmi les mesures closes.
    public private(set) var afterPlanId: UUID?
    /// Le nom du changement entre les côtés (le profil), pour les boutons de
    /// fin de série. Optionnel : un état écrit avant lui se relit.
    public private(set) var changeLabel: String?
    /// Le côté en vol au plantage de l'app — `nil` pendant `applying` : le
    /// geste a pu partir à moitié, seul le retour arrière vaut.
    public private(set) var interruptedStep: Step?

    public init() {}

    public static let initial = GuidedPilotPlan()

    public mutating func begin(draft: GuidedPlanDraft, gesture: GuidedPilotGesture?, changeLabel: String? = nil,
                               now: Date) {
        guard phase == .idle else { return }
        beforeDraft = draft
        self.gesture = gesture
        self.changeLabel = changeLabel
        startedAt = now
        lastProgressAt = now
        phase = .running(step: .before)
    }

    /// Le plan du côté en vol ; ignoré hors d'un côté (`applying` compris).
    public mutating func setSidePlan(_ id: UUID) {
        switch phase {
        case .running(step: .before): beforePlanId = id
        case .running(step: .after): afterPlanId = id
        default: break
        }
    }

    public mutating func recordUndo(_ undo: GuidedPilotUndo?) {
        guard phase == .applying else { return }
        self.undo = undo
    }

    /// Le côté à relancer : celui qui a échoué sans que le geste ne rate
    /// (jeu fermé, minutes figées, arrêt), ou celui en vol au plantage.
    public var resumableStep: Step? {
        switch phase {
        case .failed(.gameQuit), .failed(.stalled), .failed(.noMeasurement), .failed(.stopped):
            return gestureRan ? .after : .before
        case .interrupted:
            return interruptedStep
        default:
            return nil
        }
    }

    public mutating func resume(now: Date) {
        guard let step = resumableStep else { return }
        phase = .running(step: step)
        interruptedStep = nil
        lastProgressAt = now
    }

    public mutating func noteProgress(now: Date) {
        lastProgressAt = now
    }

    public func isStalled(now: Date) -> Bool {
        guard case .running = phase, let last = lastProgressAt else { return false }
        return now.timeIntervalSince(last) > Self.watchdogSeconds
    }

    /// Le côté en cours a rendu sa mesure close.
    public mutating func sideFinished(now: Date) {
        switch phase {
        case .running(step: .before):
            if gesture == nil { phase = .reporting } else { phase = .applying }
        case .running(step: .after):
            phase = .reporting
        default: break
        }
        lastProgressAt = now
    }

    public mutating func sideFailed(_ failure: Failure, now: Date) {
        guard case .running = phase else { return }
        phase = .failed(failure)
        lastProgressAt = now
    }

    public mutating func gestureApplied(now: Date) {
        guard phase == .applying else { return }
        gestureRan = true
        phase = .running(step: .after)
        lastProgressAt = now
    }

    public mutating func gestureFailed(_ failure: Failure, now: Date) {
        guard phase == .applying else { return }
        gestureRan = true
        phase = .failed(failure)
        lastProgressAt = now
    }

    /// Plantage de l'app : seul un vol en cours devient « interrompu » —
    /// `idle` n'a rien à reprendre, `reporting` a rendu son rapport.
    public mutating func interrupt() {
        switch phase {
        case .idle, .reporting, .failed, .interrupted: return
        case .running(let step): interruptedStep = step; phase = .interrupted
        case .applying: interruptedStep = nil; phase = .interrupted
        }
    }

    public mutating func finish() {
        guard phase == .reporting else { return }
        phase = .idle
        beforeDraft = nil; gesture = nil; gestureRan = false
        startedAt = nil; lastProgressAt = nil
        undo = nil; beforePlanId = nil; afterPlanId = nil; changeLabel = nil; interruptedStep = nil
    }
}
