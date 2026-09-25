import Foundation

/// Chercher un mod sur Nexus **par son nom**, via l'API GraphQL v2
/// (`POST /v2/graphql`, vérifiée le 2026-08-25) : la v1 ne sait pas
/// (`/mods/search.json` rend 422). **Non documentée** : traitée comme
/// instable, on dit « pas pu chercher » plutôt qu'une réponse fausse.
/// Type pur, sans réseau.
public enum NexusModSearch {
    /// Ce que rend une recherche.
    public struct Hit: Equatable, Identifiable, Sendable, Codable {
        public var id: Int { modId }
        public let modId: Int
        public let name: String
        public let version: String
        public let updatedAt: Date?
        public let categoryName: String
        public let uploader: String
        public let adultContent: Bool
        /// Tags Nexus : seul signal séparant supplément et traduction (« Wildflour » :
        /// 6 traductions toutes `Translation`, 2 suppléments sans). Le titre ne dit
        /// rien.
        public let tags: [String]
        /// Endossements ; NON_NULL au schéma (2026-08-27), mais absent ≠ zéro.
        public let endorsements: Int?
        /// Résumé d'une ligne, servi par les listings (2026-08-27).
        public let summary: String?
        /// Vignette, servie par listings et recherche ; optionnelle.
        public let thumbnailUrl: String?
        /// Id de catégorie `NexusCategory` (3 = Gameplay Mechanics, 25 = Visuals,
        /// 2026-08-28) : rebranche la carte sur la table traduite et colorée.
        /// Optionnel (pages en cache plus anciennes).
        public let categoryId: Int?

        public init(modId: Int, name: String, version: String, updatedAt: Date?,
                    categoryName: String, uploader: String, adultContent: Bool,
                    tags: [String] = [], endorsements: Int? = nil,
                    summary: String? = nil, thumbnailUrl: String? = nil,
                    categoryId: Int? = nil) {
            self.modId = modId
            self.name = name
            self.version = version
            self.updatedAt = updatedAt
            self.categoryName = categoryName
            self.uploader = uploader
            self.adultContent = adultContent
            self.tags = tags
            self.endorsements = endorsements
            self.summary = summary
            self.thumbnailUrl = thumbnailUrl
            self.categoryId = categoryId
        }

        /// `true` quand Nexus range ce mod parmi les traductions.
        public var isTranslation: Bool {
            tags.contains { $0.caseInsensitiveCompare(NexusModSearch.translationTag) == .orderedSame }
        }
    }

    /// Page de résultats **et total** : « Content Patcher » rend 428
    /// résultats ; taire le total ferait croire que la poignée affichée est
    /// tout. `Sendable` explicite (porté par `SectionState`).
    public struct Page: Equatable, Codable, Sendable {
        public let hits: [Hit]
        public let totalCount: Int

        public init(hits: [Hit], totalCount: Int) {
            self.hits = hits
            self.totalCount = totalCount
        }
    }

    public enum Failure: Error, Equatable {
        /// Erreurs GraphQL (schéma, filtre, droits). **Un 200 ne suffit pas** :
        /// `errors` pris pour vide dirait « aucune traduction trouvée ».
        case service(String)
        /// Réponse illisible : ce n'est pas du JSON, ou pas la forme attendue.
        case malformed
    }

    // MARK: - Requête

    /// Tag des traductions françaises : 77/80 le portent, et le serveur trie
    /// (« Parchment » : nom + tag = la bonne, nom seul = douze).
    /// ⚠️ **Pas une catégorie** : les traductions FR se répartissent sur
    /// treize des 27 catégories (celle du mod traduit).
    public static let frenchTag = "French"

    /// Tag de **toute** traduction (80/80 contre 77 pour `French`) : c'est
    /// lui qui écarte les traductions d'une recherche de suppléments (« Sword
    /// and Sorcery » : 8 des 26 premiers).
    public static let translationTag = "Translation"

