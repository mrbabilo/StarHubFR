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

    public func harmonyMap() -> ProbeHarmonyMap? {
        contents("harmony-map.json").flatMap(ProbeHarmonyMap.decode)
    }

    public func sessions() -> ProbeSessions {
        ProbeSessions.decode(timings: contents("timings.jsonl"), costs: contents("mod-costs.jsonl"))
    }

    private func contents(_ name: String) -> Data? {
        FileManager.default.contents(atPath: directory.appendingPathComponent(name).path)
    }
}

/// La carte décodée et le catalogue effectif qu'on en tire, gardés tant que
/// la date de modification et la taille du fichier ne changent pas : les vues
/// l'interrogent à chaque rendu, sans redécoder 838 Ko ni reparcourir 1 278
/// méthodes. Verrou explicite : le module Core compile en mode Swift 6.
public final class ProbeHarmonyMapCache: @unchecked Sendable {
    public static let shared = ProbeHarmonyMapCache(files: ProbeFiles())

    private struct Stamp: Equatable {
        let modified: Date
        let size: Int
    }

    private let files: ProbeFiles
    private let base: [PerformanceOverlap]
    private let lock = NSLock()
    private var loaded = false
    private var stamp: Stamp?
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
        let current = Self.stamp(of: files.harmonyMapURL)
        if loaded && current == stamp { return }
        loaded = true
        stamp = current
        map = current == nil ? nil : files.harmonyMap()
        catalog = PerformanceOverlap.effectiveCatalog(base: base, map: map)
    }

    private static func stamp(of url: URL) -> Stamp? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let modified = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? Int else { return nil }
            return Stamp(modified: modified, size: size)
        } catch {
            // Fichier absent : l'état normal sans la sonde.
            return nil
        }
    }
}
