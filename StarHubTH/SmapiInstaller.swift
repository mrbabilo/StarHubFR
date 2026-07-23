import Foundation

class SmapiInstaller: ObservableObject {
    @Published var isInstalling = false
    @Published var statusMessage = ""   // holds an L10n key, translated by caller via vm.L()
    @Published var progress: Double = 0.0
    
    // Check if SMAPI is installed in the Stardew Valley MacOS directory
    static func getInstalledVersion(gameDir: String) -> String? {
        let fm = FileManager.default
        let originalPath = (gameDir as NSString).appendingPathComponent("StardewValley-original")

        // SMAPI must have replaced the launcher
        guard fm.fileExists(atPath: originalPath) else { return nil }

        // 1. Try smapi-internal/manifest.json (standard path)
        let manifestPath = (gameDir as NSString).appendingPathComponent("smapi-internal/manifest.json")
        if fm.fileExists(atPath: manifestPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let version = json["Version"] as? String {
            return version
        }

        // 2. Fallback: parse version from SMAPI-latest.txt first line
        // Format: [HH:MM:SS INFO  SMAPI] SMAPI 4.5.2 with Stardew Valley ...
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let logPath = (home as NSString).appendingPathComponent(
            ".config/StardewValley/ErrorLogs/SMAPI-latest.txt"
        )
        if fm.fileExists(atPath: logPath),
           let handle = FileHandle(forReadingAtPath: logPath) {
            let data = handle.readData(ofLength: 256)
            try? handle.close()
            if let line = String(data: data, encoding: .utf8)?
                .components(separatedBy: .newlines).first,
               let range = line.range(of: #"SMAPI (\d+\.\d+\.\d+)"#, options: .regularExpression) {
                let match = String(line[range])
                let version = match.replacingOccurrences(of: "SMAPI ", with: "")
                return version
            }
        }

        // 3. Installed but version unknown
        return "Installed"
    }
    
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
        // to the existing download/extract/install flow below.
        resolveLatestSmapiInstallerURL { result in
            switch result {
            case .failure(let message, let detail):
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, message, detail)
                }
            case .success(let smapiZipUrl):
                self.downloadAndInstall(from: smapiZipUrl, gameDir: gameDir, completion: completion)
            }
        }
    }

    private enum ReleaseResolution {
        case success(URL)
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

        let releaseTask = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(L10n.Smapi.releaseLookupFailed, error.localizedDescription))
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(L10n.Smapi.releaseLookupFailed, "HTTP \(http.statusCode)"))
                return
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
                  let smapiZipUrl = URL(string: downloadUrlString) else {
                completion(.failure(L10n.Smapi.releaseLookupFailed, "no installer asset found in latest release"))
                return
            }
            completion(.success(smapiZipUrl))
        }
        releaseTask.resume()
    }

    private func downloadAndInstall(from smapiZipUrl: URL, gameDir: String, completion: @escaping (Bool, String, String?) -> Void) {
        let tempDir = NSTemporaryDirectory()
        let zipDest = URL(fileURLWithPath: tempDir).appendingPathComponent("smapi_latest.zip")

        let downloadTask = URLSession.shared.downloadTask(with: smapiZipUrl) { localURL, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, L10n.Smapi.downloadFailed, error.localizedDescription)
                }
                return
            }
            
            // We can't verify the download against a published checksum —
            // smapi.io's redirect endpoint doesn't expose one, and GitHub's
            // build attestations aren't something this app can practically
            // verify. This checks what we *can*: the server actually served
            // the file (not an error page), the archive extracted cleanly,
            // and the payload it produced is non-empty — before anything is
            // chmod'd executable or copied over the player's game files.
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, L10n.Smapi.downloadHttpError, "HTTP \(http.statusCode)")
                }
                return
            }

            guard let localURL = localURL else {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, L10n.Smapi.downloadedFileNotFound, nil)
                }
                return
            }

            let fm = FileManager.default
            let targetGameBin = (gameDir as NSString).appendingPathComponent("StardewValley")
            let backupGameBin = (gameDir as NSString).appendingPathComponent("StardewValley-original")
            // Set once we start overwriting files in `gameDir` itself, so the
            // catch block below only attempts a rollback for failures that
            // happen after the game's own launcher was actually touched —
            // not for a download/extract failure that never got that far.
            var gameFilesModified = false
            // Every payload item this run has copied into `gameDir`, in copy
            // order — lets a failure partway through the loop below undo
            // exactly what this run changed (not just the launcher binary).
            // Declared here (not inside the `do` block) because `do`-scoped
            // locals aren't visible to the matching `catch`.
            var installedItems: [String] = []
            // Transient per-run staging for items this run overwrites, so
            // they can be moved back on failure. Distinct from
            // `backupGameBin`, which is a *permanent* record `uninstall()`
            // and `getInstalledVersion(gameDir:)` rely on — this directory
            // is always removed at the end of this run, success or failure.
            let rollbackStagingDir = URL(fileURLWithPath: tempDir).appendingPathComponent("smapi_install_rollback")

            do {
                if fm.fileExists(atPath: zipDest.path) { try fm.removeItem(at: zipDest) }
                try fm.copyItem(at: localURL, to: zipDest)
                
                DispatchQueue.main.async {
                    self.statusMessage = L10n.Smapi.extracting
                    self.progress = 0.4
                }
                
                let extractDir = URL(fileURLWithPath: tempDir).appendingPathComponent("smapi_extracted")
                if fm.fileExists(atPath: extractDir.path) { try fm.removeItem(at: extractDir) }
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true, attributes: nil)
                
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzipProcess.arguments = ["-q", zipDest.path, "-d", extractDir.path]
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
                    self.progress = 0.7
                }
                
                var payloadDir: String? = nil
                let enumerator = fm.enumerator(atPath: extractDir.path)
                while let element = enumerator?.nextObject() as? String {
                    if element.hasSuffix("internal/mac/payload") {
                        payloadDir = (extractDir.path as NSString).appendingPathComponent(element)
                        break
                    }
                }
                
                guard let sourcePayload = payloadDir, fm.fileExists(atPath: sourcePayload) else {
                    DispatchQueue.main.async {
                        self.isInstalling = false
                        completion(false, L10n.Smapi.payloadNotFound, nil)
                    }
                    return
                }

                // Confirm the extracted payload actually has files before we
                // touch anything in `gameDir` — a truncated/incomplete
                // archive can unzip "successfully" while producing an empty
                // or partial payload folder.
                let payloadItems = try fm.contentsOfDirectory(atPath: sourcePayload)
                guard !payloadItems.isEmpty else {
                    DispatchQueue.main.async {
                        self.isInstalling = false
                        completion(false, L10n.Smapi.payloadNotFound, nil)
                    }
                    return
                }

                if fm.fileExists(atPath: targetGameBin) && !fm.fileExists(atPath: backupGameBin) {
                    try fm.copyItem(atPath: targetGameBin, toPath: backupGameBin)
                }

                // From here on we're overwriting files inside `gameDir`; if
                // anything below throws, the catch block restores the
                // original launcher from `backupGameBin` rather than leaving
                // the game in a half-installed, unplayable state.
                gameFilesModified = true

                if fm.fileExists(atPath: rollbackStagingDir.path) {
                    try? fm.removeItem(at: rollbackStagingDir)
                }
                try fm.createDirectory(at: rollbackStagingDir, withIntermediateDirectories: true, attributes: nil)

                for item in payloadItems {
                    if item.hasPrefix(".") { continue }
                    let srcItem = (sourcePayload as NSString).appendingPathComponent(item)
                    let destItem = (gameDir as NSString).appendingPathComponent(item)
                    if fm.fileExists(atPath: destItem) {
                        let stagedItem = rollbackStagingDir.appendingPathComponent(item).path
                        try fm.moveItem(atPath: destItem, toPath: stagedItem)
                    }
                    try fm.copyItem(atPath: srcItem, toPath: destItem)
                    installedItems.append(item)
                }

                var attributes = try fm.attributesOfItem(atPath: targetGameBin)
                attributes[.posixPermissions] = 0o755
                try fm.setAttributes(attributes, ofItemAtPath: targetGameBin)
                
                try? fm.removeItem(at: rollbackStagingDir)
                try? fm.removeItem(at: zipDest)
                try? fm.removeItem(at: extractDir)

                DispatchQueue.main.async {
                    self.progress = 1.0
                    self.isInstalling = false
                    completion(true, L10n.Smapi.installSuccess, nil)
                }

            } catch {
                let installErrorMessage = error.localizedDescription

                // Undo every payload item this run already copied in, restoring
                // whatever was staged aside for it (or just removing it if the
                // item didn't exist before this run), so a failure partway
                // through the copy loop doesn't leave a mix of old and new files.
                for item in installedItems.reversed() {
                    let destItem = (gameDir as NSString).appendingPathComponent(item)
                    let stagedItem = rollbackStagingDir.appendingPathComponent(item).path
                    try? fm.removeItem(atPath: destItem)
                    if fm.fileExists(atPath: stagedItem) {
                        try? fm.moveItem(atPath: stagedItem, toPath: destItem)
                    }
                }
                try? fm.removeItem(at: rollbackStagingDir)

                // If we'd already started overwriting the game's own files
                // when this failed, try to put the original launcher back
                // rather than leaving the game unplayable.
                if gameFilesModified && fm.fileExists(atPath: backupGameBin) {
                    do {
                        if fm.fileExists(atPath: targetGameBin) { try fm.removeItem(atPath: targetGameBin) }
                        try fm.copyItem(atPath: backupGameBin, toPath: targetGameBin)
                        DispatchQueue.main.async {
                            self.isInstalling = false
                            completion(false, L10n.Smapi.installErrorRestored, installErrorMessage)
                        }
                    } catch let restoreError {
                        DispatchQueue.main.async {
                            self.isInstalling = false
                            completion(false, L10n.Smapi.installErrorRestoreFailed, "\(installErrorMessage) / \(restoreError.localizedDescription)")
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isInstalling = false
                        completion(false, L10n.Smapi.installError, installErrorMessage)
                    }
                }
            }
        }

        downloadTask.resume()
    }
    
    // Uninstall SMAPI
    func uninstall(gameDir: String, completion: @escaping (Bool, String, String?) -> Void) {
        let fm = FileManager.default
        let launcherPath = (gameDir as NSString).appendingPathComponent("StardewValley")
        let originalPath = (gameDir as NSString).appendingPathComponent("StardewValley-original")
        let internalPath = (gameDir as NSString).appendingPathComponent("smapi-internal")

        guard fm.fileExists(atPath: originalPath) else {
            completion(false, L10n.Smapi.notFound, nil)
            return
        }

        self.isInstalling = true
        self.statusMessage = L10n.Smapi.uninstallSuccess
        self.progress = 0.2

        // Runs on a background queue (unlike `install`'s network download,
        // which already hops off main via URLSession) so this doesn't block
        // the caller — the moves/removes below still touch the game folder
        // directly and aren't free on a slow disk.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Move the current (SMAPI) launcher aside instead of deleting
                // it outright, so it can be put back if restoring the
                // original fails below — otherwise a failure here leaves
                // neither launcher in place and the game won't start at all.
                var setAsideLauncher: String? = nil
                if fm.fileExists(atPath: launcherPath) {
                    let tempPath = launcherPath + ".smapi_uninstall_tmp"
                    if fm.fileExists(atPath: tempPath) { try? fm.removeItem(atPath: tempPath) }
                    try fm.moveItem(atPath: launcherPath, toPath: tempPath)
                    setAsideLauncher = tempPath
                }
                DispatchQueue.main.async { self.progress = 0.6 }

                do {
                    try fm.moveItem(atPath: originalPath, toPath: launcherPath)
                } catch {
                    if let setAsideLauncher = setAsideLauncher {
                        try? fm.moveItem(atPath: setAsideLauncher, toPath: launcherPath)
                    }
                    throw error
                }

                if let setAsideLauncher = setAsideLauncher { try? fm.removeItem(atPath: setAsideLauncher) }
                if fm.fileExists(atPath: internalPath) { try fm.removeItem(atPath: internalPath) }

                DispatchQueue.main.async {
                    self.progress = 1.0
                    self.isInstalling = false
                    completion(true, L10n.Smapi.uninstallSuccess, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, L10n.Smapi.uninstallFailed, error.localizedDescription)
                }
            }
        }
    }
}