    /// Corps JSON de la recherche par nom.
    /// - Parameters:
    ///   - name: nom du mod installé, réduit par `searchTerm(for:)` ; vide
    ///     après réduction → `nil`.
    ///   - gameId: id **numérique** : `gameDomainName` seul rend
    ///     `totalCount: 0` sans erreur (faux négatif silencieux).
    ///   - tag: tag exigé (`frenchTag`) ; absent, hors requête (vide = 0 muet).
    ///   - category: filtrée **au serveur** (total et tranche cohérents).
    ///   - count: nombre de résultats (défaut avec marge).
    ///   - offset: rang du premier résultat.
    public static func queryBody(name: String, gameId: Int, tag: String? = nil,
                                 category: String? = nil,
                                 count: Int = 30, offset: Int = 0) -> Data? {
        let term = searchTerm(for: name)
        guard !term.isEmpty else { return nil }
        // Tag seulement s'il est demandé (vide = `totalCount: 0` sans erreur).
        let tagFilter = tag.map { _ in ", tag: { value: $tag, op: EQUALS }" } ?? ""
        let tagParam = tag.map { _ in ", $tag: String!" } ?? ""
        // Catégorie filtrée au serveur, cohérente avec le total.
        let catFilter = category.map { _ in
            ", categoryName: { value: $category, op: EQUALS }"
        } ?? ""
        let catParam = category.map { _ in ", $category: String!" } ?? ""
        let query = """
        query ModsByName($name: String!, $game: String!, $count: Int!, \
        $offset: Int!\(tagParam)\(catParam)) {
          mods(
            filter: { name: { value: $name, op: WILDCARD },
                      gameId: { value: $game, op: EQUALS }\(tagFilter)\(catFilter) }
            sort: { updatedAt: { direction: DESC } }
            count: $count
            offset: $offset
          ) {
            totalCount
            nodes { modId name version updatedAt adultContent status thumbnailUrl
                    modCategory { categoryId name } uploader { name } tags { name } }
          }
        }
        """
        var variables: [String: Any] = ["name": term, "game": String(gameId),
                                        "count": count, "offset": offset]
        if let tag { variables["tag"] = tag }
        if let category { variables["category"] = category }
        return try? JSONSerialization.data(withJSONObject: ["query": query,
                                                            "variables": variables])
    }

