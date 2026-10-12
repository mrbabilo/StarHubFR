import Foundation

/// Le geste que le pilote exécute entre les deux côtés (spec P1 §7). Réversible
/// par construction — ce sont les gestes existants de l'analyse.
public enum GuidedPilotGesture: Codable, Equatable, Sendable {
    case pauseMod(folderName: String, modId: String)
    case applyProfile(baseProfileIds: [String])
    case revertConfig(modId: String, sha: String)
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

    public init() {}

    public static let initial = GuidedPilotPlan()

    public mutating func begin(draft: GuidedPlanDraft, gesture: GuidedPilotGesture?, now: Date) {
        guard phase == .idle else { return }
        beforeDraft = draft
        self.gesture = gesture
        startedAt = now
        lastProgressAt = now
        phase = .running(step: .before)
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
        case .running, .applying: phase = .interrupted
        }
    }

    public mutating func finish() {
        guard phase == .reporting else { return }
        phase = .idle
        beforeDraft = nil; gesture = nil; gestureRan = false
        startedAt = nil; lastProgressAt = nil
    }
}
