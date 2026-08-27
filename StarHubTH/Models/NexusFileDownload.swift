import Foundation

/// Un téléchargement Nexus en vol : observable, annulable, et qui rend son
/// verdict **une fois exactement**.
///
/// Il remplace un `URLSession.downloadTask(with:completionHandler:)`, dont la
/// complétion unique était la garantie sur laquelle repose tout le reste :
/// `isDownloadingFromNexus` n'est remis à `false` que là, et
/// `rejectNexusDownloadIfBusy` refuse tout nouveau téléchargement tant qu'il
/// est vrai. Deux appels rejouaient l'installation ; zéro appel condamnait le
/// bouton pour la session entière.
///
/// Or le délégué, lui, sépare ce qui était une closure en **deux** rappels qui
/// se produisent tous deux sur un téléchargement normal :
/// `didFinishDownloadingTo` puis `didCompleteWithError(nil)`. La garantie ne
/// peut donc plus venir d'un raisonnement sur « lequel arrive » — elle est
/// portée ici, par un drapeau relevé sous verrou par le premier qui parle.
final class NexusFileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    /// Rendu au moment où l'archive est prête, ou dès qu'un échec est connu.
    typealias Completion = (Result<URL, NexusDownloadError>) -> Void
    /// Octets reçus, puis taille annoncée (`NSURLSessionTransferSizeUnknown`,
    /// soit `-1`, quand le serveur ne l'annonce pas — le cas est fréquent sur
    /// un CDN).
    typealias ProgressHandler = (Int64, Int64) -> Void

    /// Valide la réponse HTTP avant d'accepter le fichier : c'est là que le
    /// quota Nexus est relevé et qu'une page d'erreur déguisée en archive est
    /// écartée. Fournie par `NexusDownloader`, qui seul connaît ces règles.
    private let validate: (URLResponse?) -> NexusDownloadError?
    private let onProgress: ProgressHandler?

    private let lock = NSLock()
    private var completion: Completion?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    /// Le dernier instant rapporté à l'appelant. `URLSession` notifie à chaque
    /// paquet écrit — des centaines de fois par seconde sur une connexion
    /// rapide —, et chacune de ces notifications redessinerait la barre
    /// latérale. C'est la faute qui avait rendu la vue des journaux
    /// inutilisable à 2 000 lignes.
    private var lastReport: Date?

    /// Dix rapports par seconde : l'œil n'en distingue pas davantage sur un
    /// pourcentage, et le débit se lisse déjà sur trois secondes.
    private static let reportInterval: TimeInterval = 0.1

    init(validate: @escaping (URLResponse?) -> NexusDownloadError?,
         onProgress: ProgressHandler?,
         completion: @escaping Completion) {
        self.validate = validate
        self.onProgress = onProgress
        self.completion = completion
    }

    /// Lance le téléchargement. Sans effet si l'annulation est déjà demandée —
    /// elle peut l'être avant même que le lien ne soit résolu.
    func start(url: URL) {
        lock.lock()
        if cancelled {
            lock.unlock()
            complete(.failure(.cancelled))
            return
        }
        // Une session par téléchargement, invalidée à la fin : `URLSession`
        // **retient fortement** son délégué jusque-là, et une session gardée
        // sans être invalidée fuit son délégué à chaque téléchargement.
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        self.session = session
        self.task = task
        lock.unlock()
        task.resume()
    }

    /// Demande l'annulation. Avant le démarrage elle est mémorisée ; après,
    /// elle passe par `URLSession`, qui la rapporte en
    /// `NSURLErrorCancelled` — traduit ici en `.cancelled`, jamais en panne.
    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    // MARK: - Le verdict, une fois

    /// La **seule** porte de sortie du téléchargement, résolution du lien
    /// comprise : `NexusDownloader` y passe aussi ses échecs d'API, pour que
    /// « une fois exactement » soit vrai du flux entier et pas seulement du
    /// transfert.
    func complete(_ result: Result<URL, NexusDownloadError>) {
        lock.lock()
        guard let completion = self.completion else { lock.unlock(); return }
        self.completion = nil
        let session = self.session
        self.session = nil
        self.task = nil
        lock.unlock()

        // `finishTasksAndInvalidate` plutôt qu'`invalidateAndCancel` : la
        // tâche est terminée dans tous les chemins qui arrivent ici, et
        // l'invalidation est ce qui rompt le cycle session ↔ délégué.
        session?.finishTasksAndInvalidate()
        completion(result)
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard onProgress != nil else { return }
        let now = Date()
        lock.lock()
        // Le dernier paquet passe toujours : sans quoi la barre resterait
        // figée à 98 % jusqu'à la disparition du témoin.
        let isFinal = totalBytesExpectedToWrite > 0
            && totalBytesWritten >= totalBytesExpectedToWrite
        let due = lastReport.map { now.timeIntervalSince($0) >= Self.reportInterval } ?? true
        guard due || isFinal else { lock.unlock(); return }
        lastReport = now
        lock.unlock()
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // **Le fichier est supprimé au retour de cette méthode.** Tout ce qui
        // le concerne doit donc se faire ici, synchroniquement : le déplacer
        // dans un dossier temporaire à nous avant toute autre chose.
        if let statusError = validate(downloadTask.response) {
            complete(.failure(statusError))
            return
        }

        // Le format est lu dans les **octets** du fichier, jamais deviné
        // d'après l'URL : le lien d'un téléchargement gratuit ne porte pas
        // toujours d'extension exploitable, et nommer tout téléchargement
        // « .zip » envoyait un mod RAR ou 7z droit vers `unzip`.
        let sourceURL = downloadTask.originalRequest?.url
        let ext = ModZipInstaller.detectedArchiveExtension(at: location)
            ?? sourceURL.map { url -> String in
                let candidate = url.pathExtension.lowercased()
                return ModZipInstaller.supportedExtensions.contains(candidate) ? candidate : "zip"
            } ?? "zip"

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            complete(.success(destination))
        } catch {
            complete(.failure(.requestFailed(error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error else {
            // Sur un téléchargement réussi, ce rappel suit
            // `didFinishDownloadingTo` : `complete` a déjà parlé et ne dira
            // rien de plus. S'il est le premier, la tâche s'est terminée sans
            // produire de fichier — ce que `noValidFile` dit exactement.
            complete(.failure(.noValidFile))
            return
        }
        // Annuler son propre téléchargement n'est pas une panne : sans cette
        // traduction, le geste ouvrirait une alerte d'erreur.
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            complete(.failure(.cancelled))
            return
        }
        complete(.failure(.requestFailed(error.localizedDescription)))
    }
}
