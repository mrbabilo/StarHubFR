import Foundation

/// C5-T1 — la vue d'ensemble des traductions françaises : ce qu'une recherche
/// sur tout le parc a trouvé, et ce qu'on en dit à l'écran.
///
/// **On garde l'observation brute, jamais le verdict.** Une entrée dit ce que
/// Nexus a répondu, et quand ; le statut se dérive à l'affichage de l'état
/// vivant (registre des traductions posées, `TranslationPresence.update`).
/// Installer depuis la vue change ce statut sans relancer de recherche — un
/// statut figé au moment de la recherche proposerait encore ce qui vient
/// d'être posé.
public enum FrenchTranslationSweep {

    /// Ce que la dernière recherche a rapporté pour un mod.
    ///
    /// Deux sources, réunies : le **lien** « requis par » (une déclaration de
    /// l'auteur de la traduction — 10 justes sur 10 mesurés) et la **recherche
    /// par nom** (une ressemblance — 4 fausses sur 11). Le lien seul ne suffit
    /// pas : sur SVE, 2 des 5 traductions françaises de la page Nexus ne
    /// déclarent pas le prérequis. La vue marque ce qui ne vient que du nom.
    public struct Entry: Codable, Equatable, Sendable {
        public let hits: [NexusModSearch.Hit]
        /// Les résultats venus du lien ; les autres ne viennent que du nom.
        public let linkedModIds: Set<Int>
        public let searchedAt: Date
        /// Une panne n'est pas une absence : `failed` avec `hits` vide ne veut
        /// **pas** dire « aucune traduction », et la vue ne le dira pas.
        public let failed: Bool

        public init(hits: [NexusModSearch.Hit], linkedModIds: Set<Int> = [],
                    searchedAt: Date, failed: Bool = false) {
            self.hits = hits; self.linkedModIds = linkedModIds
            self.searchedAt = searchedAt; self.failed = failed
        }

        public func isLinked(_ hit: NexusModSearch.Hit) -> Bool {
            linkedModIds.contains(hit.modId)
        }
    }

    /// Réunit les deux sources : le lien d'abord (le plus sûr), puis ce que le
    /// nom ajoute, sans doublon. Chaque moitié garde son ordre.
    public static func merge(linked: [NexusModSearch.Hit], byName: [NexusModSearch.Hit],
                             at date: Date) -> Entry {
        let linkedIds = Set(linked.map(\.modId))
        return Entry(hits: linked + byName.filter { !linkedIds.contains($0.modId) },
                     linkedModIds: linkedIds, searchedAt: date)
    }

    /// Un mod que la recherche doit couvrir.
    public struct Candidate: Identifiable, Equatable, Sendable {
        public let folderName: String
        public let name: String
        public let isActive: Bool
        /// `nil` quand le mod ne déclare pas de fiche Nexus : seule la
        /// recherche par nom est alors possible.
        public let nexusModId: Int?
        public var id: String { folderName }

        public init(folderName: String, name: String, isActive: Bool, nexusModId: Int?) {
            self.folderName = folderName; self.name = name
            self.isActive = isActive; self.nexusModId = nexusModId
        }
    }

    /// Les mods à couvrir : les mods **de premier niveau** — c'est là qu'une
    /// traduction se dépose, comme sur la fiche (A3-T3) — traduisibles sans
    /// français (le cadrage `.missing` de la liste, une seule règle : un pack
    /// y entre dès qu'un composant est traduisible sans français), plus ceux
    /// qui portent une traduction posée par l'app, dont on suit les mises à
    /// jour. Mods en pause compris (choix de l'utilisateur, 2026-09-24) :
    /// savoir qu'une traduction existe sert avant la réactivation.
    public static func candidates(among topLevel: [ModItem],
                                  hasInstalledTranslation: (ModItem) -> Bool,
                                  nexusModId: (ModItem) -> Int?) -> [Candidate] {
        let none = ModListScoping.TranslationState(coverage: [:], stale: [], outdatedKeys: [:])
        return topLevel
            .filter { ModListScoping.matchesTranslation($0, .missing, state: none)
                        || hasInstalledTranslation($0) }
            .map { Candidate(folderName: $0.folderName, name: $0.name, isActive: $0.isEnabled,
                             nexusModId: nexusModId($0).flatMap { $0 > 0 ? $0 : nil }) }
            .sorted { ($0.name.localizedLowercase, $0.folderName)
                    < ($1.name.localizedLowercase, $1.folderName) }
    }

    /// Ce qu'on dit d'un mod.
    public enum Status: Equatable, Sendable {
        case notSearched
        case failed
        case nothingFound
        /// Des traductions existent, aucune n'est posée.
        case available([NexusModSearch.Hit])
        /// Une traduction est posée et Nexus en a une version plus récente.
        case updateAvailable(NexusModSearch.Hit)
        /// Une traduction est posée, rien de plus récent n'est connu.
        case installed
    }

    public static func status(entry: Entry?, installed: InstalledTranslation?) -> Status {
        if let installed {
            // La moitié « déjà posée » des résultats est celle qui porte la
            // mise à jour (règle de `TranslationPresence.update`).
            guard let entry, !entry.failed else { return .installed }
            let split = NexusModSearch.partition(
                entry.hits,
                installedNexusIds: installed.nexusModId > 0 ? [installed.nexusModId] : [],
                installedTitles: [installed.nexusName])
            if let newer = TranslationPresence.update(for: installed,
                                                      amongAvailable: split.available,
                                                      andInstalled: split.installed) {
                return .updateAvailable(newer)
            }
            return .installed
        }
        guard let entry else { return .notSearched }
        if entry.failed { return .failed }
        return entry.hits.isEmpty ? .nothingFound : .available(entry.hits)
    }

    // MARK: - Disque

    /// Un cache re-calculable (un clic le refait), pas une trace unique comme le
    /// registre des traductions : un fichier illisible repart vide, sans
    /// `.bak`. On encode un type à nous — il n'y a pas d'octets étrangers à
    /// décoder avant d'écrire.
    public enum Storage {
        static var fileURL: URL? {
            AppSupport.directory?.appendingPathComponent("french_translation_sweep.json")
        }

        public static func load(from url: URL? = nil) -> [String: Entry] {
            guard let target = url ?? fileURL,
                  let data = try? Data(contentsOf: target) else { return [:] }
            return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
        }

        @discardableResult
        public static func save(_ entries: [String: Entry], to url: URL? = nil) -> Bool {
            guard let target = url ?? fileURL,
                  let data = try? JSONEncoder().encode(entries) else { return false }
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
                return true
            } catch {
                return false
            }
        }
    }
}
