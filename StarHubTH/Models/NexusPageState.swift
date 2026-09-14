import Foundation

/// L'état de la **page Nexus** d'un mod, tel que la reprise l'a observé —
/// le complément fiche des verdicts smapi.io (case A2-T6).
///
/// Mesuré le 2026-09-14 sur le cas réel 32260 : smapi.io rend la même
/// erreur « Found no Nexus mod with this ID. » pour une page cachée et pour
/// une page supprimée ; seul l'interrogé direct de l'API v1 les départage
/// (caché → 200, supprimé → 404). Deux états suffisent, et le silence reste
/// possible : un mod sans observation récente ne porte rien, plutôt qu'un
/// verdict inventé.
///
/// Le cycle de vie est celui d'une **projection du dernier check** : chaque
/// reprise réécrit l'ensemble observé (une page redevenue visible fait
/// disparaître son état — fusionner avec l'ancien le ferait mentir pour
/// toujours), et l'élagage retire les mods désinstallés.
public enum NexusPageState: String, Codable, Equatable, Sendable {
    /// La page répond 200 mais smapi.io ne la voit plus : l'auteur l'a
    /// masquée (mise à jour en cours, modération). Potentiellement
    /// temporaire.
    case unavailable
    /// La page répond 404 : plus de page du tout. Terminal.
    case removed

    /// Ce qui départage deux états portés par des composants d'un même
    /// pack : le plus grave gagne, même règle que `ModCompatibility.Status`.
    public var severity: Int {
        self == .removed ? 2 : 1
    }

    /// Ne garde que les états des mods **installés** : la fiche d'un mod
    /// parti n'existe plus, et un badge orphelin ne doit pas ressusciter
    /// avec lui au check suivant.
    public static func prune(_ states: [String: NexusPageState],
                             keeping installed: Set<String>) -> [String: NexusPageState] {
        states.filter { installed.contains($0.key) }
    }
}
