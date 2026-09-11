import Foundation

/// La fenêtre mémoire du journal : qui reste quand le plafond est atteint.
///
/// Le *quoi jeter* vit dans `LogNoise.trimIndices` (le bruit `TRACE` part
/// avant le signal, et le signal le plus ancien en tout dernier recours) ;
/// ici c'est la **composition**, extraite du ViewModel où elle portait deux
/// défauts corrigés mais jamais mis sous test.
enum LogBudget {

    /// Applique le plafond en jetant le bruit, jamais la tête du journal :
    /// SMAPI écrit tout son diagnostic de démarrage (mods ignorés, alertes du
    /// sérialiseur de sauvegarde, intégrations en échec) **au début** du
    /// fichier, et un vrai journal est à ~90 % de `TRACE`. Garder les
    /// N dernières lignes jetait donc exactement ce qui compte — la carte de
    /// santé, qui lit le fichier entier, contredisait alors la liste.
    static func trimPreservingSignal(_ entries: [LogEntry], cap: Int) -> [LogEntry] {
        guard entries.count > cap else { return entries }
        let keep = LogNoise.trimIndices(
            count: entries.count,
            cap: cap,
            isNoise: { entries[$0].level == .trace }
        )
        return keep.map { entries[$0] }
    }

    /// Remplace le bloc SMAPI de `existing` par `incoming`, sous le plafond.
    ///
    /// **Remplace, n'empile pas** : `SMAPI-latest.txt` est un instantané
    /// unique, et chaque lancement de jeu comme chaque ouverture d'onglet le
    /// relit. Sans ce remplacement, N lancements donnaient N copies.
    ///
    /// **Le budget se compte sur ce qui reste après les entrées de l'app**,
    /// jamais par écrêtage de la tête du tableau combiné : la tête porte les
    /// entrées de StarHubFR, et un écrêtage frontal les effaçait toutes dès
    /// que le journal SMAPI était gros.
    static func replacingSmapi(in existing: [LogEntry],
                               with incoming: [LogEntry], cap: Int) -> [LogEntry] {
        var out = existing.filter { $0.source != .smapi }
        let budget = max(0, cap - out.count)
        out.append(contentsOf: trimPreservingSignal(incoming, cap: budget))
        return out
    }

    /// Ajoute une entrée de l'app, en jetant les plus anciennes au-delà du
    /// plafond. Ici l'écrêtage par la tête est correct : toutes les entrées
    /// concernées sont de l'app, et l'ancienneté est le seul critère.
    static func appending(_ entry: LogEntry, to existing: [LogEntry], cap: Int) -> [LogEntry] {
        var out = existing
        out.append(entry)
        if out.count > cap { out.removeFirst(out.count - cap) }
        return out
    }
}
