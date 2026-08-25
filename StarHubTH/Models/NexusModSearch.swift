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
    public struct Hit: Equatable, Identifiable, Sendable {
        public var id: Int { modId }
        public let modId: Int
        public let name: String
        public let version: String
        public let updatedAt: Date?
        public let categoryName: String
        public let uploader: String
        public let adultContent: Bool

        public init(modId: Int, name: String, version: String, updatedAt: Date?,
                    categoryName: String, uploader: String, adultContent: Bool) {
            self.modId = modId
            self.name = name
            self.version = version
            self.updatedAt = updatedAt
            self.categoryName = categoryName
            self.uploader = uploader
            self.adultContent = adultContent
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
            nodes { modId name version updatedAt adultContent status
                    modCategory { name } uploader { name } }
          }
        }
        """
        var variables: [String: Any] = ["name": term, "game": String(gameId),
                                        "count": count, "offset": offset]
        if let tag { variables["tag"] = tag }
        return try? JSONSerialization.data(withJSONObject: ["query": query,
                                                            "variables": variables])
    }

    /// Le terme réellement envoyé : sans accents, et débarrassé de ce qui ne
    /// sert qu'à l'humain.
    ///
    /// **L'index de Nexus ne connaît pas les accents.** Mesuré : « Français »
    /// rend 0 résultat là où « Francais » en rend 184. Un nom de mod accentué
    /// chercherait donc dans le vide sans qu'aucune erreur ne le signale.
    public static func searchTerm(for name: String) -> String {
        name.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Réponse

    /// Lit une réponse GraphQL. Le tableau `errors` l'emporte sur les données :
    /// une réponse partielle est une panne, pas un résultat.
    public static func decode(_ data: Data) -> Result<[Hit], Failure> {
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

        return .success(nodes.compactMap(hit(from:)))
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
        return Hit(modId: modId,
                   name: name,
                   version: node["version"] as? String ?? "",
                   updatedAt: (node["updatedAt"] as? String).flatMap(parseDate),
                   categoryName: category,
                   uploader: uploader,
                   adultContent: node["adultContent"] as? Bool ?? false)
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

    /// `2026-08-16T15:32:14Z`, avec ou sans fraction de seconde.
    static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw)
    }
}
