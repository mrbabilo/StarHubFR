import Foundation
import Observation

/// Le téléchargement Nexus **en vol** : ce que l'écran en montre, la tâche
/// annulable, la file des demandes surnuméraires et le lissage du débit
/// (cadrage §4, domaine 7, tranche 3).
///
/// Ce qu'il épine :
///
/// 1. **L'ouverture et la fermeture sont symétriques.** La remise au repos
///    était déjà regroupée (`clearNexusDownloadState`, et son commentaire
///    disait pourquoi : les quatre témoins étaient remis à zéro à trois
///    endroits, et oublier l'un d'eux condamnait le bouton pour la session).
///    L'**ouverture**, elle, restait posée à la main sur les deux seuls
///    sites qui démarrent un transfert — un mod, et une traduction.
/// 2. **`progress` reste `nil` pendant que le lien se résout.** Les deux
///    appels d'API qui précèdent le transfert n'ont rien à mesurer : c'est
///    `isDownloading` qui porte l'attente, pas une barre à zéro.
/// 3. **Annuler ne remet rien au repos.** `URLSession` rapporte
///    l'annulation par le chemin d'échec habituel, et c'est lui qui conclut.
///    Le faire des deux côtés rouvrirait la porte à un état remis au repos
///    pendant qu'un transfert continue.
/// 4. **Le débit se remet à zéro avec le reste**, sans quoi le
///    téléchargement suivant hériterait des octets du précédent — rien ne
///    casserait, le chiffre serait seulement faux.
///
/// ⚠️ Ce qu'il ne juge **pas** : « suis-je occupé ? ». `NexusDownloadFlow`
/// tranche sur le couple (`isDownloading`, `pendingDownloadedZip`), et la
/// seconde moitié appartient à l'installation. La décision reste chez
/// l'appelant, qui voit les deux — comme l'entrée du snooze en tranche 1.
@Observable
final class NexusDownloadStore {

    /// Vrai dès la demande, donc avant que le lien ne soit résolu.
    private(set) var isDownloading = false

    /// L'identifiant Nexus de ce qui se télécharge, `nil` au repos. Pilote
    /// le témoin de la ligne dans la liste des mises à jour —
    /// `isDownloading` ne dit que « il y en a un ».
    private(set) var downloadingModId: Int?

    /// Où en est le transfert. `nil` au repos **et** pendant la résolution
    /// du lien (règle 2).
    private(set) var progress: DownloadProgress?

    /// Le transfert en vol, seul point d'annulation. Interne : ce n'est pas
    /// un signal de rendu.
    @ObservationIgnored private(set) var inFlight: NexusFileDownload?

    /// Les demandes mises en file au lieu d'être refusées pendant qu'un
    /// autre tourne ou que la feuille d'installation est ouverte.
    @ObservationIgnored private var queue = NexusDownloadQueue()

    /// Le débit, lissé sur trois secondes. Vit ici et non dans la vue : le
    /// téléchargement continue quand l'onglet change.
    @ObservationIgnored private var rate = DownloadRateEstimator()

    // MARK: - Le cycle d'un téléchargement

    /// Ouvre un téléchargement. `progress` reste `nil` : rien n'est encore
    /// mesurable, et une barre à zéro mentirait sur ce qui se passe.
    func beginDownload(modId: Int) {
        isDownloading = true
        downloadingModId = modId
        progress = nil
    }

    /// Retient la tâche annulable. Geste séparé de `beginDownload` par
    /// nécessité : elle n'existe qu'au retour du téléchargeur, qu'on appelle
    /// entre les deux.
    func track(_ download: NexusFileDownload?) {
        inFlight = download
    }

    /// Publie l'avancement et nourrit le lissage du débit.
    ///
    /// `now` est injectable **parce que le débit ne se teste pas sans ça** :
    /// deux relevés posés dans la même milliseconde ne rendent aucun débit,
    /// et le test qui prétendait vérifier que le débit ne survit pas au
    /// transfert précédent passait aussi sans la remise à zéro.
    func noteProgress(received: Int64, expected: Int64, modId: Int,
                      now: Date = Date()) {
        rate.record(totalBytes: received, at: now)
        progress = DownloadProgress(bytesReceived: received,
                                    totalBytes: expected,
                                    bytesPerSecond: rate.bytesPerSecond,
                                    nexusModId: modId)
    }

    /// Remet tout au repos — les trois témoins, la tâche, **et le lissage du
    /// débit** : sans quoi le transfert suivant héritera des octets de
    /// celui-ci.
    func endDownload() {
        isDownloading = false
        downloadingModId = nil
        progress = nil
        inFlight = nil
        rate.reset()
    }

    /// Annule le transfert en cours. Sans effet s'il n'y en a pas, et **ne
    /// remet rien au repos** : `URLSession` rapportera l'annulation par le
    /// chemin d'échec, qui appellera `endDownload()`. Conclure ici aussi
    /// laisserait l'état au repos pendant qu'un transfert continue.
    func cancel() {
        inFlight?.cancel()
    }

    // MARK: - La file

    /// Met une demande en attente. Rend `false` si elle y est déjà.
    @discardableResult
    func enqueue(_ entry: NexusDownloadQueue.Entry) -> Bool {
        queue.enqueue(entry)
    }

    /// La demande suivante, s'il y en a une.
    func dequeue() -> NexusDownloadQueue.Entry? {
        queue.dequeue()
    }

    var hasQueuedDownloads: Bool { !queue.isEmpty }
}