    /// Terme envoyé : sans accents, sans préfixe de convention.
    /// **L'index ignore les accents** : « Français » 0, « Francais » 184.
    /// **Et les préfixes de cadre** (`[CP]`, `[FTM]`, `[AT]`, `[JA]`…,
    /// convention de dossier, cf. `docs/DOMAINE.md`) : la recherche par
    /// sous-chaîne échoue en silence (2026-08-25 : `[CP] Make Gunther Real`
    /// 0 → 9, `[FTM] Wildflour's Atelier Goods` 0 → 12). 148/995 manifestes
    /// du parc en portent un.
    public static func searchTerm(for name: String) -> String {
        let stripped = stripConventionPrefixes(name)
        return stripped.folding(options: [.diacriticInsensitive],
                                locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Retire les préfixes `[…]`/`(…)` de **tête**, courts seulement.
    /// **Jamais le vide** : un nom tout en crochets est cherché tel quel.
    static func stripConventionPrefixes(_ name: String) -> String {
        var remainder = Substring(name).drop { $0.isWhitespace }
        while let opening = remainder.first, opening == "[" || opening == "(",
              let close = remainder.firstIndex(of: opening == "[" ? "]" : ")") {
            let inside = remainder[remainder.index(after: remainder.startIndex)..<close]
            guard !inside.isEmpty, inside.count <= 12 else { break }
            let rest = remainder[remainder.index(after: close)...].drop { $0.isWhitespace }
            guard !rest.isEmpty else { break }
            remainder = rest
        }
        return String(remainder)
    }

    // MARK: - Listing (vitrine « Découvrir », axe G)

    /// Tris de vitrine, noms du type `ModsSort` (introspection 2026-08-27 ;
    /// pas d'`endorsed`/`endorsementCount`).
    public enum ListingSort: String, CaseIterable, Sendable {
        case endorsed, recentlyUpdated, newest

        public var graphQLField: String {
            switch self {
            case .endorsed: return "endorsements"
            case .recentlyUpdated: return "updatedAt"
            case .newest: return "createdAt"
            }
        }
    }

    /// Corps JSON d'un **listing** (tri, sans nom) : jeu entier 33 199 mods,
    /// tag `French` 747 (2026-08-27).
    /// - Parameter offset: rang du premier mod, pour « voir plus ».
    public static func listingBody(sort: ListingSort, tag: String? = nil,
                                   category: String? = nil,
                                   gameId: Int, count: Int = 20,
                                   offset: Int = 0) -> Data? {
        let tagFilter = tag.map { _ in ", tag: { value: $tag, op: EQUALS }" } ?? ""
        let tagParam = tag.map { _ in ", $tag: String!" } ?? ""
        // `categoryName` de `ModsFilter` (2026-08-28) : filtré **au serveur**
        // (50 mods de tendances couvrent 15 catégories).
        let catFilter = category.map { _ in
            ", categoryName: { value: $category, op: EQUALS }"
        } ?? ""
        let catParam = category.map { _ in ", $category: String!" } ?? ""
        let query = """
        query ModListing($game: String!, $count: Int!, $offset: Int!\(tagParam)\(catParam)) {
          mods(
            filter: { gameId: { value: $game, op: EQUALS }\(tagFilter)\(catFilter) }
            sort: { \(sort.graphQLField): { direction: DESC } }
            count: $count
            offset: $offset
          ) {
            totalCount
            nodes { modId name version updatedAt adultContent status endorsements
                    summary thumbnailUrl modCategory { categoryId name }
                    uploader { name } tags { name } }
          }
        }
        """
        var variables: [String: Any] = ["game": String(gameId), "count": count,
                                        "offset": offset]
        if let tag { variables["tag"] = tag }
        if let category { variables["category"] = category }
        return try? JSONSerialization.data(withJSONObject: ["query": query,
                                                            "variables": variables])
    }

    // MARK: - Fiche (Detail, vitrine « Découvrir »)

    /// La fiche d'un mod pour la vitrine : ce que la carte ne dit pas.
    public struct Detail: Equatable, Sendable, Codable {
        public let modId: Int
        public let name: String
        public let summary: String?
        /// Le corps descriptif, brut — le rendu (liens, BBCodes) est à la vue.
        public let descriptionText: String?
        public let endorsements: Int?
        public let version: String
        public let updatedAt: Date?
        public let tags: [String]
        /// Image principale (`pictureUrl`, seule garantie) ; peut être vide.
        public let pictureUrls: [String]
        /// L'auteur Nexus, quand la réponse le porte.
        public let uploaderName: String?

        public init(modId: Int, name: String, summary: String?, descriptionText: String?,
                    endorsements: Int?, version: String, updatedAt: Date?,
                    tags: [String], pictureUrls: [String], uploaderName: String?) {
            self.modId = modId; self.name = name; self.summary = summary
            self.descriptionText = descriptionText; self.endorsements = endorsements
            self.version = version; self.updatedAt = updatedAt
            self.tags = tags; self.pictureUrls = pictureUrls
            self.uploaderName = uploaderName
        }
    }

    /// Fiche d'un mod par id ; champs optionnels : fiche dégradée plutôt
    /// qu'erreur.
    public static func detailBody(modId: Int, gameId: Int) -> Data? {
        let query = """
        query ModDetail($game: String!, $id: String!) {
          mods(filter: { gameId: { value: $game, op: EQUALS },
                         modId: { value: $id, op: EQUALS } }, count: 1) {
            nodes { modId name version updatedAt status endorsements
                    description summary pictureUrl
                    modCategory { name } uploader { name } tags { name } }
          }
        }
        """
        let variables: [String: Any] = ["game": String(gameId), "id": String(modId)]
        return try? JSONSerialization.data(withJSONObject: ["query": query,
                                                            "variables": variables])
    }

    /// Lit une fiche : `errors` l'emporte ; image ou description absente
    /// tolérée.
    public static func decodeDetail(_ data: Data) -> Result<Detail, Failure> {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.malformed)
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let message = errors.compactMap { $0["message"] as? String }.joined(separator: " · ")
            return .failure(.service(message.isEmpty ? "unknown" : message))
        }
        guard let node = ((root["data"] as? [String: Any])?["mods"] as? [String: Any])?["nodes"]
                as? [[String: Any]], let first = node.first,
              let modId: Int = (first["modId"] as? Int) ?? (first["modId"] as? String).flatMap(Int.init),
              let name = first["name"] as? String
        else { return .failure(.malformed) }
        var pictures: [String] = []
        if let url = first["pictureUrl"] as? String, !url.isEmpty { pictures.append(url) }
        return .success(Detail(
            modId: modId,
            name: name,
            summary: first["summary"] as? String,
            descriptionText: first["description"] as? String,
            endorsements: first["endorsements"] as? Int,
            version: first["version"] as? String ?? "",
            updatedAt: (first["updatedAt"] as? String).flatMap(parseDate),
            tags: (first["tags"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? [],
            pictureUrls: pictures,
            uploaderName: (first["uploader"] as? [String: Any])?["name"] as? String))
    }

    // MARK: - Réponse

    /// Lit une réponse GraphQL : `errors` l'emporte (partielle = panne).
    public static func decode(_ data: Data) -> Result<Page, Failure> {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.malformed)
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let message = errors.compactMap { $0["message"] as? String }.joined(separator: " · ")
            return .failure(.service(message.isEmpty ? "unknown" : message))
        }
        guard let payload = root["data"] as? [String: Any],
              let mods = payload["mods"] as? [String: Any],
              let nodes = mods["nodes"] as? [[String: Any]]
        else { return .failure(.malformed) }

        // `totalCount` absent ≠ zéro : repli sur ce qu'on a reçu.
        let total = (mods["totalCount"] as? Int) ?? nodes.count
        return .success(Page(hits: nodes.compactMap(hit(from:)), totalCount: total))
    }

