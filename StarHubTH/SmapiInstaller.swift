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
    func install(gameDir: String, completion: @escaping (Bool, String) -> Void) {
        self.isInstalling = true
        self.statusMessage = L10n.Smapi.downloading
        self.progress = 0.1
        
        let smapiZipUrl = URL(string: "https://smapi.io/get/latest")!
        let tempDir = NSTemporaryDirectory()
        let zipDest = URL(fileURLWithPath: tempDir).appendingPathComponent("smapi_latest.zip")
        
        let downloadTask = URLSession.shared.downloadTask(with: smapiZipUrl) { localURL, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    // Pass key + actual message so caller can format: vm.L(key) + detail
                    completion(false, L10n.Smapi.downloadFailed + error.localizedDescription)
                }
                return
            }
            
            guard let localURL = localURL else {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, L10n.Smapi.downloadedFileNotFound)
                }
                return
            }
            
            do {
                let fm = FileManager.default
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
                        completion(false, L10n.Smapi.payloadNotFound)
                    }
                    return
                }
                
                let targetGameBin = (gameDir as NSString).appendingPathComponent("StardewValley")
                let backupGameBin = (gameDir as NSString).appendingPathComponent("StardewValley-original")
                
                if fm.fileExists(atPath: targetGameBin) && !fm.fileExists(atPath: backupGameBin) {
                    try fm.copyItem(atPath: targetGameBin, toPath: backupGameBin)
                }
                
                let payloadItems = try fm.contentsOfDirectory(atPath: sourcePayload)
                for item in payloadItems {
                    if item.hasPrefix(".") { continue }
                    let srcItem = (sourcePayload as NSString).appendingPathComponent(item)
                    let destItem = (gameDir as NSString).appendingPathComponent(item)
                    if fm.fileExists(atPath: destItem) { try fm.removeItem(atPath: destItem) }
                    try fm.copyItem(atPath: srcItem, toPath: destItem)
                }
                
                var attributes = try fm.attributesOfItem(atPath: targetGameBin)
                attributes[.posixPermissions] = 0o755
                try fm.setAttributes(attributes, ofItemAtPath: targetGameBin)
                
                try? fm.removeItem(at: zipDest)
                try? fm.removeItem(at: extractDir)
                
                DispatchQueue.main.async {
                    self.progress = 1.0
                    self.isInstalling = false
                    completion(true, L10n.Smapi.installSuccess)
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, L10n.Smapi.installError + error.localizedDescription)
                }
            }
        }
        
        downloadTask.resume()
    }
    
    // Uninstall SMAPI
    func uninstall(gameDir: String, completion: @escaping (Bool, String) -> Void) {
        let fm = FileManager.default
        let launcherPath = (gameDir as NSString).appendingPathComponent("StardewValley")
        let originalPath = (gameDir as NSString).appendingPathComponent("StardewValley-original")
        let internalPath = (gameDir as NSString).appendingPathComponent("smapi-internal")
        
        guard fm.fileExists(atPath: originalPath) else {
            completion(false, L10n.Smapi.notFound)
            return
        }
        
        do {
            if fm.fileExists(atPath: launcherPath) { try fm.removeItem(atPath: launcherPath) }
            try fm.moveItem(atPath: originalPath, toPath: launcherPath)
            if fm.fileExists(atPath: internalPath) { try fm.removeItem(atPath: internalPath) }
            completion(true, L10n.Smapi.uninstallSuccess)
        } catch {
            completion(false, L10n.Smapi.uninstallFailed + error.localizedDescription)
        }
    }
}
