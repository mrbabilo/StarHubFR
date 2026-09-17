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

    /// `true` quand une vérification doit partir **après que l'utilisateur a
    /// choisi le dossier du jeu** (2026-09-17).
    ///
    /// Un dossier **différent**, c'est un autre parc : le cache des mises à
    /// jour décrit celui d'avant, et le TTL de 12 h n'a rien à dire dessus —
    /// on interroge. Re-choisir le **même** dossier retombe sous la règle du
    /// lancement : c'est un geste fréquent (on revient des Réglages), et il
    /// n'a aucune raison de coûter une passe complète sur 974 mods.
    ///
    /// Le réglage de l'utilisateur prime dans les deux cas : auto-check coupé,
    /// rien ne part. Choisir un dossier n'est pas consentir à du réseau.
    public static func shouldCheckAfterSelection(gameFolderChanged: Bool,
                                                 autoCheckEnabled: Bool,
                                                 lastSuccess: Date?,
                                                 now: Date,
                                                 ttl: TimeInterval) -> Bool {
        guard autoCheckEnabled else { return false }
        guard !gameFolderChanged else { return true }
        return shouldAutoCheck(lastSuccess: lastSuccess, now: now, ttl: ttl)
    }
}