    private static func hit(from node: [String: Any]) -> Hit? {
        // `modId` en nombre ou en chaîne, les deux acceptés.
        let modId: Int?
        if let value = node["modId"] as? Int { modId = value }
        else if let value = node["modId"] as? String { modId = Int(value) }
        else { modId = nil }
        guard let modId, let name = node["name"] as? String else { return nil }

        // Mods publiés seulement.
        if let status = node["status"] as? String, status != "published" { return nil }

        let categoryNode = node["modCategory"] as? [String: Any]
        let category = categoryNode?["name"] as? String ?? ""
        let uploader = (node["uploader"] as? [String: Any])?["name"] as? String ?? ""
        let tags = (node["tags"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        return Hit(modId: modId,
                   name: name,
                   version: node["version"] as? String ?? "",
                   updatedAt: (node["updatedAt"] as? String).flatMap(parseDate),
                   categoryName: category,
                   uploader: uploader,
                   adultContent: node["adultContent"] as? Bool ?? false,
                   tags: tags,
                   endorsements: node["endorsements"] as? Int,
                   summary: node["summary"] as? String,
                   thumbnailUrl: node["thumbnailUrl"] as? String,
                   categoryId: categoryNode?["categoryId"] as? Int)
    }

    // MARK: - Reconnaître une traduction française

    /// Marqueurs d'une traduction **française** dans un titre (« Francais »,
    /// « FR », « VF », « French Translation »…), accents repliés.
    private static let frenchMarkers: Set<String> = [
        "fr", "fra", "vf", "francais", "francaise", "french", "frenchie",
        "traduction", "traduit", "traduite", "francophone",
    ]

    /// Marqueurs **d'une autre langue** (X79) : « Traduction espagnole de X »
    /// matche « traduction ». **Variantes longues seulement** : les codes ISO
    /// (`de`, `en`…) sont aussi des mots français.
    private static let nonFrenchLanguageMarkers: Set<String> = [
        "espagnol", "espagnole", "allemand", "allemande",
        "italien", "italienne", "portugais", "portugaise",
        "anglais", "anglaise", "english", "japonais", "japonaise",
        "coreen", "coreenne", "chinois", "chinoise", "russe",
        "polonais", "polonaise", "hongrois", "hongroise", "turc", "turque",
        "arabe", "neerlandais", "neerlandaise", "suedois", "suedoise",
        "norvegien", "norvegienne", "danois", "danoise", "finnois",
        "finlandaise", "grec", "grecque", "tcheque", "ukrainien",
        "ukrainienne",
    ]

    /// `true` si le titre annonce une traduction française. **Filet** : le tag
    /// `French` prime (3/80 ne l'ont pas). **Mots entiers** (« FR » en
    /// sous-chaîne : 1 559 mods). X79 : marqueur d'une autre langue = retiré.
    public static func announcesFrenchTranslation(_ title: String) -> Bool {
        let words = words(in: title)
        let hasFrench = !words.isDisjoint(with: frenchMarkers)
        guard hasFrench else { return false }
        // Une autre langue annule le match (« fr » exclu des marqueurs
        // non-français, tranché pour le français).
        return words.isDisjoint(with: nonFrenchLanguageMarkers)
    }

    /// Mots comparables : accents repliés, minuscules, césure hors lettres et
    /// chiffres (« PT-BR » → pt, br).
    static func words(in title: String) -> Set<String> {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
        return Set(folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty })
    }

    /// Traductions FR parmi des résultats **non filtrés**, récentes d'abord.
    /// Sur un résultat déjà tagué `French`, utiliser `ranked(_:excluding:)`.
    public static func frenchTranslations(among hits: [Hit],
                                          excluding hostModId: Int? = nil) -> [Hit] {
        hits.filter { announcesFrenchTranslation($0.name) && $0.modId != hostModId }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    /// Résultats **déjà tagués `French`**, plus probables d'abord. **Le titre
    /// classe, ne filtre pas** (77/80 portent le tag). Mod hôte écarté.
    public static func ranked(_ hits: [Hit], excluding hostModId: Int? = nil) -> [Hit] {
        hits.filter { $0.modId != hostModId }
            .sorted {
                let left = announcesFrenchTranslation($0.name)
                let right = announcesFrenchTranslation($1.name)
                if left != right { return left }
                return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
    }

    /// Vitrine francophone : non-traduction toujours, traduction seulement
    /// **française**. Coût : ~1 traduction FR sur 20 écartée à tort (tag
    /// 77/80) ; le compte « x sur y » le signale. Vitrine seulement.
    public static func vitrineEligible(_ hit: Hit) -> Bool {
        guard hit.isTranslation else { return true }
        return hit.tags.contains {
            $0.caseInsensitiveCompare(frenchTag) == .orderedSame
        }
    }

    // MARK: - Reconnaître un supplément

    /// **Suppléments** d'un mod : `WILDCARD` cherche une sous-chaîne du titre,
    /// mais les résultats sont **noyés de traductions** (« Automate » : 21/43).
    /// Deux retraits : **tag `Translation`** (seul signal), et **l'hôte**.
    /// Le reste n'est **pas certain** (« Content Patcher » : 428 résultats) :
    /// l'appelant plafonne **et dit le total**.
    /// - Parameters:
    ///   - hostModId: id Nexus du mod, s'il en déclare un.
    ///   - hostName: **repli qui compte** (111 mods sans id) : sinon le mod
    ///     figure en tête de ses propres suppléments.
    public static func supplements(among hits: [Hit], excluding hostModId: Int? = nil,
                                   hostName: String = "") -> [Hit] {
        let host = comparableTitle(hostName)
        return hits
            .filter { hit in
                guard !hit.isTranslation, hit.modId != hostModId else { return false }
                // Titre **réduit** (préfixe, ponctuation, casse). **Égalité, pas
                // préfixe** : « Hôte – Ajout » est la forme d'un vrai supplément (59
                // mods au parc, 2026-09-03). Reste : hôte sans id à sous-titre Nexus.
                return !host.isEmpty ? comparableTitle(hit.name) != host : true
            }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    /// Candidat à l'identité d'un mod, et accord de l'auteur.
    public struct IdentityCandidate: Equatable, Identifiable, Sendable {
        public var id: Int { hit.modId }
        public let hit: Hit
        /// Auteur du manifeste = pseudo Nexus. **Indice, jamais filtre**.
        public let authorMatches: Bool

        public init(hit: Hit, authorMatches: Bool) {
            self.hit = hit
            self.authorMatches = authorMatches
        }
    }

    /// Fiches Nexus possibles pour un mod sans id, plus probable d'abord.
    /// Mesuré sur 83 mods sans id (2026-08-26) : **55 ne rendent rien** (dont
    /// 20 composants de pack) ; **61 % des candidats sont des traductions**,
    /// écartées par le tag `Translation` ; ensuite 18 mods à candidat unique.
    /// **L'auteur ordonne, ne tranche pas** (12/18 concordent ; `Owljoy` /
    /// `OwlandJoy`). **Proposition** seulement : l'utilisateur désigne.
    public static func identityCandidates(among hits: [Hit],
                                          modName: String,
                                          modAuthor: String) -> [IdentityCandidate] {
        let wanted = comparableTitle(modName)
        return hits
            .filter { !$0.isTranslation && namesMatch(modName, $0.name) }
            .map { IdentityCandidate(hit: $0, authorMatches: authorsMatch(modAuthor, $0.uploader)) }
            .sorted { lhs, rhs in
                if lhs.authorMatches != rhs.authorMatches { return lhs.authorMatches }
                let lhsExact = comparableTitle(lhs.hit.name) == wanted
                let rhsExact = comparableTitle(rhs.hit.name) == wanted
                if lhsExact != rhsExact { return lhsExact }
                return (lhs.hit.updatedAt ?? .distantPast) > (rhs.hit.updatedAt ?? .distantPast)
            }
    }

    /// Même personne ? Préfixe dans les deux sens, plancher de 4 (`kurts` /
    /// `kurtsietz`) ; plusieurs auteurs déclarés, chacun essayé. `false` =
    /// absence d'indice.
    static func authorsMatch(_ declared: String, _ uploader: String) -> Bool {
        let right = comparableTitle(uploader)
        guard right.count >= 4 else { return false }
        let parts = declared.split(whereSeparator: { ",/;&+".contains($0) })
        for part in parts + [Substring(declared)] {
            for word in part.split(separator: " ") where word.lowercased() != "and" {
                let left = comparableTitle(String(word))
                guard left.count >= 4 else { continue }
                if left.hasPrefix(right) || right.hasPrefix(left) { return true }
            }
            let whole = comparableTitle(String(part))
            guard whole.count >= 4 else { continue }
            if whole.hasPrefix(right) || right.hasPrefix(whole) { return true }
        }
        return false
    }

    /// Titre réduit : préfixe retiré, accents repliés, ponctuation et casse.
    static func comparableTitle(_ name: String) -> String {
        stripConventionPrefixes(name)
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Résultats séparés : déjà en place / à découvrir.
    public struct Partition: Equatable {
        /// Ce que le parc porte déjà.
        public let installed: [Hit]
        /// Ce qui n'y est pas.
        public let available: [Hit]

        public init(installed: [Hit], available: [Hit]) {
            self.installed = installed
            self.available = available
        }
    }

    /// Sépare selon l'installé, par deux clés : **mod entier** (id Nexus) ou
    /// **greffe sans manifeste** (nom au registre).
    /// ⚠️ Le nom d'un dépôt est **celui du fichier** (« FishingLogbook - FR
    /// 50233 1.1.0 … ») : l'égalité échoue sur les trois archives, le
    /// **préfixe** (deux sens) réussit.
    public static func partition(_ hits: [Hit], installedNexusIds: Set<Int>,
                                 installedTitles: Set<String>) -> Partition {
        var installed: [Hit] = []
        var available: [Hit] = []
        for hit in hits {
            let matchesName = installedTitles.contains { namesMatch($0, hit.name) }
            if installedNexusIds.contains(hit.modId) || matchesName {
                installed.append(hit)
            } else {
                available.append(hit)
            }
        }
        return Partition(installed: installed, available: available)
    }

    /// Même chose ? **Préfixe dans les deux sens** sur titres réduits (Nexus
    /// suffixe ses noms de fichier). **Plancher de 4 des deux côtés**
    /// (« R.S.V. » → `rsv` préfixerait « RSV Item Bags »).
    public static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = comparableTitle(lhs)
        let right = comparableTitle(rhs)
        guard left.count >= 4, right.count >= 4 else { return false }
        return left.hasPrefix(right) || right.hasPrefix(left)
    }

    /// Ids Nexus d'un nom de fichier téléchargé (14/15 archives) :
    /// `FishingLogbook - FR 50233 1.1.0 …`, `Utility Bags-37381-1-0-0-…`.
    /// Plusieurs candidats (une année en est un) : `confirmedNexusId` tranche.
    /// ≠ `NexusArchiveName.parse` (un seul id, hors ligne, au dépôt).
    public static func nexusIdCandidates(inFileName name: String) -> Set<Int> {
        var candidates: Set<Int> = []
        var digits = ""
        for character in name + " " {
            if character.isASCII, character.isNumber {
                digits.append(character)
            } else {
                if (4...6).contains(digits.count), let value = Int(digits) {
                    candidates.insert(value)
                }
                digits = ""
            }
        }
        return candidates
    }

    /// Fiche attribuable **avec certitude** à un dépôt manuel : titre (préfixe)
    /// **et** id du nom de fichier concordent. `nil` à la moindre ambiguïté.
    public static func confirmedNexusId(forDeposit name: String, among hits: [Hit]) -> Hit? {
        let candidates = nexusIdCandidates(inFileName: name)
        guard !candidates.isEmpty else { return nil }
        let matches = hits.filter { candidates.contains($0.modId) && namesMatch(name, $0.name) }
        return matches.count == 1 ? matches[0] : nil
    }

    /// `2026-08-16T15:32:14Z`, avec ou sans fraction de seconde.
    static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw)
    }
}
