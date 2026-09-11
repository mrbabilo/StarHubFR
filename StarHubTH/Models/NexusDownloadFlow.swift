import Foundation

/// Les décisions de la file de téléchargement Nexus — le QUOI de
/// `enqueueOrStartNexusDownload`/`drainQueuedNexusDownloads`/
/// `handleNexusDownloadResult`/`nexusDownloadMessage` (le COMMENT — le
/// transfert, les témoins publiés, l'alerte, le journal — reste au
/// ViewModel).
///
/// Extraite du ViewModel le 2026-09-11 (REFACTORING §5, domaine Nexus,
/// tranche 5). Deux duplications disparaissent au passage :
///
/// - **le prédicat « créneau occupé »**, qui vivait en trois exemplaires
///   (refus d'un nouveau clic, aiguillage, drainage) — trois copies d'une
///   même règle divergent à la première retouche ;
/// - **la table des messages d'erreur**, qui vivait en deux exemplaires : ici
///   et dans `NexusDownloadError.errorDescription`. Les deux portaient les
///   mêmes neuf clés, résolues par deux bundles différents — le bundle
///   principal pour `errorDescription`, le bundle vivant du ViewModel (qui
///   seul suit un changement de langue en session) pour l'autre. La table
///   rend désormais la **clé et ses arguments** ; chaque site la résout avec
///   son propre bundle, et il n'y a plus qu'une table.
enum NexusDownloadFlow {

    /// Le créneau est-il pris ?
    ///
    /// Occupé tant qu'un transfert court **ou** qu'une feuille
    /// d'installation attend d'être fermée : démarrer par-dessus écraserait
    /// le zip que l'utilisateur n'a pas encore installé.
    static func isBusy(isDownloading: Bool, hasPendingZip: Bool) -> Bool {
        isDownloading || hasPendingZip
    }

    enum Routing: Equatable {
        case start(NexusDownloadQueue.Entry)
        case enqueue(NexusDownloadQueue.Entry)
    }

    /// Au repos la demande part, occupé elle prend la file.
    static func route(_ entry: NexusDownloadQueue.Entry, isBusy: Bool) -> Routing {
        isBusy ? .enqueue(entry) : .start(entry)
    }

    /// Un message localisable : sa clé, et l'argument que son format attend.
    /// Rendu plutôt que résolu ici, pour que l'appelant choisisse son bundle.
    enum Message: Equatable {
        case plain(String)
        case withInt(String, Int)
        case withText(String, String)

        /// Applique le format avec le bundle de l'appelant.
        func resolved(_ localize: (String) -> String) -> String {
            switch self {
            case .plain(let key):            return localize(key)
            case .withInt(let key, let n):   return String(format: localize(key), n)
            case .withText(let key, let s):  return String(format: localize(key), s)
            }
        }
    }

    /// La table — **seule** source des neuf cas.
    static func message(for error: NexusDownloadError) -> Message {
        switch error {
        case .noApiKey:               return .plain("vm_nexus_dl_no_api_key")
        case .noValidFile:            return .plain("vm_nexus_dl_no_valid_file")
        case .noDownloadLink:         return .plain("vm_nexus_dl_no_link")
        case .authFailed:             return .plain("vm_nexus_dl_auth_failed")
        case .linkExpired:            return .plain("vm_nexus_dl_link_expired")
        case .rateLimited:            return .plain("vm_nexus_dl_rate_limited")
        // Ne devrait jamais s'afficher : les appelants traitent `.cancelled`
        // avant d'en arriver là, une alerte sur un geste volontaire étant du
        // bruit. Le cas existe pour que le switch reste exhaustif — c'est lui
        // qui fait échouer la compilation quand un cas apparaît, plutôt que
        // de laisser passer une chaîne anglaise en silence.
        case .cancelled:              return .plain("vm_nexus_dl_cancelled_error")
        case .serverError(let code):  return .withInt("vm_nexus_dl_server_error", code)
        case .requestFailed(let msg): return .withText("vm_nexus_dl_request_failed", msg)
        }
    }

    /// Ce qu'un résultat de téléchargement demande à l'appelant.
    enum Completion: Equatable {
        /// Le zip est posé : la feuille d'installation peut s'ouvrir. `facts`
        /// est X9 — ce que le téléchargement savait du fichier posé — et vaut
        /// `nil` quand la page ne datait pas son fichier : l'app s'abstient
        /// d'ancrer plutôt que d'inventer.
        case installable(zip: URL, modId: Int, facts: NexusInstallFacts?)
        /// Annuler n'est pas une panne : l'appelant garde la trace de ce qui
        /// n'a pas été installé, aucune alerte ne s'ouvre.
        ///
        /// Le libellé reste à l'appelant, et ce n'est pas un oubli : il sait
        /// nommer le mod (`nexusDownloadLogMessage` le résout depuis `mods`),
        /// ce que Core ne peut pas faire. Rendre une phrase d'ici obligerait
        /// à la variante sans nom — une régression visible au journal.
        case cancelled
        /// Une vraie panne : alerte **et** journal, même message.
        case failed(message: Message)
    }

    static func completion(for result: Result<NexusDownloadOutcome, NexusDownloadError>,
                           modId: Int) -> Completion {
        switch result {
        case .success(let outcome):
            return .installable(
                zip: outcome.zip, modId: modId,
                facts: outcome.resolvedFile.flatMap {
                    NexusInstallFacts(resolvedFile: $0, modId: String(modId))
                })
        case .failure(.cancelled):
            return .cancelled
        case .failure(let error):
            return .failed(message: message(for: error))
        }
    }
}
