import Foundation
import Observation

/// Ce que le journal SMAPI dit de la santé de l'installation : les
/// diagnostics structurés, la date et la fraîcheur du journal, les alertes
/// système, les conflits Content Patcher — et le verrou du bouton de
/// relecture.
///
/// Ce n'est pas le journal lui-même : les lignes affichées vivent dans
/// `LogStore`, et la couture entre les deux est l'arithmétique du plafond
/// (voir `LogBudget`). Les décisions que ce store applique — quelles alertes
/// méritent une ligne de journal — sont prouvées dans `SmapiHealthFold`.
///
/// Ce qu'il ne fait pas : lire le fichier ni le parser. L'orchestration reste
/// au ViewModel, qui a besoin du parc (`mods`) pour imputer les lignes.
@Observable
final class SmapiHealthStore {

    private(set) var diagnostics: SmapiDiagnostics?
    private(set) var logDate: Date?
    private(set) var isStale = false
    private(set) var errors: [String] = []
    private(set) var contentPatcherConflicts: [LoadConflict] = []

    /// Les mods que **SMAPI lui-même** signale périmés (bloc « You can update
    /// N mods », écrit au démarrage) — distinct des mises à jour Nexus, qui
    /// viennent d'une requête réseau. Les deux s'additionnent dans la pastille
    /// d'accueil et le pied de page.
    ///
    /// Trié par nom **ici** : l'ordre de SMAPI est celui du chargement, qui
    /// change d'un lancement à l'autre. Deux tris chez deux appelants
    /// divergeraient un jour.
    private(set) var outOfDateMods: [ModUpdateInfo] = []

    /// Vrai pendant qu'une relecture tourne — pilote le spinner et
    /// l'anti-double-clic du bouton de la page des alertes système.
    private(set) var isRefreshing = false

    /// Les alertes déjà journalisées, pour n'écrire que les nouvelles.
    /// Survit à un `reset()` : voir `SmapiHealthFold.alertsToLog`.
    @ObservationIgnored private var loggedAlerts: Set<String> = []

    /// Ce qu'une lecture du journal rend. **Les cinq changent ensemble** :
    /// une date sans ses conflits, ou l'inverse, afficherait les conflits de
    /// la lecture précédente à côté de la date d'aujourd'hui.
    ///
    /// `outOfDate` a rejoint le lot le 2026-09-12 : il sortait de la même
    /// lecture mais était publié à part, et **un des deux chemins de lecture
    /// ne le recalculait pas du tout**.
    func apply(diagnostics: SmapiDiagnostics?, logDate: Date?,
               isStale: Bool, conflicts: [LoadConflict],
               outOfDate: [ModUpdateInfo]) {
        self.diagnostics = diagnostics
        self.logDate = logDate
        self.isStale = isStale
        self.contentPatcherConflicts = conflicts
        self.outOfDateMods = outOfDate.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Publie les alertes et rend **celles qui méritent une ligne de
    /// journal** — l'appelant les écrit, lui seul sachant les localiser.
    func apply(errors: [String]) -> [String] {
        self.errors = errors
        let decision = SmapiHealthFold.alertsToLog(current: errors,
                                                  alreadyLogged: loggedAlerts)
        if let updated = decision.updatedSet { loggedAlerts = updated }
        return decision.toLog
    }

    /// Journal absent : tout ce qui en venait disparaît. Sans ce reset, un
    /// journal supprimé laissait les conflits de la lecture précédente
    /// affichés à côté d'une date à `nil`.
    ///
    /// ⚠️ `loggedAlerts` n'est **pas** vidé — comportement conservé tel qu'il
    /// était au ViewModel, épinglé par un test.
    func reset() {
        diagnostics = nil
        logDate = nil
        isStale = false
        errors = []
        contentPatcherConflicts = []
        outOfDateMods = []
    }

    /// Prend le verrou de relecture, ou rend `false` s'il est déjà tenu.
    func beginRefresh() -> Bool {
        if isRefreshing { return false }
        isRefreshing = true
        return true
    }

    func endRefresh() {
        isRefreshing = false
    }
}
