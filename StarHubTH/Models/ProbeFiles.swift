import Foundation

/// Les fichiers de la sonde StarHubFR sur disque (D4-T2). Tout est
/// facultatif : sans la sonde, aucun fichier, et chaque lecture rend `nil`
/// ou un résultat vide — jamais une erreur.
public struct ProbeFiles: Sendable {
    public static var defaultDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/StardewValley/ModData/mrbabilo.StarHubFR.Probe", isDirectory: true)
    }

    public let directory: URL

    public init(directory: URL = ProbeFiles.defaultDirectory) {
        self.directory = directory
    }

    public var harmonyMapURL: URL { directory.appendingPathComponent("harmony-map.json") }
    public var gmcmOptionsURL: URL { directory.appendingPathComponent("gmcm-options.json") }
    public var timingsURL: URL { directory.appendingPathComponent("timings.jsonl") }
    public var costsURL: URL { directory.appendingPathComponent("mod-costs.jsonl") }
    public var inventoryURL: URL { directory.appendingPathComponent("inventory.jsonl") }
    public var configsDirectory: URL { directory.appendingPathComponent("configs", isDirectory: true) }

    public func harmonyMap() -> ProbeHarmonyMap? {
        contents("harmony-map.json").flatMap(ProbeHarmonyMap.decode)
    }

    public func gmcmCapture() -> GmcmCapture? {
        contents("gmcm-options.json").flatMap(GmcmCapture.decode)
    }

    public func sessions() -> ProbeSessions {
        ProbeSessions.decode(timings: contents("timings.jsonl"), costs: contents("mod-costs.jsonl"))
    }

    public func inventory() -> (launches: [ProbeInventoryLaunch],
                                changes: [ProbeInventoryChange], unreadable: Int)? {
        contents("inventory.jsonl").map(ProbeInventory.decode)
    }

    private func contents(_ name: String) -> Data? {
        FileManager.default.contents(atPath: directory.appendingPathComponent(name).path)
    }
}

/// Date de modification et taille d'un fichier de la sonde : ce qui dit aux
/// caches qu'une nouvelle session l'a réécrit. `nil` = fichier absent.
struct ProbeFileStamp: Equatable {
    let modified: Date
    let size: Int

    static func of(_ url: URL) -> ProbeFileStamp? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let modified = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? Int else { return nil }
            return ProbeFileStamp(modified: modified, size: size)
        } catch {
            // Fichier absent : l'état normal sans la sonde.
            return nil
        }
    }
}

/// La carte décodée et le catalogue effectif qu'on en tire, gardés tant que
/// la date de modification et la taille du fichier ne changent pas : les vues
/// l'interrogent à chaque rendu, sans redécoder 838 Ko ni reparcourir 1 278
/// méthodes. Verrou explicite : le module Core compile en mode Swift 6.
public final class ProbeHarmonyMapCache: @unchecked Sendable {
    public static let shared = ProbeHarmonyMapCache(files: ProbeFiles())

    private let files: ProbeFiles
    private let base: [PerformanceOverlap]
    private let lock = NSLock()
    private var loaded = false
    private var stamp: ProbeFileStamp?
    private var map: ProbeHarmonyMap?
    private var catalog: [PerformanceOverlap]

    public init(files: ProbeFiles, base: [PerformanceOverlap] = PerformanceOverlap.catalog) {
        self.files = files
        self.base = base
        self.catalog = base
    }

    public func performanceCatalog() -> [PerformanceOverlap] {
        lock.withLock {
            refreshIfNeeded()
            return catalog
        }
    }

    public func harmonyMap() -> ProbeHarmonyMap? {
        lock.withLock {
            refreshIfNeeded()
            return map
        }
    }

    private func refreshIfNeeded() {
        let current = ProbeFileStamp.of(files.harmonyMapURL)
        if loaded && current == stamp { return }
        loaded = true
        stamp = current
        map = current == nil ? nil : files.harmonyMap()
        catalog = PerformanceOverlap.effectiveCatalog(base: base, map: map)
    }
}

/// La capture GMCM décodée (~3,5 Mo), gardée tant que le fichier ne change
/// pas : l'éditeur de config l'interroge à chaque ouverture. Décodage mesuré
/// à ~85 ms sur la capture du parc (170 mods, 3,4 Mo, build sans `-O` comme
/// l'app), plus ≤ 13 ms pour les options d'un mod : sous le seuil de 100 ms
/// de la spec D4-T7, donc fait au premier appel, sur le fil de l'appelant.
/// Verrou explicite : le module Core compile en mode Swift 6.
public final class GmcmCaptureCache: @unchecked Sendable {
    public static let shared = GmcmCaptureCache(files: ProbeFiles())

    private let files: ProbeFiles
    private let lock = NSLock()
    private var loaded = false
    private var stamp: ProbeFileStamp?
    private var current: GmcmCapture?

    public init(files: ProbeFiles) {
        self.files = files
    }

    public func capture() -> GmcmCapture? {
        lock.withLock {
            let latest = ProbeFileStamp.of(files.gmcmOptionsURL)
            if !loaded || latest != stamp {
                loaded = true
                stamp = latest
                current = latest == nil ? nil : files.gmcmCapture()
            }
            return current
        }
    }

    public func options(forMod uniqueId: String, installedVersion: String) -> GmcmModOptions? {
        capture()?.options(forMod: uniqueId, installedVersion: installedVersion)
    }
}
