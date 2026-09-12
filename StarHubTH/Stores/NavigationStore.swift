import Foundation
import Observation

/// L'état de **navigation** — présentation inter-vues (chantier « vider le
/// VM de son état publié », cadrage P8) : les vues de détail que `MainView`
/// remet à `nil` au changement d'onglet, et les requêtes posées d'une vue
/// et consommées par une autre (patron B3-T4 : une demande peut arriver
/// avant que la vue n'existe).
///
/// La règle du changement d'onglet vit dans `TabChangePlan` (Core, 11 tests,
/// six sabotages) ; le store ne porte que l'état que cette règle lit et
/// efface. Les poses inertes sont des `var` publiques — aucune décision ;
/// les deux canaux s'écrivent par verbe seulement, parce que leur cycle de
/// vie est posé-par-une-fonction, consommé-par-une-autre.
@Observable
final class NavigationStore {

    /// La sauvegarde dont la timeline est ouverte. Remis à `nil` par
    /// `MainView` au changement d'onglet (un des cinq états de détail).
    var viewingSaveTimeline: SaveGameInfo?

    /// Le mod thaï affiché par le hub de traduction (état de détail,
    /// remis à `nil` au changement d'onglet).
    var viewingThaiMod: ThaiTranslationMod?

    /// A mod the user asked to jump to (from a log line or the health card).
    ///
    /// Lives on the store rather than being handled by `ModListView`: tabs
    /// are built in an `if/else` chain, so when the request is made from the
    /// Logs tab `ModListView` doesn't exist yet and can't observe a
    /// notification. It reads and clears this on appear instead.
    var pendingModFocus: String?

    /// Le mod dont la fiche doit s'ouvrir **sur son onglet Traduction**, par
    /// dossier logique. Posé par la couverture française d'un profil (B3-T4),
    /// où le geste attendu n'est pas « regarde ce mod » mais « traduis-le ».
    /// La fiche le consomme à son apparition ; il ne survit pas au passage
    /// d'un mod à l'autre.
    var pendingTranslationFocus: String?

    /// Le mod dont l'**éditeur de configuration** doit s'ouvrir après un
    /// changement d'onglet, par dossier logique. Posé par le rapport de
    /// raccourcis (Alertes système, T8) ; consommé et effacé par le
    /// `onChange` de `MainView` après sa remise à zéro des états de détail —
    /// poser `editingModConfig` avant la bascule ne sert à rien, la remise à
    /// zéro l'efface aussitôt (même piège que `pendingTranslationFocus`).
    var pendingConfigFocus: String?

    /// Le mod dont la **fiche** doit s'ouvrir après un changement d'onglet —
    /// une requête libre (dossier OU nom affiché), résolue via
    /// `ModFocusResolver` au moment de la consommation. Posé par
    /// `SystemAlertsView` (H-T6b) pour ses lignes SMAPI/raccourcis/conflit :
    /// contrairement à `pendingModFocus` (qui ne fait que CADRER la liste,
    /// voir sa doc), celui-ci ouvre la fiche elle-même — même piège, même
    /// cure que `pendingConfigFocus` : consommé dans le `onChange` de
    /// `MainView`, après la remise à zéro des états de détail.
    var pendingModDetailFocus: String?

    /// L'onglet sur lequel la prochaine fiche de mod doit s'ouvrir, quand
    /// l'appelant ne veut pas la description par défaut. Posé avec
    /// `pendingModDetailFocus` par `SystemAlertsView` : une alerte parle de
    /// l'ÉTAT du mod (compatibilité, erreurs, raccourcis, conflits), pas de
    /// sa prose — l'ouvrir sur la description obligeait à un clic de plus
    /// pour lire ce qui motivait l'alerte.
    ///
    /// Consommé par `ModDetailView` elle-même, comme `pendingTranslationFocus`
    /// : `selectedTab` est un `@State` privé de cette vue. Remis à `nil` par
    /// `MainView` quand la résolution échoue, sinon la demande survivrait
    /// jusqu'à la prochaine fiche ouverte à la main.
    var pendingDetailTab: DetailTab?

    /// C2-T4 — le cadrage du diff de traduction demandé par le bouton
    /// « Traduire les nouveaux textes » de la section « Dernière mise à jour ».
    /// Consommé au `.task` de `TranslationDiffView` (là seul où le filtre
    /// existe avant que les groupes se rebâtissent), remis à `nil` aussitôt —
    /// la réouverture manuelle de l'onglet ne rejoue pas le cadrage.
    var pendingTranslationDiffFilter: TranslationCoverage.DiffFilter?

    /// Le texte à préremplir dans la recherche des Journaux après un
    /// changement d'onglet. Posé par `SystemAlertsView` (H-T6b) pour ses
    /// lignes sans mod résolvable (outil externe, notice bénigne sans mod).
    ///
    /// Contrairement à `pendingConfigFocus`/`pendingModDetailFocus`, la
    /// cible n'est pas un `@Published` que `MainView` lit pour choisir quelle
    /// sous-vue rendre : `searchText` est un `@State` PRIVÉ de `LogsView`,
    /// que `MainView` ne peut pas atteindre depuis son propre `onChange`.
    /// `LogsView` le consomme donc lui-même, à son apparition — même patron
    /// que `pendingModFocus` dans `ModListView`
    /// (« une requête peut arriver avant que la vue n'existe »), pas celui de
    /// `pendingConfigFocus`.
    var pendingLogFocus: String?

    /// « Voir la fiche » depuis la fenêtre de bilan. La fenêtre ne peut
    /// pas lire `currentTab` (`@State` de MainView) — la décision se prend
    /// donc LÀ où vit l'état : MainView consomme ce canal et choisit la
    /// pose directe ou le passage par le changement d'onglet (patron
    /// B3-T4 — poser les pendings avant `currentTab` ne marche jamais).
    private(set) var reportDetailFocus: String?

    /// Consommé par MainView : la fiche est demandée (pose directe ou
    /// changement d'onglet), le canal peut retomber.
    func openReportDetail(for folderName: String) {
        reportDetailFocus = folderName
    }

    func consumeReportDetailFocus() {
        reportDetailFocus = nil
    }

    // MARK: - Navigation demandée depuis la scène App (I-T1 / I-T2)

    /// L'onglet demandé depuis le menu « Aller » ou la palette ⌘K.
    ///
    /// `.commands` vit dans la scène App, `currentTab` est un `@State` de
    /// MainView : le menu ne peut pas l'écrire. Même canal que
    /// `reportDetailFocus` ci-dessus, pour la même raison (patron B3-T4).
    private(set) var pendingTabRequest: SidebarDestination?

    func requestTab(_ destination: SidebarDestination) {
        pendingTabRequest = destination
    }

    /// Consommé par MainView une fois l'onglet appliqué.
    func consumePendingTabRequest() {
        pendingTabRequest = nil
    }
}
