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
    /// d'heure. Ce plafond ne s'applique **pas** à un quota épuisé dont la
    /// remise à zéro est mesurée : cette échéance-là est certaine, la deviner
    /// n'a plus de sens.
    public static let maxBackoff: TimeInterval = 15 * 60

    /// Instant avant lequel toute requête est refusée. `nil` = rien en cours.
    public private(set) var blockedUntil: Date?

    public init() {}

    /// Arme la porte après un 429. Un `retryAfter` négatif ou nul n'arme rien —
    /// il n'y a pas d'attente à respecter.
    ///
    /// Si le quota mesuré sur la même réponse annonce une fenêtre **épuisée**
    /// avec son instant de remise à zéro, la porte s'aligne dessus : jusqu'à
    /// cette échéance, toute requête ne peut que repartir en 429, et le plafond
    /// de 15 minutes ne ferait que réessayer pour rien. Une fenêtre épuisée
    /// **sans** échéance mesurée ne dit rien de plus qu'avant : le plafond
    /// garde alors son rôle.
    public mutating func note(retryAfter: TimeInterval, quota: NexusQuota? = nil,
                              now: Date = Date()) {
        var until: Date?
        if retryAfter > 0 {
            until = now.addingTimeInterval(min(retryAfter, Self.maxBackoff))
        }
        for window in [quota?.hourly, quota?.daily].compactMap({ $0 }) {
            guard window.remaining == 0, let reset = window.reset, reset > now else { continue }
            if let current = until, current >= reset { continue }
            until = reset
        }
        guard let target = until else { return }
        // Deux 429 concurrents : garder la plus lointaine des deux échéances,
        // sinon la réponse la plus courte raccourcit l'attente de l'autre.
        if let current = blockedUntil, current > target { return }
        blockedUntil = target
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
