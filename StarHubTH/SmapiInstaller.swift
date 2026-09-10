import Foundation

class SmapiInstaller: ObservableObject {
    /// Chemin vers l'onglet Journaux pour ce que la complétion ne peut pas dire.
    ///
    /// L'installation peut réussir **et** laisser un défaut derrière elle : le
    /// marqueur de version non écrit fait croire à l'app, au lancement suivant,
    /// que SMAPI est absent. Rendre `false` mentirait, et un `print` n'apparaît
    /// nulle part dans l'app — d'où ce canal séparé, branché par le ViewModel.
    var onWarning: ((String) -> Void)?

    @Published var isInstalling = false
    @Published var statusMessage = ""   // holds an L10n key, translated by caller via vm.L()
    @Published var progress: Double = 0.0

        /// L'environnement **minimal** qu'on pose sur chaque `Process` lancé ici :
    /// `LC_ALL=en_US_POSIX` + `LANG=en_US_POSIX`. AGENTS §4.7 l'exige pour
    /// éviter qu'une locale système (français, thaï) ne s'infiltre dans un
    /// message d'erreur d'un sous-processus qu'on aurait à parser
    /// (`unzip`, `xattr`, installateur .NET de SMAPI). Le pattern partagé
    /// avec les `DateFormatter.locale` du dépôt : sans cette pose, la locale
    /// du parent est héritée, et un message comme « l'opération n'est pas
    /// permise » deviendrait intraitable côté `lastMeaningfulLine`.
    private static func posixLocaleEnvironment() -> [String: String] {
        ["LC_ALL": "en_US_POSIX", "LANG": "en_US_POSIX"]
    }

