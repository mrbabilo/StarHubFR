import Foundation

/// Quand la vérification automatique des mises à jour (smapi.io) doit partir.
///
/// A2-T4 : au lancement, l'app servait l'affichage depuis le cache puis
/// réinterrogeait le parc entier à chaque boot — le genre d'habitude qui
/// finit en rate-limit. La règle retenue au cadrage du 2026-08-31 : un
/// **TTL de 12 h** sur le dernier passage réussi ; le geste manuel de la
/// page Mises à jour, lui, passe toujours outre.
///
/// Pure et testée : la frontière exacte (périmé à l'instant du TTL, pas
/// une seconde avant) est le genre de détail qu'on ne veut pas deviner.
public enum UpdateCheckPolicy {
    /// `true` quand une vérification automatique doit partir : jamais
    /// effectuée, ou dernier succès plus vieux que `ttl`.
    public static func shouldAutoCheck(lastSuccess: Date?, now: Date, ttl: TimeInterval) -> Bool {
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= ttl
    }
}
