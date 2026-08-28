import Foundation

/// Le cache de l'onglet « Découvrir » : ce que chaque section a rendu, quand,
/// et combien de temps ça vaut encore (spec §6).
///
/// Type pur : lire et écrire des fichiers est injecté — tout le comportement
/// se teste sans disque. Une entrée corrompue se lit comme « jamais chargé » :
/// un cache ne mérite jamais une erreur surfaced.
public struct ModCatalog {
    public enum SectionKind: String, CaseIterable, Codable, Sendable {
        case trending, recent, french

        /// Le tri de la requête qui alimente cette section (spec §5.1).
        public var defaultSort: NexusModSearch.ListingSort {
            switch self {
            case .trending: return .endorsed
            case .recent, .french: return .recentlyUpdated
            }
        }

        /// Le filtre de tag de la section — la sélection FR seule en porte un.
        public var defaultTag: String? {
            self == .french ? NexusModSearch.frenchTag : nil
        }
    }

    public enum EmptyReason: Equatable, Sendable {
        /// Jamais chargé — première ouverture, cache absent ou corrompu.
        case neverLoaded
        /// La dernière tentative a échoué ; le message est fabriqué par la vue.
        case failed
    }

    public enum SectionState: Equatable, Sendable {
        case fresh(NexusModSearch.Page)
        /// Périmée mais affichée pendant le rechargement — jamais un spinner
        /// sur page blanche (spec §6).
        case stale(NexusModSearch.Page)
        case empty(EmptyReason)

        /// Le contenu à montrer, quel que soit l'âge.
        public var page: NexusModSearch.Page? {
            switch self {
            case .fresh(let page), .stale(let page): return page
            case .empty: return nil
            }
        }
    }

    /// Durée de vie d'une section et d'une fiche : 24 h (spec §6).
    public static let freshness: TimeInterval = 24 * 3600

    private let load: (String) -> Data?
    private let save: (String, Data) -> Void
    private let now: () -> Date

    public init(load: @escaping (String) -> Data?,
                save: @escaping (String, Data) -> Void,
                now: @escaping () -> Date = Date.init) {
        self.load = load; self.save = save; self.now = now
    }

    private struct Entry: Codable {
        let savedAt: Date
        let page: NexusModSearch.Page
    }

    private struct DetailEntry: Codable {
        let savedAt: Date
        let detail: NexusModSearch.Detail
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// La clé de cache d'une section **et de son filtre de catégorie** : les
    /// tendances de « Portraits » ne sont pas les tendances tout court. Sans
    /// cette distinction, revenir à « toutes les catégories » resservirait la
    /// liste filtrée pendant 24 h. Le cas sans filtre garde sa clé d'origine —
    /// les fichiers déjà écrits restent lisibles.
    private func sectionKey(_ kind: SectionKind, _ category: Int?) -> String {
        guard let category else { return "section.\(kind.rawValue)" }
        return "section.\(kind.rawValue).cat\(category)"
    }
    private func detailKey(_ modId: Int) -> String { "detail.\(modId)" }

    /// L'état d'une section : ce qu'on a, et s'il vaut encore.
    public func state(_ kind: SectionKind, category: Int? = nil) -> SectionState {
        guard let data = load(sectionKey(kind, category)),
              let entry = try? Self.decoder.decode(Entry.self, from: data)
        else { return .empty(.neverLoaded) }
        let age = now().timeIntervalSince(entry.savedAt)
        return age <= Self.freshness ? .fresh(entry.page) : .stale(entry.page)
    }

    /// Retient une page en dédoublonnant par `modId` : une requête ne doit
    /// jamais rendre deux fois le même mod dans une même bande (spec §6).
    /// Réapparaître dans une **autre** section est normal : elles ne lisent
    /// pas les mêmes fichiers.
    public func record(_ kind: SectionKind, category: Int? = nil,
                       page: NexusModSearch.Page) {
        var seen = Set<Int>()
        let deduped = NexusModSearch.Page(
            hits: page.hits.filter { seen.insert($0.modId).inserted },
            totalCount: page.totalCount)
        guard let data = try? Self.encoder.encode(Entry(savedAt: now(), page: deduped))
        else { return }
        save(sectionKey(kind, category), data)
    }

    /// La fiche cachée, tant qu'elle a moins de 24 h.
    public func detail(for modId: Int) -> NexusModSearch.Detail? {
        guard let data = load(detailKey(modId)),
              let entry = try? Self.decoder.decode(DetailEntry.self, from: data),
              now().timeIntervalSince(entry.savedAt) <= Self.freshness
        else { return nil }
        return entry.detail
    }

    public func recordDetail(_ detail: NexusModSearch.Detail) {
        guard let data = try? Self.encoder.encode(DetailEntry(savedAt: now(), detail: detail))
        else { return }
        save(detailKey(detail.modId), data)
    }
}