    /// La session éphémère pour le download GitHub de SMAPI (X83).
    ///
    /// `URLSession.shared` n'a pas de timeout explicite : sa valeur par
    /// défaut (~60 s par requête) suffit pour un hôte rapide, mais un
    /// CDN GitHub ralenti par un proxy peut laisser le download en
    /// attente bien plus longtemps — mesuré à 5 min sur le parc de
    /// référence quand un VPN d'entreprise s'interpose. On borne donc
    /// chaque étape : 30 s par ressource, 60 s globales, sans cache
    /// disque (l'archive de SMAPI ne se re-télécharge jamais deux fois
    /// dans la même session). `.ephemeral` empêche aussi les cookies de
    /// session d'un compte GitHub antérieur de fuiter vers l'API.
    private static func downloadSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }

    /// Un verdict HTTP typé pour le download SMAPI (X88).
    ///
    /// 4xx = panne **définitive** (URL changée, asset retiré, repo
    /// supprimé) : on ne retente pas, on dit à l'utilisateur ce qu'on a
    /// vu. 5xx = panne **transitoire** (rate-limit GitHub, blip réseau,
    /// pic de charge) : un retry pourrait passer, mais l'install
    /// s'arrête ici pour ne pas masquer une vraie erreur. La distinction
    /// sert surtout à l'appelant qui voudra un jour proposer un
    /// « réessayer » sur 5xx — pour l'instant, le filet reste le message
    /// d'erreur, mais déjà typé pour ne pas avoir à reparcourir ce code.
    private enum DownloadStatus {
        case ok
        case clientError(Int)   // 4xx — ne pas retenter
        case serverError(Int)   // 5xx — retenter est défendable
        case unexpected(Int)    // ni 2xx ni 4xx/5xx
    }

    private static func classify(_ http: HTTPURLResponse) -> DownloadStatus {
        switch http.statusCode {
        case 200...299: return .ok
        case 400...499: return .clientError(http.statusCode)
        case 500...599: return .serverError(http.statusCode)
        default:        return .unexpected(http.statusCode)
        }
    }

    // Check if SMAPI is installed in the Stardew Valley MacOS directory
    // — la lecture vit désormais en Core : `SmapiVersionEvidence.installedVersion`.
    // Le verdict de présence et son histoire (X77, X31) y sont documentés.

    // Install SMAPI
    //
    // completion's 3rd parameter is an optional detail string to substitute
    // into the message key's "%@" placeholder (via String(format:)) — the
    // key alone is passed for messages that take no detail. Kept separate
    // (rather than pre-concatenated) because this class has no localization
    // bundle of its own; only the caller (which has `vm.L`) can translate,
    // and concatenating the raw key with detail text before translation
    // would corrupt the lookup key itself.
    func install(gameDir: String, completion: @escaping (Bool, String, String?) -> Void) {
        self.isInstalling = true
        self.statusMessage = L10n.Smapi.downloading
        self.progress = 0.1

        // smapi.io used to serve a `/get/latest` redirect to the current
        // installer zip; that endpoint now returns a bare 404 (confirmed
        // directly — no redirect, empty body). SMAPI's actual distribution
        // channel today is its GitHub Releases page, so resolve the current
        // release through the GitHub API first, then hand the resolved URL
        // to the download/extract/run flow below.
        resolveLatestSmapiInstallerURL { result in
            switch result {
            case .failure(let message, let detail):
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, message, detail)
                }
            case .success(let smapiZipUrl, let version):
                self.downloadAndRunInstaller(from: smapiZipUrl, version: version, gameDir: gameDir, action: .install, completion: completion)
            }
        }
    }

    // Uninstall SMAPI
    //
    // Runs the same official installer as `install()`, answering its
    // uninstall question instead. This used to be done locally (swap
    // `StardewValley-original` back over `StardewValley`, delete
    // `smapi-internal`) without any download — but the installer's current
    // packaging also adds top-level `StardewModdingAPI*` files next to the
    // launcher (see `install()`'s doc comment on `runOfficialInstaller`),
    // and only the official installer itself reliably knows the full set of
    // files it added. Re-downloading it for an uninstall is wasteful but
    // simple and correct; uninstalling isn't a hot path.
    func uninstall(gameDir: String, completion: @escaping (Bool, String, String?) -> Void) {
        let fm = FileManager.default

        // Même marqueur que `SmapiVersionEvidence.installedVersion` (X77) : une installation
        // **propre** ne pose pas `StardewValley-original`, l'ancienne garde
        // refusait donc de désinstaller ce que l'app venait d'installer.
        guard SmapiInstallMarker.isPresent(gameDir: gameDir, fm: fm) else {
            completion(false, L10n.Smapi.notFound, nil)
            return
        }

        self.isInstalling = true
        self.statusMessage = L10n.Smapi.downloading
        self.progress = 0.1

        resolveLatestSmapiInstallerURL { result in
            switch result {
            case .failure(let message, let detail):
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, message, detail)
                }
            case .success(let smapiZipUrl, let version):
                self.downloadAndRunInstaller(from: smapiZipUrl, version: version, gameDir: gameDir, action: .uninstall, completion: completion)
            }
        }
    }

    private enum ReleaseResolution {
        case success(URL, String)
        case failure(String, String?)
    }

    /// Resolves the download URL for SMAPI's current installer zip via the
    /// GitHub Releases API, rather than a hardcoded/redirected URL that can
    /// go stale when the version changes or the host reorganizes its site
    /// (as happened to smapi.io's old `/get/latest` endpoint).
    ///
    /// Each release publishes two zips: a plain installer and a
    /// "-double-zipped" variant (an extra compression layer for platforms
    /// that need it). This app's extractor only unzips once, so it must
    /// pick the plain installer specifically — matching on the filename
    /// pattern rather than assuming a fixed name, since the version number
    /// is embedded in it (e.g. `SMAPI-4.5.2-installer.zip`).
    private func resolveLatestSmapiInstallerURL(completion: @escaping (ReleaseResolution) -> Void) {
        let releaseApiUrl = URL(string: "https://api.github.com/repos/Pathoschild/SMAPI/releases/latest")!
        var request = URLRequest(url: releaseApiUrl)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        // X83 : on passe par la session éphémère — la lookup aussi, pas
        // seulement le download. Un blip côté api.github.com qui laisse
        // traîner la connexion était le scénario de timeout initial.
        let releaseTask = Self.downloadSession().dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(L10n.Smapi.releaseLookupFailed, error.localizedDescription))
                return
            }
            if let http = response as? HTTPURLResponse {
                switch Self.classify(http) {
                case .ok: break
                case .clientError(let code), .serverError(let code), .unexpected(let code):
                    // X88 : la lookup a aussi son verdict typé — un 404 sur
                    // `/releases/latest` peut arriver si le repo devient
                    // privé, et c'est distinct d'un 503 transient.
                    completion(.failure(L10n.Smapi.releaseLookupFailed, "HTTP \(code)"))
                    return
                }
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = json["assets"] as? [[String: Any]] else {
                completion(.failure(L10n.Smapi.releaseLookupFailed, "unparseable release metadata"))
                return
            }
            guard let installerAsset = assets.first(where: { asset in
                      guard let name = asset["name"] as? String else { return false }
                      return name.hasPrefix("SMAPI-") && name.hasSuffix("-installer.zip") && !name.contains("double-zipped")
                  }),
                  let downloadUrlString = installerAsset["browser_download_url"] as? String,
                  let smapiZipUrl = URL(string: downloadUrlString),
                  let version = json["tag_name"] as? String else {
                completion(.failure(L10n.Smapi.releaseLookupFailed, "no installer asset found in latest release"))
                return
            }
            completion(.success(smapiZipUrl, version))
        }
        releaseTask.resume()
    }

    /// Downloads SMAPI's installer zip, extracts it, and hands off to
    /// `runOfficialInstaller`. Older versions of this app manually searched
    /// the archive for a flat `internal/mac/payload` folder and copied its
    /// contents into `gameDir` by hand — that folder no longer exists in
    /// current SMAPI packaging. The archive now ships a real installer
    /// program (`internal/macOS/SMAPI.Installer`) that must be *run*, since
    /// it alone knows which files go where and under what names (verified
    /// directly: it renames some of its own files when copying them into
    /// the game directory, a mapping that isn't recoverable from the zip's
    /// structure alone).
    private func downloadAndRunInstaller(from smapiZipUrl: URL, version: String, gameDir: String, action: SmapiInstallerAction, completion: @escaping (Bool, String, String?) -> Void) {
        // X81 : un UUID sur le nom de dossier rend deux `install()` concurrents
        // indépendants. Sans lui, `smapi_latest.zip` et `smapi_extracted/`
        // sont des cibles nommées : un second appel qui appelle `removeItem`
        // efface le fichier que le premier est encore en train de copier. Le
        // scénario le plus probable est un double-clic sur le bouton
        // « installer », qui passe par le callback UI sans garde — c'est
        // l'audit Phase 2 qui a remonté le piège. Le `defer { removeItem }`
        // sur le `zipDest` et le `extractDir` ferme le filet symétrique :
        // même une exception, le temp est nettoyé.
        let stamp = UUID().uuidString
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("smapi_install_\(stamp)", isDirectory: true)
        let zipDest = tempRoot.appendingPathComponent("installer.zip")
        let extractDir = tempRoot.appendingPathComponent("extracted", isDirectory: true)
        defer {
            // Cleanup best-effort : même une exception, le dossier de tête
            // est nettoyé. Le `try?` est volontaire — un volume plein au
            // moment du cleanup ne doit pas masquer l'erreur métier qui
            // a déclenché le defer.
            try? FileManager.default.removeItem(at: tempRoot)
        }

        // X83 : session dédiée, timeouts 30s/60s, sans cache. Voir
        // `downloadSession()`. Le download hérite désormais des mêmes
        // garanties que la lookup — fini le piège d'un hôte lent qui
        // laisse la completion sans réponse pendant 5 minutes.
        let downloadTask = Self.downloadSession().downloadTask(with: smapiZipUrl) { localURL, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, L10n.Smapi.downloadFailed, error.localizedDescription)
                }
                return
            }

            // We can't verify the download against a published checksum —
            // GitHub's build attestations aren't something this app can
            // practically verify. This checks what we *can*: the server
            // actually served the file (not an error page), and the
            // archive extracted cleanly — before anything downloaded is
            // marked executable or run.
            if let http = response as? HTTPURLResponse {
                switch Self.classify(http) {
                case .ok: break
                // X88 : 4xx (URL changée, asset retiré) et 5xx (rate-limit
                // GitHub) sont **distincts**. Aujourd'hui les deux court-
                // circuitent la même completion, mais le verdict typé est
                // posé pour qu'un futur bouton « réessayer » puisse
                // discriminer sans relecture.
                case .clientError(let code):
                    DispatchQueue.main.async {
                        self.isInstalling = false
                        completion(false, L10n.Smapi.downloadHttpError, "HTTP \(code) — fichier indisponible")
                    }
                    return
                case .serverError(let code):
                    DispatchQueue.main.async {
                        self.isInstalling = false
                        completion(false, L10n.Smapi.downloadHttpError, "HTTP \(code) — réessayez dans quelques minutes")
                    }
                    return
                case .unexpected(let code):
                    DispatchQueue.main.async {
                        self.isInstalling = false
                        completion(false, L10n.Smapi.downloadHttpError, "HTTP \(code)")
                    }
                    return
                }
            }

            guard let localURL = localURL else {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, L10n.Smapi.downloadedFileNotFound, nil)
                }
                return
            }

            let fm = FileManager.default

            do {
                // X81 : `tempRoot` est créé ici, pas avant — on laisse le
                // `defer` gérer le cleanup même si la création échoue.
                try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
                if fm.fileExists(atPath: zipDest.path) { try fm.removeItem(at: zipDest) }
                try fm.copyItem(at: localURL, to: zipDest)

                DispatchQueue.main.async {
                    self.statusMessage = L10n.Smapi.extracting
                    self.progress = 0.4
                }

                if fm.fileExists(atPath: extractDir.path) { try fm.removeItem(at: extractDir) }
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true, attributes: nil)

                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                // `-o` : écraser sans demander. Le dossier vient d'être
                // recréé vide, il n'y a rien d'autre à écraser — mais une
                // archive à chemins dupliqués ferait sinon poser une question
                // sur une entrée standard qui n'existe pas ici. Même ceinture
                // que sur l'extraction des mods.
                unzipProcess.arguments = ["-q", "-o", zipDest.path, "-d", extractDir.path]
                // AGENTS §4.7 : locale POSIX explicite, sinon la locale du
                // parent (système) peut colorer les messages d'erreur et
                // empêcher le parsing en aval.
                unzipProcess.environment = Self.posixLocaleEnvironment()
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                guard unzipProcess.terminationStatus == 0 else {
                    DispatchQueue.main.async {
                        self.isInstalling = false
                        completion(false, L10n.Smapi.extractFailed, "unzip exit code \(unzipProcess.terminationStatus)")
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.statusMessage = L10n.Smapi.preparing
                    self.progress = 0.6
                }

                // The installer's containing folder is versioned (e.g.
                // "SMAPI 4.5.2 installer/"), so search by suffix rather
                // than a fixed path.
                var installerPath: String? = nil
                let enumerator = fm.enumerator(atPath: extractDir.path)
                while let element = enumerator?.nextObject() as? String {
                    if element.hasSuffix("internal/macOS/SMAPI.Installer") {
                        installerPath = (extractDir.path as NSString).appendingPathComponent(element)
                        break
                    }
                }

                guard let smapiInstallerBin = installerPath, fm.fileExists(atPath: smapiInstallerBin) else {
                    DispatchQueue.main.async {
                        self.isInstalling = false
                        completion(false, L10n.Smapi.payloadNotFound, nil)
                    }
                    return
                }

                // The installer and its dependencies were just downloaded, so
                // macOS marks them quarantined; running a quarantined binary
                // via Process (bypassing the normal double-click Gatekeeper
                // flow) fails until the quarantine attribute is cleared. The
                // official "install on macOS.command" script does the same
                // thing, recursively, on the whole `internal` folder next to
                // the binary — mirrored here so this behaves identically.
                let macOSDir = (smapiInstallerBin as NSString).deletingLastPathComponent
                let internalRoot = (macOSDir as NSString).deletingLastPathComponent
                let xattrProcess = Process()
                xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattrProcess.arguments = ["-r", "-d", "com.apple.quarantine", internalRoot]
                // AGENTS §4.7 : voir `posixLocaleEnvironment()`. Pour `xattr`,
                // l'enjeu est nul en pratique (sa sortie est vide au succès),
                // mais on garde la règle uniforme.
                xattrProcess.environment = Self.posixLocaleEnvironment()
                try? xattrProcess.run()
                xattrProcess.waitUntilExit()

                var attributes = try fm.attributesOfItem(atPath: smapiInstallerBin)
                attributes[.posixPermissions] = 0o755
                try fm.setAttributes(attributes, ofItemAtPath: smapiInstallerBin)

                DispatchQueue.main.async {
                    self.statusMessage = L10n.Smapi.preparing
                    self.progress = 0.8
                }

                self.runOfficialInstaller(at: smapiInstallerBin, version: version, gameDir: gameDir, action: action) { success, message, detail in
                    // Le temp est nettoyé par le `defer` posé en tête de
                    // `downloadAndRunInstaller` — ne pas le faire ici, ce
                    // serait un cleanup local à un scope plus étroit que
                    // celui qui survivra à une exception de `runOfficialInstaller`.
                    DispatchQueue.main.async {
                        self.progress = success ? 1.0 : self.progress
                        self.isInstalling = false
                        completion(success, message, detail)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, L10n.Smapi.installError, error.localizedDescription)
                }
            }
        }

        downloadTask.resume()
    }

    /// Runs SMAPI's own official installer binary non-interactively through
    /// its command-line flags (X32): `--install`/`--uninstall` declares the
    /// action, `--game-path` declares the folder — only the color-scheme
    /// question remains on stdin, answered with `1`.
    ///
    /// Mesuré le 2026-09-06 sur le vrai binaire 4.5.2, lancé sur une
    /// installation de contrôle (dossier factice avec `Stardew Valley`,
    /// `Stardew Valley.dll`, `.deps.json`, `.runtimeconfig.json`) : sous
    /// drapeaux l'installateur annonce « Just one question first » — le jeu
    /// de couleurs — puis « That's all I need! ». L'ancien pilotage écrivait
    /// quatre réponses d'un coup (`1`, `2`, le chemin, l'action) dans un
    /// ordre supposé stable : une seule question réordonnée par une future
    /// version décalait toute la file — le chemin devenait la réponse à une
    /// autre question. Bonus mesuré : un dossier sans jeu rend « Failed
    /// finding your game path. » et **sort**, au lieu de reboucler la
    /// question à l'infini sur stdin fermé (l'amorce de X30).
    ///
    /// The process's exit code alone isn't fully trustworthy: on its error
    /// path, the installer tries to read a keypress before exiting, which
    /// can throw an unhandled .NET exception (and a non-zero exit) whenever
    /// stdin isn't a real terminal — measured: the exit code is 0 on some
    /// failures too. So success is determined by a combination of the
    /// installer's own "done" message and concrete file-system evidence,
    /// not the exit code by itself.
    ///
    /// On a successful install, also writes `version` to
    /// `SmapiInstallMarker.installedVersionRelativePath` — verified directly against a
    /// real install that nothing else on disk reliably states SMAPI's own
    /// version afterward (see `SmapiVersionEvidence.installedVersion`'s doc
    /// comment), so this app records what it just installed instead of
    /// guessing later.
    private func runOfficialInstaller(at installerPath: String, version: String, gameDir: String, action: SmapiInstallerAction, completion: @escaping (Bool, String, String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: installerPath)
        process.arguments = SmapiInstallerInvocation.arguments(action: action, gamePath: gameDir)
        // AGENTS §4.7 : SMAPI est un binaire .NET dont la sortie dépend de
        // la locale. Les deux messages qui déclenchent le verdict de succès
        // (« SMAPI is installed! » / « SMAPI is removed! ») et le rendu de
        // `lastMeaningfulLine` ne sont tenables qu'en locale POSIX. Sans
        // cette pose, un système francophone basculerait l'installateur sur
        // sa propre traduction et le check `output.contains(...)` tomberait
        // en échec. Le coût est nul, le filet est mesurable.
        process.environment = Self.posixLocaleEnvironment()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stdoutPipe

        let answers = SmapiInstallerInvocation.stdinAnswers

        do {
            try process.run()
        } catch {
            completion(false, L10n.Smapi.installError, error.localizedDescription)
            return
        }

        stdinPipe.fileHandleForWriting.write(answers.data(using: .utf8) ?? Data())
        try? stdinPipe.fileHandleForWriting.close()

        // Lecture **bornée**, pas `readDataToEndOfFile()` : une réponse que
        // l'installateur refuse le fait reposer sa question à une entrée déjà
        // close, indéfiniment — mesuré à 6 Mo par seconde, tous accumulés en
        // mémoire (voir `SmapiInstallerLimits`).
        let handle = stdoutPipe.fileHandleForReading
        let limits = SmapiInstallerLimits.standard
        let start = Date()
        var outputData = Data()
        var aborted: SmapiInstallerLimits.Abort?
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }  // fin du tube
            outputData.append(chunk)
            if let verdict = limits.abort(bytesRead: outputData.count,
                                          elapsed: Date().timeIntervalSince(start)) {
                aborted = verdict
                // On s'assure **d'abord** que plus personne n'écrit, et sans
                // jamais lire pour l'attendre : une horloge consultée entre
                // deux lectures bloquantes n'avance pas tant que l'enfant
                // parle, et on rejouerait la panne qu'on répare. Mesuré sur
                // l'installateur 4.5.2 en plein flot : SIGTERM le tue en
                // 0,02 s — la borne d'une seconde est cinquante fois large,
                // et `SIGKILL` ferme le cas d'un enfant qui l'ignorerait.
                process.terminate()
                let deadline = Date().addingTimeInterval(1)
                while process.isRunning, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                // Vidange : l'écrivain est mort, la fin du tube est donc
                // certaine. Sans elle, un tube plein retiendrait l'enfant.
                while !handle.availableData.isEmpty {}
                break
            }
        }
        process.waitUntilExit()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        if let aborted {
            // Message à part : « erreur d'installation » n'aiderait personne
            // ici. Ce qui a coupé, c'est presque toujours un dossier de jeu
            // que l'installateur refuse — et c'est réparable.
            completion(false, L10n.Smapi.installerAborted, aborted.rawValue)
            return
        }

        let fm = FileManager.default
        let smapiInternalPath = (gameDir as NSString).appendingPathComponent(SmapiInstallMarker.folderName)

        switch action {
        case .install:
            let succeeded = output.contains("SMAPI is installed!") && fm.fileExists(atPath: smapiInternalPath)
            if succeeded {
                let markerPath = (gameDir as NSString).appendingPathComponent(SmapiInstallMarker.installedVersionRelativePath)
                do {
                    try version.write(toFile: markerPath, atomically: true, encoding: .utf8)
                } catch {
                    // Le marqueur est un cache de version pour l'UI ; SMAPI est bien
                    // installé. Consigner l'échec — sinon l'app croit au prochain
                    // lancement que SMAPI est absent (jusqu'à la re-détection).
                    onWarning?("SMAPI install succeeded but version marker write failed at \(markerPath): \(error.localizedDescription)")
                }
                completion(true, L10n.Smapi.installSuccess, nil)
            } else {
                completion(false, L10n.Smapi.installError, Self.lastMeaningfulLine(of: output))
            }
        case .uninstall:
            let succeeded = output.contains("SMAPI is removed!") && !fm.fileExists(atPath: smapiInternalPath)
            if succeeded {
                completion(true, L10n.Smapi.uninstallSuccess, nil)
            } else {
                completion(false, L10n.Smapi.uninstallFailed, Self.lastMeaningfulLine(of: output))
            }
        }
    }

    /// Picks a short, useful line from the installer's captured output for
    /// the error detail shown to the user.
    ///
    /// La règle vit dans `SmapiInstallerOutput` (Core) : ce fichier n'est pas
    /// dans le paquet testable, et c'est pourtant tout ce que l'utilisateur
    /// apprend d'un échec.
    private static func lastMeaningfulLine(of output: String) -> String {
        SmapiInstallerOutput.lastMeaningfulLine(of: output)
    }
}
