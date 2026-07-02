import Foundation

class SmapiInstaller: ObservableObject {
    @Published var isInstalling = false
    @Published var statusMessage = ""
    @Published var progress: Double = 0.0
    
    // Check if SMAPI is installed in the Stardew Valley MacOS directory
    static func getInstalledVersion(gameDir: String) -> String? {
        let fm = FileManager.default
        let originalPath = (gameDir as NSString).appendingPathComponent("StardewValley-original")
        let manifestPath = (gameDir as NSString).appendingPathComponent("smapi-internal/manifest.json")
        
        guard fm.fileExists(atPath: originalPath) else { return nil }
        
        if fm.fileExists(atPath: manifestPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let version = json["Version"] as? String {
            return version
        }
        return "Installed"
    }
    
    // Install SMAPI
    func install(gameDir: String, completion: @escaping (Bool, String) -> Void) {
        self.isInstalling = true
        self.statusMessage = "กำลังเริ่มดาวน์โหลด SMAPI..."
        self.progress = 0.1
        
        // We use the direct SMAPI download URL for the latest version
        let smapiZipUrl = URL(string: "https://smapi.io/get/latest")!
        
        let tempDir = NSTemporaryDirectory()
        let zipDest = URL(fileURLWithPath: tempDir).appendingPathComponent("smapi_latest.zip")
        
        // 1. Download Zip
        let downloadTask = URLSession.shared.downloadTask(with: smapiZipUrl) { localURL, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, "ดาวน์โหลดล้มเหลว: \(error.localizedDescription)")
                }
                return
            }
            
            guard let localURL = localURL else {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, "ไม่พบข้อมูลไฟล์ที่ดาวน์โหลด")
                }
                return
            }
            
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: zipDest.path) {
                    try fm.removeItem(at: zipDest)
                }
                try fm.copyItem(at: localURL, to: zipDest)
                
                DispatchQueue.main.async {
                    self.statusMessage = "ดาวน์โหลดสำเร็จ กำลังคลายไฟล์..."
                    self.progress = 0.4
                }
                
                // 2. Unzip using temporary directory shell execution (to avoid importing heavy external libraries for a quick draft)
                let extractDir = URL(fileURLWithPath: tempDir).appendingPathComponent("smapi_extracted")
                if fm.fileExists(atPath: extractDir.path) {
                    try fm.removeItem(at: extractDir)
                }
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true, attributes: nil)
                
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzipProcess.arguments = ["-q", zipDest.path, "-d", extractDir.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()
                
                DispatchQueue.main.async {
                    self.statusMessage = "เตรียมติดตั้ง SMAPI ลงในตัวเกม..."
                    self.progress = 0.7
                }
                
                // 3. Locate the payload folder inside extracted directory
                // Typically: smapi_extracted/SMAPI <version> installer/internal/mac/payload/
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
                        completion(false, "ไม่พบไฟล์ Payload สำหรับติดตั้งภายใน SMAPI Zip")
                    }
                    return
                }
                
                // 4. Back up original game binary if not already backed up
                let targetGameBin = (gameDir as NSString).appendingPathComponent("StardewValley")
                let backupGameBin = (gameDir as NSString).appendingPathComponent("StardewValley-original")
                
                if fm.fileExists(atPath: targetGameBin) && !fm.fileExists(atPath: backupGameBin) {
                    try fm.copyItem(atPath: targetGameBin, toPath: backupGameBin)
                }
                
                // 5. Copy payload items into the game MacOS directory
                let payloadItems = try fm.contentsOfDirectory(atPath: sourcePayload)
                for item in payloadItems {
                    if item.hasPrefix(".") { continue }
                    let srcItem = (sourcePayload as NSString).appendingPathComponent(item)
                    let destItem = (gameDir as NSString).appendingPathComponent(item)
                    
                    if fm.fileExists(atPath: destItem) {
                        try fm.removeItem(atPath: destItem)
                    }
                    try fm.copyItem(atPath: srcItem, toPath: destItem)
                }
                
                // 6. Set Executable permission (+x, 755) to the new StardewValley launcher
                var attributes = try fm.attributesOfItem(atPath: targetGameBin)
                attributes[.posixPermissions] = 0o755
                try fm.setAttributes(attributes, ofItemAtPath: targetGameBin)
                
                // Cleanup temp
                try? fm.removeItem(at: zipDest)
                try? fm.removeItem(at: extractDir)
                
                DispatchQueue.main.async {
                    self.progress = 1.0
                    self.isInstalling = false
                    completion(true, "ติดตั้ง SMAPI เรียบร้อยแล้ว!")
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, "การติดตั้งเกิดข้อผิดพลาด: \(error.localizedDescription)")
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
            completion(false, "ไม่พบข้อมูลการติดตั้ง SMAPI ในโฟลเดอร์นี้")
            return
        }
        
        do {
            // Restore original game launcher
            if fm.fileExists(atPath: launcherPath) {
                try fm.removeItem(atPath: launcherPath)
            }
            try fm.moveItem(atPath: originalPath, toPath: launcherPath)
            
            // Clean up smapi-internal
            if fm.fileExists(atPath: internalPath) {
                try fm.removeItem(atPath: internalPath)
            }
            
            completion(true, "ถอนการติดตั้ง SMAPI สำเร็จ! คืนค่าตัวเกมหลักเรียบร้อย")
        } catch {
            completion(false, "ถอนการติดตั้งล้มเหลว: \(error.localizedDescription)")
        }
    }
}
