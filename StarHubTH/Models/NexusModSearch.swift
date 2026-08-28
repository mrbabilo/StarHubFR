import Foundation

/// Chercher un mod sur Nexus **par son nom**.
///
/// L'API publique v1 ne sait pas le faire : `/mods/search.json` rend 422, et
/// `latest_updated.json` ne donne que dix entrées couvrant une heure. La voie
/// est l'API GraphQL v2 (`POST /v2/graphql`), vérifiée sur un compte réel le
/// 2026-08-25. Elle n'est **pas documentée publiquement** : tout ce fichier
/// traite donc le service comme une dépendance qui peut changer sans préavis,
/// et préfère dire « je n'ai pas pu chercher » plutôt que rendre une réponse
/// fausse.
///
/// Type pur : construction de la requête et lecture de la réponse, sans réseau.
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
        /// Les tags Nexus du mod.
        ///
        /// C'est ce qui sépare un supplément d'une traduction, et rien d'autre
        /// ne le fait : mesuré sur douze résultats pour « Wildflour », les six
        /// traductions portent toutes `Translation` et les deux vrais
        /// suppléments n'en portent aucun. Le titre, lui, ne dit rien —
        /// « (ES-LATAM) … » n'annonce pas plus une traduction que
        /// « Item Bags for … » n'annonce une greffe.
        public let tags: [String]
        /// Endossements Nexus, quand la réponse les porte. Le champ est
        /// scalaire et NON_NULL côté schéma (introspection 2026-08-27), mais
        /// l'API n'est pas documentée : absent ≠ zéro, la carte affiche sans.
        public let endorsements: Int?
        /// Le résumé d'une ligne — servi par les listings eux-mêmes, sans
        /// requête de fiche (mesuré 2026-08-27).
        public let summary: String?
        /// La vignette du mod, servie par les listings et la recherche
        /// (4 mods sur 4 en tête de tendances, capture 2026-08-27). Une carte
        /// sans vignette reste une carte.
        public let thumbnailUrl: String?

        public init(modId: Int, name: String, version: String, updatedAt: Date?,
                    categoryName: String, uploader: String, adultContent: Bool,
                    tags: [String] = [], endorsements: Int? = nil,
                    summary: String? = nil, thumbnailUrl: String? = nil) {
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
        }

        /// `true` quand Nexus range ce mod parmi les traductions.
        public var isTranslation: Bool {
            tags.contains { $0.caseInsensitiveCompare(NexusModSearch.translationTag) == .orderedSame }
        }
    }

    /// Une page de résultats : ce qu'on a reçu, et **combien il y en a en tout**.
    ///
    /// Le total n'est pas décoratif. La requête plafonne à `count`, et l'écran
    /// en montre moins encore ; sur un nom générique — « Content Patcher » rend
    /// **428** résultats — taire le total laisserait croire que la poignée
    /// affichée est tout ce qui existe.
    public struct Page: Equatable, Codable {
        public let hits: [Hit]
        public let totalCount: Int

        public init(hits: [Hit], totalCount: Int) {
            self.hits = hits
            self.totalCount = totalCount
        }
    }

    public enum Failure: Error, Equatable {
        /// Le service a répondu, mais avec des erreurs GraphQL — schéma changé,
        /// filtre refusé, droits. **Un 200 ne suffit pas à conclure au succès :**
        /// GraphQL rend 200 avec un tableau `errors`, et prendre ça pour un
        /// résultat vide transformerait une panne en « aucune traduction
        /// trouvée ».
        case service(String)
        /// Réponse illisible : ce n'est pas du JSON, ou pas la forme attendue.
        case malformed
    }

    // MARK: - Requête

    /// Corps JSON de la requête de recherche par nom.
    ///
    /// - Parameters:
    ///   - name: le nom à chercher — celui du mod installé, pas un mot-clé.
    ///   - gameId: identifiant **numérique** du jeu. `gameDomainName` seul rend
    ///     `totalCount: 0` sans la moindre erreur : un faux négatif silencieux,
    ///     et la raison pour laquelle ce paramètre n'a pas de valeur par défaut
    ///     lisible ailleurs que dans `NexusRequestBuilder`.
    ///   - count: nombre de résultats. Douze suffisaient à couvrir un mod et
    ///     ses onze traductions ; le défaut laisse de la marge.
    /// Le tag que Nexus pose sur les traductions françaises.
    ///
    /// Mesuré sur 80 traductions françaises réelles : **77 le portent**, et
    /// toutes portent `Translation`. Filtrer dessus laisse le tri au serveur —
    /// sur le mod « Parchment », « nom + tag French » rend **exactement** la
    /// bonne traduction là où le nom seul en rendait douze, toutes langues
    /// confondues.
    ///
    /// ⚠️ **Ce n'est pas la catégorie.** Stardew Valley n'a aucune catégorie
    /// « Traduction » — ses 27 catégories décrivent le contenu du mod — et les
    /// traductions françaises se répartissent sur **treize** d'entre elles
    /// (Gameplay Mechanics 27, Miscellaneous 17, Expansions 10…), chacune
    /// héritant de la catégorie du mod qu'elle traduit. Filtrer par catégorie
    /// ne rendrait rien.
    public static let frenchTag = "French"

    /// Le tag que Nexus pose sur **toute** traduction, quelle que soit la
    /// langue. Sur 80 traductions françaises relevées, les 80 le portent — là
    /// où 77 seulement portent `French`. C'est donc lui, et non le titre, qui
    /// écarte les traductions d'une recherche de suppléments : sur
    /// « Sword and Sorcery », les huit premiers résultats sur vingt-six sont
    /// des traductions japonaises, chinoises, hongroises, brésiliennes…
    public static let translationTag = "Translation"

    public static func queryBody(name: String, gameId: Int, tag: String? = nil,
                                 count: Int = 30, offset: Int = 0) -> Data? {
        let term = searchTerm(for: name)
        guard !term.isEmpty else { return nil }
        // Le filtre de tag n'entre dans la requête que s'il est demandé : un
        // `tag` vide ou nul rendrait `totalCount: 0` sans erreur, comme le
        // domaine du jeu à la place de son identifiant.
        let tagFilter = tag.map { _ in ", tag: { value: $tag, op: EQUALS }" } ?? ""
        let tagParam = tag.map { _ in ", $tag: String!" } ?? ""
        let query = """
        query ModsByName($name: String!, $game: String!, $count: Int!, $offset: Int!\(tagParam)) {
          mods(
            filter: { name: { value: $name, op: WILDCARD },
                      gameId: { value: $game, op: EQUALS }\(tagFilter) }
            sort: { updatedAt: { direction: DESC } }
            count: $count
            offset: $offset
          ) {
            totalCount
            nodes { modId name version updatedAt adultContent status thumbnailUrl
                    modCategory { name } uploader { name } tags { name } }
          }
        }
        """
        var variables: [String: Any] = ["name": term, "game": String(gameId),
                                        "count": count, "offset": offset]
        if let tag { variables["tag"] = tag }
        return try? JSONSerialization.data(withJSONObject: ["query": query,
                                                            "variables": variables])
    }

    /// Le terme réellement envoyé : sans accents, sans préfixe de convention,
    /// et débarrassé de ce qui ne sert qu'à l'humain.
    ///
    /// **L'index de Nexus ne connaît pas les accents.** Mesuré : « Français »
    /// rend 0 résultat là où « Francais » en rend 184. Un nom de mod accentué
    /// chercherait donc dans le vide sans qu'aucune erreur ne le signale.
    ///
    /// **Et il ne connaît pas non plus les préfixes de convention.** Le nom
    /// déclaré par un manifeste commence souvent par l'acronyme du *framework*
    /// qui charge le content pack — `[CP]` Content Patcher, `[FTM]` Farm Type
    /// Manager, `[AT]` Alternative Textures, `[JA]` Json Assets… C'est une
    /// convention communautaire pour ranger un dossier (cf. `docs/DOMAINE.md`),
    /// **pas un morceau du titre Nexus**. La recherche portant sur une
    /// **sous-chaîne** de ce titre, le préfixe la fait échouer entièrement, et
    /// en silence. Mesuré sur l'API réelle le 2026-08-25, six noms du parc,
    /// six fois le même écart :
    ///
    /// | nom déclaré | résultats | sans préfixe |
    /// |---|---|---|
    /// | `[CP] Make Gunther Real` | 0 | 9 |
    /// | `[FTM] Wildflour's Atelier Goods` | 0 | 12 |
    /// | `[AT] Vanilla Forage Crops and Bushes` | 0 | 6 |
    ///
    /// **148 manifestes sur 995** en portent un dans le parc de référence :
    /// autant de fiches qui annonçaient « aucune traduction trouvée » sans
    /// avoir rien cherché de trouvable.
    public static func searchTerm(for name: String) -> String {
        let stripped = stripConventionPrefixes(name)
        return stripped.folding(options: [.diacriticInsensitive],
                                locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Retire les préfixes `[…]` et `(…)` de tête, tant qu'il en reste.
    ///
    /// Uniquement en tête, uniquement courts : un `(Traduction francaise - FR)`
    /// en fin de titre appartient au titre, et `[Something Very Long]` n'est
    /// pas une convention de cadre. **Ne rend jamais le vide** : un nom qui ne
    /// serait fait que de crochets vaut mieux cherché tel quel que pas cherché
    /// du tout.
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

    /// Les tris demandables pour un listing de vitrine.
    ///
    /// Les noms viennent du type `ModsSort`, lu en introspection le
    /// 2026-08-27 : `createdAt, downloads, endorsements, lastComment, name,
    /// random, relevance, size, uniqueDownloads, updatedAt`. Pas de
    /// `endorsed` ni d'`endorsementCount` — les deux premiers candidats du
    /// plan étaient faux, l'introspection les a départagés.
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

    /// Corps JSON d'un **listing** — les mods du jeu par tri, sans nom cherché.
    ///
    /// Même forme que `queryBody(name:)`, le filtre `name` en moins : la
    /// vitrine ne cherche rien, elle montre. Mesuré sur l'API réelle le
    /// 2026-08-27 : le jeu entier rend 33 199 mods, le seul tag `French`
    /// en rend 747.
    public static func listingBody(sort: ListingSort, tag: String? = nil,
                                   gameId: Int, count: Int = 20) -> Data? {
        let tagFilter = tag.map { _ in ", tag: { value: $tag, op: EQUALS }" } ?? ""
        let tagParam = tag.map { _ in ", $tag: String!" } ?? ""
        let query = """
        query ModListing($game: String!, $count: Int!, $offset: Int!\(tagParam)) {
          mods(
            filter: { gameId: { value: $game, op: EQUALS }\(tagFilter) }
            sort: { \(sort.graphQLField): { direction: DESC } }
            count: $count
            offset: $offset
          ) {
            totalCount
            nodes { modId name version updatedAt adultContent status endorsements
                    summary thumbnailUrl modCategory { name } uploader { name } tags { name } }
          }
        }
        """
        var variables: [String: Any] = ["game": String(gameId), "count": count, "offset": 0]
        if let tag { variables["tag"] = tag }
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
        /// URL de l'image principale, seule que le schéma garantit
        /// (`pictureUrl`, introspection 2026-08-27). Peut être vide : la fiche
        /// sans image reste une fiche.
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

    /// La fiche d'un mod, par son identifiant — même racine `mods` éprouvée,
    /// un filtre de plus. Champs optionnels partout : une fiche dégradée vaut
    /// mieux qu'une erreur habillée en fiche introuvable.
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

    /// Lit une réponse de fiche. Mêmes règles que `decode` : `errors` l'emporte,
    /// et une image ou une description absente ne fait pas échouer la fiche.
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

    /// Lit une réponse GraphQL. Le tableau `errors` l'emporte sur les données :
    /// une réponse partielle est une panne, pas un résultat.
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

        // Un `totalCount` absent n'est pas zéro : mieux vaut retomber sur ce
        // qu'on a reçu que d'annoncer « aucun résultat » en en affichant douze.
        let total = (mods["totalCount"] as? Int) ?? nodes.count
        return .success(Page(hits: nodes.compactMap(hit(from:)), totalCount: total))
    }

    private static func hit(from node: [String: Any]) -> Hit? {
        // `modId` peut arriver en nombre ou en chaîne selon les champs : les
        // deux sont acceptés plutôt que d'écarter le résultat en silence.
        let modId: Int?
        if let value = node["modId"] as? Int { modId = value }
        else if let value = node["modId"] as? String { modId = Int(value) }
        else { modId = nil }
        guard let modId, let name = node["name"] as? String else { return nil }

        // Seuls les mods publiés sont proposables : un brouillon ou un mod
        // retiré ne se télécharge pas.
        if let status = node["status"] as? String, status != "published" { return nil }

        let category = (node["modCategory"] as? [String: Any])?["name"] as? String ?? ""
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
                   thumbnailUrl: node["thumbnailUrl"] as? String)
    }

    // MARK: - Reconnaître une traduction française

    /// Ce qui, dans un titre Nexus, annonce une traduction **française**.
    ///
    /// Relevé sur des titres réels : « … - Francais », « … FR », « … VF »,
    /// « Traduction française de … », « French Translation ». Les auteurs
    /// écrivent aussi bien avec qu'sans cédille, d'où le repli des accents.
    private static let frenchMarkers: Set<String> = [
        "fr", "fra", "vf", "francais", "francaise", "french", "frenchie",
        "traduction", "traduit", "traduite", "francophone",
    ]

    /// `true` quand ce titre annonce une traduction française.
    ///
    /// **Filet de secours, pas chemin principal** : le tag `French` de Nexus
    /// est plus sûr et se filtre côté serveur. Trois traductions sur quatre-
    /// vingts ne le portent pas ; ce sont celles-là que le titre rattrape.
    ///
    /// Compare des **mots entiers**, jamais des fragments : « fr » contenu dans
    /// « from », « fresh » ou « Frontier » ferait passer pour françaises la
    /// moitié des pages de Nexus — le mot-clé « FR » seul rend 1 559 mods sur
    /// Stardew, là où « Francais » en rend 184.
    ///
    /// Les titres des autres langues ne sont pas écartés à part : il suffit de
    /// n'avoir aucun marqueur français pour être laissé de côté. « PT-BR »,
    /// « KOR Translation » ou « Traditional Chinese » n'en portent aucun.
    public static func announcesFrenchTranslation(_ title: String) -> Bool {
        !words(in: title).isDisjoint(with: frenchMarkers)
    }

    /// Découpe un titre en mots comparables : accents repliés, minuscules,
    /// césure sur tout ce qui n'est ni lettre ni chiffre — un « PT-BR » donne
    /// donc « pt » et « br », et un « Log_JP » donne « log » et « jp ».
    static func words(in title: String) -> Set<String> {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
        return Set(folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty })
    }

    /// Parmi des résultats de recherche **non filtrés par le serveur**, les
    /// seules traductions françaises, la plus récemment mise à jour en tête.
    ///
    /// Réservé à la recherche large, où rien d'autre que le titre ne distingue
    /// une traduction. Sur un résultat déjà restreint au tag `French`, c'est
    /// `ranked(_:excluding:)` qu'il faut : y rejouer le titre jetterait les
    /// traductions correctement taguées dont le titre ne dit rien.
    public static func frenchTranslations(among hits: [Hit],
                                          excluding hostModId: Int? = nil) -> [Hit] {
        hits.filter { announcesFrenchTranslation($0.name) && $0.modId != hostModId }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    /// Des résultats **déjà tagués `French` par le serveur**, les plus probables
    /// d'abord.
    ///
    /// **Le titre classe, il ne filtre pas.** Sur 80 traductions relevées, 77
    /// portent le tag : rejeter celles dont le titre ne dit pas « FR »
    /// reviendrait à perdre celles-là mêmes que le tag rattrapait, et la fiche
    /// annoncerait qu'aucune traduction n'existe.
    ///
    /// Le mod hôte est écarté : un mod qui porte le tag `French` parce qu'il
    /// est lui-même français n'est pas sa propre traduction.
    public static func ranked(_ hits: [Hit], excluding hostModId: Int? = nil) -> [Hit] {
        hits.filter { $0.modId != hostModId }
            .sorted {
                let left = announcesFrenchTranslation($0.name)
                let right = announcesFrenchTranslation($1.name)
                if left != right { return left }
                return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
    }

    /// La vitrine « Découvrir » est francophone : un mod non-traduction y
    /// est toujours bienvenu, une traduction n'y figure que si elle est
    /// **française**. Les autres — japonaises, chinoises, brésiliennes… —
    /// n'ont rien à y faire.
    ///
    /// La règle se paie : le tag `French` porte **77 traductions sur 80**
    /// (mesuré en A3-T3/T4, repris à la spec §3) — environ une traduction
    /// française sur vingt est donc écartée à tort. Le compte « x affichés
    /// sur y » de la section dit au moins qu'un filtre est passé.
    /// À n'appliquer qu'en vitrine : une recherche par nom doit rendre ce
    /// qu'on lui a demandé.
    public static func vitrineEligible(_ hit: Hit) -> Bool {
        guard hit.isTranslation else { return true }
        return hit.tags.contains {
            $0.caseInsensitiveCompare(frenchTag) == .orderedSame
        }
    }

    // MARK: - Reconnaître un supplément

    /// Les **suppléments** d'un mod parmi des résultats de recherche : greffes
    /// d'assets, compatibilités, packs qui citent ce mod dans leur titre.
    ///
    /// **Chercher n'est pas le problème, trier l'est.** Mesuré sur l'API réelle
    /// le 2026-08-25 : `op: WILDCARD` cherche une **sous-chaîne** du titre, si
    /// bien que le nom du mod installé suffit à faire remonter ses suppléments
    /// — « Wildflour » rend « Item Bags for Wildflour's Atelier Goods ». Mais
    /// les résultats sont **noyés de traductions** : sur « Sword and Sorcery »,
    /// les huit premiers sur vingt-six sont japonais, chinois, hongrois,
    /// brésiliens… ; sur « Automate », 21 des 43.
    ///
    /// Deux retraits, et rien d'autre :
    /// - **le tag `Translation`**, que Nexus pose sur toute traduction quelle
    ///   que soit la langue. C'est le seul signal qui les sépare : sur douze
    ///   résultats « Wildflour », les six traductions le portent toutes et les
    ///   deux vrais suppléments n'en portent aucun. Le titre, lui, ne dit rien ;
    /// - **le mod hôte lui-même**, qui n'est pas son propre supplément.
    ///
    /// Ce qui reste n'est **pas certain** d'être un supplément : c'est un mod
    /// dont le titre cite celui-ci. Sur un nom générique — « Content Patcher »
    /// rend 428 résultats dont 45 sur 50 ne sont pas des traductions — la liste
    /// est surtout du bruit. L'appelant doit donc plafonner **et dire le
    /// total**, jamais faire comme s'il savait.
    /// - Parameters:
    ///   - hostModId: l'identifiant Nexus du mod, quand il en déclare un.
    ///   - hostName: son nom. **Le repli qui compte** : 111 mods du parc ne
    ///     déclarent aucun identifiant, et sans ce second filet le mod
    ///     figurerait en tête de ses propres suppléments — vu en simulant la
    ///     recherche sur « Wildflour's Atelier Goods », qui se rendait
    ///     lui-même.
    public static func supplements(among hits: [Hit], excluding hostModId: Int? = nil,
                                   hostName: String = "") -> [Hit] {
        let host = comparableTitle(hostName)
        return hits
            .filter { hit in
                guard !hit.isTranslation, hit.modId != hostModId else { return false }
                // Sur le titre **réduit**, jamais sur l'égalité brute : le
                // manifeste dit « [FTM] Wildflour's Atelier Goods » là où Nexus
                // titre « Wildflour's Atelier Goods - An Artisan Goods
                // Expansion ». C'est le titre qui *commence* par le nom du mod
                // sans rien y ajouter d'autre qu'un sous-titre qui est l'hôte.
                return !host.isEmpty ? comparableTitle(hit.name) != host : true
            }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    /// Un candidat à l'identité d'un mod : la fiche Nexus qui pourrait être la
    /// sienne, et si l'auteur le confirme.
    public struct IdentityCandidate: Equatable, Identifiable, Sendable {
        public var id: Int { hit.modId }
        public let hit: Hit
        /// L'auteur déclaré par le manifeste et le pseudo Nexus concordent.
        /// **Un indice, jamais un filtre** — voir `identityCandidates`.
        public let authorMatches: Bool

        public init(hit: Hit, authorMatches: Bool) {
            self.hit = hit
            self.authorMatches = authorMatches
        }
    }

    /// Les fiches Nexus qui pourraient être celle de ce mod, la plus probable
    /// en tête.
    ///
    /// Un mod sans identifiant Nexus n'a ni suivi de version, ni page, ni
    /// recherche de traduction. `NexusIdLearning` récupère ceux que smapi.io
    /// connaît ; pour les autres, il ne reste que le nom — et le nom est
    /// traître. Mesuré sur les **83 mods du parc qui restent sans identifiant**,
    /// recherche réellement exécutée le 2026-08-26 :
    ///
    /// - **55 ne rendent rien.** Mod retiré, renommé, jamais publié sur Nexus.
    ///   20 d'entre eux sont des **composants de pack** : « ARV- Maximum » n'a
    ///   jamais été un titre Nexus, c'est le pack qui a une page.
    /// - **23 rendent des candidats, dont 61 % sont des traductions** — 45 sur
    ///   74. Le titre d'une traduction commence par celui du mod, donc la
    ///   comparaison par préfixe les attrape toutes : « LewdDew Valley » rend
    ///   neuf candidats, neuf traductions. Le tag `Translation` est le seul
    ///   moyen de les écarter, et il les écarte toutes.
    /// - Une fois écartées, **18 mods n'ont plus qu'un seul candidat** (contre
    ///   14 sans le filtre) et les cinq listes restantes deviennent lisibles.
    ///
    /// **L'auteur confirme, il ne tranche pas.** Sur ces 18, le pseudo Nexus
    /// concorde 12 fois, parfois à une variante près (`skeleton` /
    /// `Skeleton0w0`), et parfois pas du tout alors que c'est bien le même mod
    /// (`Owljoy` / `OwlandJoy`). En faire un filtre perdrait des candidats
    /// justes ; il n'ordonne donc que l'affichage.
    ///
    /// Rien n'est écrit d'autorité : c'est une **proposition**, et l'utilisateur
    /// désigne. Deux des 18 candidats uniques mesurés portent un auteur sans
    /// rapport — une ligne qui suit le mauvais mod est pire qu'une ligne qui ne
    /// suit rien.
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

    /// L'auteur déclaré par un manifeste et un pseudo Nexus désignent-ils la
    /// même personne ?
    ///
    /// Par préfixe, dans les deux sens, avec le même plancher de quatre
    /// caractères que `namesMatch` : le pseudo Nexus prolonge souvent celui du
    /// manifeste (`kurts` / `kurtsietz`). Et un manifeste nomme parfois
    /// **plusieurs** auteurs — « StarAmy/Mila Stavetskaya », « Haze1nuts, 58
    /// and Cara » — dont un seul a publié la page : chacun est essayé.
    ///
    /// Répond `false` sans hésiter quand rien ne concorde : ce n'est pas une
    /// accusation, seulement l'absence d'un indice.
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

    /// Un titre réduit à ce qui l'identifie : préfixe de cadre retiré, accents
    /// repliés, ponctuation et casse écartées.
    static func comparableTitle(_ name: String) -> String {
        stripConventionPrefixes(name)
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Des résultats séparés en deux : ce qui est déjà en place, et ce qui
    /// reste à découvrir.
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

    /// Sépare des résultats selon ce qui est déjà installé.
    ///
    /// **Deux formes, mesurées sur le parc le 2026-08-26.** Un supplément peut
    /// être installé de deux façons très différentes :
    /// - **comme un mod à part entière**, avec son manifeste — 2 des 10
    ///   suppléments de Cornucopia, 1 des 12 de Ridgeside Village. Il se
    ///   reconnaît à son identifiant Nexus, déjà déclaré par le parc ;
    /// - **comme une greffe sans manifeste**, un lot de sacs `ItemBags` déposé
    ///   à la main. Aucun identifiant : c'est le registre qui le retient, et le
    ///   nom du dépôt est parfois tout ce dont on dispose.
    ///
    /// D'où deux clés, et non une.
    ///
    /// ⚠️ **Le nom retenu d'un dépôt manuel est celui du fichier téléchargé, pas
    /// le titre Nexus.** Mesuré sur les archives réelles : « FishingLogbook -
    /// FR 50233 1.1.0 2026-08-05T17-33Z 2hI4jbUR4 » pour un mod que Nexus
    /// titre « FishingLogbook - FR ». L'égalité échoue donc sur **les trois**
    /// archives éprouvées, et le **préfixe** réussit sur les trois : Nexus
    /// suffixe ses noms de fichier d'identifiant, version, date et jeton, sans
    /// jamais toucher au début. La comparaison se fait donc par préfixe, dans
    /// les deux sens — l'archive peut être plus longue que le titre, et
    /// l'inverse arrive quand l'auteur allonge son titre après coup.
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

    /// Deux noms désignent-ils la même chose ?
    ///
    /// **Par préfixe, dans les deux sens**, sur les titres réduits — parce que
    /// le nom d'un dépôt est celui du fichier téléchargé et que Nexus le
    /// suffixe d'identifiant, version, date et jeton sans jamais toucher au
    /// début (mesuré : l'égalité échoue sur les trois archives éprouvées, le
    /// préfixe réussit sur les trois).
    ///
    /// **Le plancher de quatre caractères vaut des deux côtés.** Le garder d'un
    /// seul laisserait un titre court reconnaître n'importe quoi : « R.S.V. »
    /// se réduit à `rsv` et préfixe « RSV Item Bags ».
    public static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = comparableTitle(lhs)
        let right = comparableTitle(rhs)
        guard left.count >= 4, right.count >= 4 else { return false }
        return left.hasPrefix(right) || right.hasPrefix(left)
    }

    /// Les identifiants Nexus que porte un nom de fichier téléchargé.
    ///
    /// **Mesuré : 14 des 15 archives du jeu d'épreuve en portent un.** Nexus
    /// nomme ses téléchargements de deux façons, et l'identifiant suit le nom
    /// dans les deux :
    /// `FishingLogbook - FR 50233 1.1.0 2026-08-05T17-33Z 2hI4jbUR4`
    /// `Utility Bags-37381-1-0-0-1757199288`
    /// La seule exception est une archive renommée à la main.
    ///
    /// Plusieurs candidats sont rendus, jamais un seul « deviné » : une année
    /// dans un titre en est un aussi. C'est `confirmedNexusId` qui tranche, en
    /// exigeant qu'un second signal concorde.
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

    /// La fiche Nexus qu'on peut attribuer **avec certitude** à un dépôt manuel.
    ///
    /// Deux signaux indépendants doivent concorder : le titre, comparé par
    /// préfixe, **et** l'identifiant lu dans le nom du fichier. Chacun seul se
    /// tromperait — un titre proche n'est pas le même mod, et un nombre à cinq
    /// chiffres dans un nom peut être une année. Ensemble, ils ne laissent pas
    /// de place au doute, et c'est ce qui permet de rattacher sans rien
    /// demander à l'utilisateur.
    ///
    /// `nil` dès qu'il y a la moindre ambiguïté : mieux vaut une ligne sans
    /// suivi qu'une ligne qui suit le mauvais mod.
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
