import Foundation
import Observation

/// L'avancement d'une passe de vérification.
///
/// Un `struct` plutôt que le tuple `(done:total:)` d'origine : un tuple n'est
/// pas `Equatable`, donc inutilisable dans un `onChange(of:)` — la vue n'en
/// animait que `done`, faute de mieux.
public struct UpdateCheckProgress: Equatable, Sendable {
    public let done: Int
    public let total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

/// Ce que l'app sait des mises à jour de mods : les lignes à montrer, et
/// l'état des deux passes qui les produisent (cadrage §4, domaine 7,
/// tranche 1).
///
/// **Le store ne voit jamais le cache plat.** Les lignes qu'il porte sont des
/// *projections* : `NexusUpdateChecker.shared` garde le cache, la
/// consolidation par pack et la fusion d'une passe partielle (429, 503) —
/// pièges mesurés, consignés dans `CLAUDE.md`. L'appelant consolide, juge le
/// snooze, puis remet les deux moitiés d'un coup. Y réécrire la liste
/// consolidée aplatirait ce que le cache doit garder à plat.
///
/// Ce qu'il épine, et qui vivait en gardes posées à la main :
///
/// 1. **Les deux moitiés changent ensemble.** « Actives » et « en veille »
///    sortent d'une même partition ; publiées séparément, un instant de
///    rendu voit un mod dans les deux, ou dans aucune.
/// 2. **Le verrou a deux détenteurs.** La reprise Nexus démarre *dans* la
///    passe smapi.io, donc avant que celle-ci n'ait fini : le relâchement de
///    la première ne doit pas éteindre le voyant que la seconde vient
///    d'allumer. Sans ça, le bouton « Vérifier » réapparaît pendant que
///    Nexus est encore interrogé page par page — et un second passage
///    complet peut démarrer par-dessus, aux dépens du quota Nexus là où
///    smapi.io est gratuit.
@Observable
final class ModUpdateStore {

    // MARK: - Ce que la fenêtre montre

    /// Les mises à jour dues, consolidées par pack — le badge de la barre
    /// latérale ne compte que celles-ci.
    private(set) var updates: [NexusUpdateChecker.ModUpdate] = []

    /// Vraies, mais repoussées par un snooze encore vivant. Affichées
    /// repliées, jamais comptées par le badge.
    private(set) var snoozed: [NexusUpdateChecker.ModUpdate] = []

    /// Les mises à jour qu'un « Je l'ai déjà » a fait taire (X12).
    private(set) var affirmed: [AffirmedUpdates.Row] = []

    /// Les mods que smapi.io n'a pas pu vérifier, avec le motif classé. Les
    /// taire laissait la fenêtre dire « tous à jour » alors qu'ils n'avaient
    /// de verdict d'aucune source.
    private(set) var unverifiable: [SmapiVerdicts.Unverifiable] = []

    // MARK: - L'état des passes

    /// Vrai tant qu'une vérification tourne — l'une **ou** l'autre passe.
    private(set) var isChecking = false

    /// Le message de la dernière passe en échec, effacé au lancement de la
    /// suivante.
    private(set) var checkError: String?

    private(set) var progress: UpdateCheckProgress?

    /// Vrai entre le lancement d'une reprise Nexus et sa fin. Interne : ce
    /// n'est pas un signal de rendu, c'est ce qui retient `endCheck()`.
    @ObservationIgnored private(set) var fallbackInFlight = false

    // MARK: - Les lignes

    /// Les deux moitiés de la partition, **d'un seul geste**.
    func setPartition(active: [NexusUpdateChecker.ModUpdate],
                      sleeping: [NexusUpdateChecker.ModUpdate]) {
        updates = active
        snoozed = sleeping
    }

    func setAffirmed(_ rows: [AffirmedUpdates.Row]) {
        affirmed = rows
    }

    func setUnverifiable(_ rows: [SmapiVerdicts.Unverifiable]) {
        unverifiable = rows
    }

    /// Nexus a fini par trancher pour ces identifiants : ils quittent les
    /// invérifiables. **Un retrait ciblé**, pas un remplacement — les mods
    /// que la reprise n'a pas atteints restent dus.
    func settle(_ settled: Set<String>) {
        guard !settled.isEmpty else { return }
        unverifiable = unverifiable.filter { !settled.contains($0.uniqueId) }
    }

    // MARK: - Les passes

    /// Ouvre une passe : voyant allumé, erreur précédente effacée.
    func beginCheck(progress: UpdateCheckProgress? = nil) {
        isChecking = true
        checkError = nil
        self.progress = progress
    }

    func setProgress(_ progress: UpdateCheckProgress?) {
        self.progress = progress
    }

    func setCheckError(_ message: String?) {
        checkError = message
    }

    /// Referme la passe smapi.io — **sauf si une reprise Nexus est partie**,
    /// auquel cas c'est `endFallback()` qui relâchera les deux.
    ///
    /// La décision vit ici, pas chez l'appelant : elle y était un `guard`
    /// qu'il fallait penser à écrire, et le chemin qui l'oubliait éteignait
    /// le voyant d'une passe encore en vol.
    func endCheck() {
        guard !fallbackInFlight else { return }
        isChecking = false
        progress = nil
    }

    /// Ouvre la reprise Nexus. Elle démarre **pendant** la passe smapi.io :
    /// le voyant est déjà allumé, elle en prend la relève.
    func beginFallback(pages: Int) {
        isChecking = true
        fallbackInFlight = true
        progress = UpdateCheckProgress(done: 0, total: pages)
    }

    /// Referme tout. Appelée sur les deux sorties de la reprise — dernière
    /// page atteinte **et** abandon sur limitation de débit : un drapeau
    /// resté levé laisserait la vérification bloquée « en cours » pour la
    /// session.
    func endFallback() {
        fallbackInFlight = false
        isChecking = false
        progress = nil
    }
}
