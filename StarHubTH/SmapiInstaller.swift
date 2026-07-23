import Foundation

class SmapiInstaller: ObservableObject {
    @Published var isInstalling = false
    @Published var statusMessage = ""   // holds an L10n key, translated by caller via vm.L()
    @Published var progress: Double = 0.0

    /// File `install()` writes on success, holding the plain version string
    /// (e.g. "4.5.2") of the release it just installed — see
    /// `runOfficialInstaller`'s doc comment for why this exists.
    private static let installedVersionMarkerRelativePath = "smapi-internal/.starhubth-installed-version"

    // Check if SMAPI is installed in the Stardew Valley MacOS directory
    static func getInstalledVersion(gameDir: String) -> String? {
        let fm = FileManager.default
        let originalPath = (gameDir as NSString).appendingPathComponent("StardewValley-original")

        // SMAPI must have replaced the launcher
        guard fm.fileExists(atPath: originalPath) else { return nil }

        // 1. Our own marker, written by `install()` right after a successful
        // run. SMAPI's packaging no longer includes anything that reliably
        // states its own version (verified directly against a real
        // install: no `smapi-internal/manifest.json`, the installed
        // `StardewModdingAPI.deps.json` is an empty stub, and
        // `StardewModdingAPI.runtimeconfig.json` only names the .NET
        // runtime version, not SMAPI's) — so this app records what it
        // installed itself instead of guessing from artifacts afterward.
        let markerPath = (gameDir as NSString).appendingPathComponent(installedVersionMarkerRelativePath)
        if let version = try? String(contentsOfFile: markerPath, encoding: .utf8) {
            let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        // 2. Fallback: parse version from SMAPI-latest.txt first line, for
        // an install this app didn't perform itself (e.g. installed
        // manually, or by a version of this app that predates the marker
        // above). Only available after the game has been launched at least
        // once post-install.
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
        let originalPath = (gameDir as NSString).appendingPathComponent("StardewValley-original")

        guard fm.fileExists(atPath: originalPath) else {
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
                  let smapiZipUrl = URL(string: downloadUrlString),
                  let version = json["tag_name"] as? String else {
                completion(.failure(L10n.Smapi.releaseLookupFailed, "no installer asset found in latest release"))
                return
            }
            completion(.success(smapiZipUrl, version))
        }
        releaseTask.resume()
    }

    private enum InstallerAction: String {
        case install = "1"
        case uninstall = "2"
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
    private func downloadAndRunInstaller(from smapiZipUrl: URL, version: String, gameDir: String, action: InstallerAction, completion: @escaping (Bool, String, String?) -> Void) {
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
            // GitHub's build attestations aren't something this app can
            // practically verify. This checks what we *can*: the server
            // actually served the file (not an error page), and the
            // archive extracted cleanly — before anything downloaded is
            // marked executable or run.
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
                    try? fm.removeItem(at: zipDest)
                    try? fm.removeItem(at: extractDir)
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

    /// Runs SMAPI's own official installer binary non-interactively by
    /// feeding its fixed prompt sequence through stdin in one write:
    /// color scheme, "enter a custom game path" (option 2 — never trust
    /// its auto-detected option 1, which only matches well-known install
    /// locations), the game path itself, then install (1) or uninstall (2).
    /// Verified directly against a real download: this sequence is stable,
    /// short, and doesn't require synchronizing on the installer's output
    /// text (which could reword between versions) — stdin is a queue the
    /// installer's prompts consume from in order, regardless of what's
    /// already been printed.
    ///
    /// The process's exit code alone isn't fully trustworthy: on its error
    /// path, the installer tries to read a keypress before exiting, which
    /// throws an unhandled .NET exception (and a non-zero exit) whenever
    /// stdin isn't a real terminal — including some cases that already
    /// completed the actual install/uninstall work. So success is
    /// determined by a combination of the installer's own "done" message
    /// and concrete file-system evidence, not the exit code by itself.
    ///
    /// On a successful install, also writes `version` to
    /// `installedVersionMarkerRelativePath` — verified directly against a
    /// real install that nothing else on disk reliably states SMAPI's own
    /// version afterward (see `getInstalledVersion`'s doc comment), so this
    /// app records what it just installed instead of guessing later.
    private func runOfficialInstaller(at installerPath: String, version: String, gameDir: String, action: InstallerAction, completion: @escaping (Bool, String, String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: installerPath)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stdoutPipe

        let answers = "1\n2\n\(gameDir)\n\(action.rawValue)\n"

        do {
            try process.run()
        } catch {
            completion(false, L10n.Smapi.installError, error.localizedDescription)
            return
        }

        stdinPipe.fileHandleForWriting.write(answers.data(using: .utf8) ?? Data())
        try? stdinPipe.fileHandleForWriting.close()

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        let fm = FileManager.default
        let smapiInternalPath = (gameDir as NSString).appendingPathComponent("smapi-internal")

        switch action {
        case .install:
            let succeeded = output.contains("SMAPI is installed!") && fm.fileExists(atPath: smapiInternalPath)
            if succeeded {
                let markerPath = (gameDir as NSString).appendingPathComponent(Self.installedVersionMarkerRelativePath)
                try? version.write(toFile: markerPath, atomically: true, encoding: .utf8)
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
    /// the error detail shown to the user. Its crash output ends in a C#
    /// stack trace, which isn't useful verbatim — the actual error message
    /// is the line announcing the exception, so surface that instead of the
    /// trace beneath it.
    private static func lastMeaningfulLine(of output: String) -> String {
        let lines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        if let idx = lines.firstIndex(where: { $0.contains("unexpected exception") || $0.contains("failed") }) {
            return lines[idx]
        }
        return lines.last(where: { !$0.isEmpty }) ?? "unknown error"
    }
}
