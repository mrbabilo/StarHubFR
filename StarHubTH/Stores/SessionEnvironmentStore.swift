import Foundation
import Observation

/// D2-T3 §4 — l'état environnement de la session du journal : config SLO
/// résolue, menus de config détectés, poids des packs Content Patcher,
/// conflits CP. Lit lui-même `SMAPI-latest.txt` (patron ProbePerformanceStore :
/// IO hors du fil principal, possédé par la vue, jamais par le ViewModel).
@MainActor
@Observable
final class SessionEnvironmentStore {
    enum Status: Equatable { case idle, loading, ready }

    private(set) var status: Status = .idle
    private(set) var report: SessionEnvironmentReport?

    @ObservationIgnored private let logURL: URL
    /// Empreinte du dernier journal lu (epoch entier : deux `Date` lues du
    /// disque ne se comparent pas en `==`, piège setAttributes).
    @ObservationIgnored private var lastStamp: Int?
    @ObservationIgnored private var lastModsRoot = ""
    @ObservationIgnored private var lastModsStamp: Int = 0

    init(logURL: URL = SessionEnvironmentStore.defaultLogURL()) {
        self.logURL = logURL
    }

    /// `~/.config/StardewValley/ErrorLogs/SMAPI-latest.txt` (VM:2019).
    /// `nonisolated` : sert de valeur par défaut d'`init` — évaluée hors
    /// acteur (mode Swift 6 du gate, un static hérite l'isolation sinon).
    nonisolated static func defaultLogURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/StardewValley/ErrorLogs/SMAPI-latest.txt")
    }

    func reload(mods: [ModItem], gameDir: String?) async {
        if status == .idle { status = .loading }
        let logURL = logURL
        let modsRoot = gameDir.map { ($0 as NSString).appendingPathComponent("Mods") }
        let modsRootPath = modsRoot ?? ""
        // Garde-fou coût (patron ProbeSessionsIndex : cache par date) : le
        // retour d'app et le changement d'onglet rechargent tous les deux —
        // 390 content.json relus à chaque fois, c'est trop. Journal inchangé
        // et même parc : le rapport tient toujours.
        let stamp = (try? logURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate.map { Int($0.timeIntervalSince1970) }
        // Empreinte du parc : un toggle ne change ni le journal ni la racine,
        // mais le rapport doit le suivre (pause = pack exclu, spec §3.1).
        let modsStamp = mods.map { "\($0.folderName):\($0.isEnabled)" }.hashValue
        if status == .ready, stamp == lastStamp, modsRootPath == lastModsRoot,
           modsStamp == lastModsStamp {
            return
        }
        let loaded = await Task.detached(priority: .userInitiated) { () -> SessionEnvironmentReport? in
            guard let text = try? String(contentsOf: logURL, encoding: .utf8),
                  !text.isEmpty else { return nil }
            let entries = SmapiLogParser.parse(text)
            let date = (try? logURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            return SessionEnvironmentReport(
                journalDate: date, diskReadAt: Date(),
                slo: SloOptimizerConfig.parse(log: text),
                menus: ConfigMenuCoverage.coverage(in: entries),
                groups: SessionEnvironmentStore.scanGroups(mods: mods, modsRoot: modsRootPath),
                conflicts: ContentPatcherConflicts.read(from: entries),
                stardropiumMemory: StardropiumMemoryReport.parse(text))
        }.value
        report = loaded
        lastStamp = stamp
        lastModsRoot = modsRootPath
        lastModsStamp = modsStamp
        status = .ready
    }

    /// D2-T3 §3.1 — parcours réutilisé de la découverte : racines et
    /// composants déjà connus de la liste des mods, pas de second balayage.
    /// Racines **actives** seulement (spec §3.1 : préfixé point = exclu) ;
    /// chemins physiques via `physicalFolderName` (AGENTS §4).
    /// `nonisolated` : IO pur sans état partagé — appelé depuis
    /// `Task.detached` dans `reload` (mode Swift 6 : un static hérite
    /// l'isolation @MainActor de la classe sinon).
    nonisolated static func scanGroups(mods: [ModItem], modsRoot: String) -> [ContentPatcherPacks.Group] {
        // Racines actives seulement (spec §3.1 : dossiers préfixés point exclus).
        mods.filter { !$0.isPackComponent && $0.isEnabled }.compactMap { root in
            let dirs = ContentPatcherPacks.packDirectories(of: root, modsRoot: modsRoot)
            guard !dirs.isEmpty else { return nil }
            return ContentPatcherPacks.Group(rootName: root.name, packs: dirs.map(ContentPatcherPacks.read))
        }
    }
}

/// Ce que la carte affiche. `journalDate` distingue le moment du journal de
/// celui du scan disque (spec §7 : les deux s'affichent tels quels).
public struct SessionEnvironmentReport: Equatable, Sendable {
    public let journalDate: Date?
    public var diskReadAt: Date? = nil
    public let slo: SloOptimizerConfig?
    public let menus: [ConfigMenuEntry]
    public let groups: [ContentPatcherPacks.Group]
    public let conflicts: [LoadConflict]
    public var stardropiumMemory: StardropiumMemoryReport = .init()

    public var totalPatches: Int { groups.reduce(0) { $0 + $1.totalPatches } }
    public var totalPacks: Int { groups.reduce(0) { $0 + $1.packs.count } }
    public var unreadablePacks: [String] {
        groups.flatMap(\.packs).filter { $0.state == .illisible }.map(\.packName)
    }
    /// Packs lus dont une partie des inclusions n'a pu être comptée : leur
    /// total est un plancher, la carte dit de combien de fichiers.
    public var packsWithUnreadIncludes: [ContentPatcherPackCount] {
        groups.flatMap(\.packs).filter { $0.state == .ok && $0.includesUnread > 0 }
    }
}
