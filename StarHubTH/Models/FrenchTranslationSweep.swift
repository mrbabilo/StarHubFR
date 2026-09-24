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

        /// Ce qu'on peut affirmer d'un résultat pour le mod `hostName`.
        public func confidence(of hit: NexusModSearch.Hit, hostName: String) -> Confidence {
            guard isLinked(hit) else { return .nameOnly }
            return FrenchTranslationSweep.titleNames(hit.name, host: hostName) ? .confirmed : .linkedOnly
        }
    }

    /// Mesuré sur l'API réelle le 2026-09-24 : pour SVE, le lien rend 8
    /// traductions françaises, dont **4 traduisent un autre mod** qui requiert
    /// lui aussi SVE (Spouses React, Xtardew, Aurora Vineyard, Rasmodius) —
    /// une traduction déclare en prérequis tout ce que son mod requiert. Le
    /// lien dit « de la famille », le titre dit « de ce mod-là » ; seuls les
    /// deux ensemble se passent de vérification.
    public enum Confidence: Equatable, Sendable {
        /// Liée, et son titre nomme le mod.
        case confirmed
        /// Liée, mais son titre ne nomme pas le mod : peut-être la traduction
        /// d'un mod qui en dépend.
        case linkedOnly
        /// Trouvée par ressemblance de nom seulement.
        case nameOnly
    }

    /// Le titre nomme-t-il le mod ? Tous les mots significatifs du nom (trois
    /// lettres et plus, préfixe de cadre retiré, accents repliés) se
    /// retrouvent dans le titre, dans n'importe quel ordre — « Maggs Townsfolk
    /// Daily Dialogue » pour « Maggs Daily Townsfolk Dialogue » ; ou le nom,
    /// collé, figure dans le titre collé — un nom de manifeste sans espaces.
    static func titleNames(_ title: String, host: String) -> Bool {
        let hostWords = NexusModSearch.words(in: NexusModSearch.searchTerm(for: host))
            .filter { $0.count >= 3 }
        let titleWords = NexusModSearch.words(in: title)
        if !hostWords.isEmpty, hostWords.isSubset(of: titleWords) { return true }
        let hostGlued = NexusModSearch.comparableTitle(host)
        return hostGlued.count >= 4 && NexusModSearch.comparableTitle(title).contains(hostGlued)
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
        /// Une traduction est posée, la recherche a abouti, sa fiche est
        /// connue, et rien de plus récent n'est sorti.
        case installed
        /// Une traduction est posée, mais rien ne permet de dire si elle est à
        /// jour : jamais cherché, recherche en échec, ou traduction sans fiche
        /// Nexus (courant sur un compte gratuit, où tout s'installe à la main).
        /// Ne pas le ranger sous « à jour » — ce serait un vert mensonger.
        case installedUnverified
    }

    public static func status(entry: Entry?, installed: InstalledTranslation?) -> Status {
        if let installed {
            // La moitié « déjà posée » des résultats est celle qui porte la
            // mise à jour (règle de `TranslationPresence.update`).
            guard let entry, !entry.failed, installed.nexusModId > 0 else {
                return .installedUnverified
            }
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

    /// Les mods pour lesquels une recherche a trouvé la fiche `modId` : quand
    /// l'archive d'une traduction arrive par un lien Nexus, son nom ne dit
    /// souvent rien (« Patch FR/fr.json » pour Jakk's Quinn), mais la page
    /// vient d'être proposée pour un mod précis. Trié, pour un ordre stable.
    ///
    /// `detailHits` : les résultats de la recherche lancée depuis la fiche d'un
    /// mod (`TranslationHubStore.hits`), même question posée ailleurs.
    public static func hosts(ofTranslation modId: Int, in entries: [String: Entry],
                             detailHits: [String: [NexusModSearch.Hit]] = [:],
                             installed: [String]? = nil) -> [String] {
        let fromSweep = entries.filter { $0.value.hits.contains { $0.modId == modId } }.map(\.key).sorted()
        let fromDetail = detailHits.filter { $0.value.contains { $0.modId == modId } }.map(\.key).sorted()
        var seen = Set<String>()
        return (fromSweep + fromDetail).filter {
            (installed?.contains($0) ?? true) && seen.insert($0).inserted
        }
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
