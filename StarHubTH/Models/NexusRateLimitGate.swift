import Foundation

/// Le back-off partagé après un 429 de l'API Nexus.
///
/// Avant, chaque appel réseau jugeait seul : `check()` arrêtait sa boucle sur un
/// 429, mais `fetchRawDescription`/`fetchChangelogs` traitaient le 429 comme un
/// échec ordinaire et repartaient à la requête suivante — naviguer entre les
/// fiches de mods pendant une limitation aggravait le bannissement au lieu de
/// l'attendre. Le compteur vit donc ici, à un seul endroit, consulté par tous
/// les chemins réseau.
///
/// Type pur (l'instant est injecté) pour être testable sans réseau ni horloge
/// réelle ; `NexusUpdateChecker` en garde une instance sous verrou.
public struct NexusRateLimitGate {
    /// Plafond du back-off. Un `Retry-After` aberrant — ou simplement très long,
    /// comme sur un quota journalier — couperait sinon les fonctions Nexus pour
    /// toute la session. Plafonner ne contourne rien : la requête d'après
    /// reprend un 429 et réarme la porte, soit au pire une requête par quart
    /// d'heure.
    public static let maxBackoff: TimeInterval = 15 * 60

    /// Instant avant lequel toute requête est refusée. `nil` = rien en cours.
    public private(set) var blockedUntil: Date?

    public init() {}

    /// Arme la porte après un 429. Un `retryAfter` négatif ou nul n'arme rien —
    /// il n'y a pas d'attente à respecter.
    public mutating func note(retryAfter: TimeInterval, now: Date = Date()) {
        guard retryAfter > 0 else { return }
        let until = now.addingTimeInterval(min(retryAfter, Self.maxBackoff))
        // Deux 429 concurrents : garder la plus lointaine des deux échéances,
        // sinon la réponse la plus courte raccourcit l'attente de l'autre.
        if let current = blockedUntil, current > until { return }
        blockedUntil = until
    }

    /// Temps d'attente restant, ou `nil` quand la voie est libre.
    public func remaining(now: Date = Date()) -> TimeInterval? {
        guard let until = blockedUntil, until > now else { return nil }
        return until.timeIntervalSince(now)
    }

    /// `true` tant qu'une requête doit être refusée.
    public func isBlocked(now: Date = Date()) -> Bool {
        remaining(now: now) != nil
    }
}
