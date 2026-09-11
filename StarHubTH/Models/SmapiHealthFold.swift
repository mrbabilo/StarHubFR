import Foundation

/// Les deux décisions que prend un rechargement du journal SMAPI : **quelles
/// alertes journaliser**, et **si ce journal doit être replié** dans
/// l'historique d'erreurs par mod.
///
/// Les deux portent de l'état qui s'accumule d'une exécution à l'autre — le
/// profil de défaut le plus cher du dépôt — et aucune des deux n'était testée
/// tant qu'elles vivaient au milieu de l'orchestration du ViewModel.
enum SmapiHealthFold {

    /// Ce qu'un mod installé apporte à une observation : son dossier (la clé
    /// de l'historique) et sa version (l'erreur est imputée à une version
    /// précise, pas au mod en général).
    struct ResolvedMod {
        let folderName: String
        let version: String

        init(folderName: String, version: String) {
            self.folderName = folderName
            self.version = version
        }
    }

    /// Les alertes à journaliser, et le jeu de référence à retenir — `nil`
    /// quand il ne doit pas changer.
    struct AlertDecision {
        let toLog: [String]
        let updatedSet: Set<String>?
    }

    /// Décide quelles alertes SMAPI méritent une ligne de journal.
    ///
    /// **Le diff se fait par contenu, pas par compte** : une alerte remplacée
    /// par une autre laisse le compte inchangé, et serait passée inaperçue.
    ///
    /// **L'ordre rendu est celui de `current`**, jamais celui du `Set` : ce
    /// dernier n'en a pas, et le journal deviendrait non déterministe d'un
    /// lancement à l'autre.
    ///
    /// ⚠️ Quand rien n'est neuf, le jeu de référence **n'est pas réécrit** —
    /// donc une alerte qui disparaît puis revient ne sera pas re-journalisée.
    /// Comportement conservé tel qu'il était au ViewModel, et épinglé par
    /// `aShrinkingListLeavesTheReferenceSetUntouched` ; le test dit ce que le
    /// code fait, pas qu'il a raison.
    static func alertsToLog(current: [String],
                            alreadyLogged: Set<String>) -> AlertDecision {
        let currentSet = Set(current)
        let fresh = currentSet.subtracting(alreadyLogged)
        guard !fresh.isEmpty else { return AlertDecision(toLog: [], updatedSet: nil) }
        return AlertDecision(toLog: current.filter { fresh.contains($0) },
                             updatedSet: currentSet)
    }

    /// Ce journal doit-il être replié dans l'historique d'erreurs ?
    ///
    /// **Un journal sans date ne l'est jamais** : sans elle, rien ne
    /// distingue une relecture du même fichier d'un nouveau journal, et
    /// chaque ouverture d'onglet gonflerait les compteurs.
    ///
    /// **Un journal déjà replié — ou antérieur — ne l'est pas non plus.** Le
    /// même fichier est relu à chaque ouverture d'onglet et à chaque
    /// rafraîchissement.
    static func shouldFold(logDate: Date?, lastFolded: Date?) -> Bool {
        guard let logDate else { return false }
        guard let lastFolded else { return true }
        return logDate > lastFolded
    }

    /// Ce qu'un journal apporte à l'historique : ses lignes `ERROR` et `WARN`
    /// imputées à un mod **que le parc connaît**.
    ///
    /// `resolve` est une closure : le parc appartient au domaine Scan, et ce
    /// type n'a pas à le connaître. Une ligne dont le mod ne se résout pas est
    /// écartée — l'imputation peut avoir été devinée dans le préfixe d'un
    /// message, et inventer un coupable serait pire que se taire.
    static func observations(from entries: [LogEntry],
                             resolve: (String) -> ResolvedMod?)
    -> [ModErrorHistory.Observation] {
        entries.compactMap { entry in
            guard entry.level == .error || entry.level == .warning,
                  let modName = entry.modName,
                  let mod = resolve(modName) else { return nil }
            return .init(mod: mod.folderName,
                         version: mod.version,
                         message: entry.message,
                         isError: entry.level == .error)
        }
    }
}
