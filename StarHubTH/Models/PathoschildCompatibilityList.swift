import Foundation

/// Fallback hors-ligne pour la liste de compatibilité `Pathoschild/SmapiCompatibilityList`.
///
/// La source primaire reste `smapi.io/api/v3.0/mods` (A2-T1/T2) : plus riche
/// (`suggestedUpdate`, `unofficialUpdate`, etc.), elle est ce qui sert
/// habituellement la fiche. Mais :
/// - **smapi.io répond `[]` silencieusement** au-delà d'un certain débit
///   (mesuré ~100 mods/min par IP, jamais 429), sans rien dire ;
/// - **smapi.io peut être en panne**, comme toute API publique ;
/// - **la base de compatibilité Pathoschild reste publiée** sous forme d'un
///   dump statique `data/mods.jsonc` (~4 000 mods, un par `UniqueID`) et tient
///   lieu de filet.
///
/// Ce type :
/// 1. **récupère** le dump depuis l'URL canonique du dépôt Pathoschild
///   (`https://raw.githubusercontent.com/Pathoschild/SmapiCompatibilityList/develop/data/mods.jsonc`)
///   en passant par `URLSession.shared` (timeout court, sans clé ni quota) ;
/// 2. **strippe** les commentaires JSONC (`//` et `/* … */`) avant
///   `JSONSerialization` — `JSONSerialization` n'accepte pas les commentaires ;
/// 3. **décode** uniquement les champs nécessaires (`id`, `status`, `brokeIn`,
///   `summary`, `unofficialUpdate`) en ignorant les clés `name`, `author`,
///   `github`, etc. ;
/// 4. **joint** sur `UniqueID` à la liste des mods installés, en rendant
///   `ModCompatibility` (le même type que smapi.io) pour ne pas multiplier les
///   formes de verdicts côté UI.
///
/// Le résultat n'est **pas** aussi riche que smapi.io — pas de
/// `suggestedUpdate` — mais le verdict de statut
/// (`broken`/`abandoned`/`obsolete`/`workaround`/`unofficial`) y est, et
/// `brokeIn` aussi quand présent. C'est strictement le filet qui manquait
/// quand smapi.io se tait.
///
/// Mis en cache sur disque (Application Support) avec un TTL de **6 h**,
/// aligné sur celui de smapi.io (A2-T4). Une panne réseau prolongée finit par
/// voir son cache expirer — c'est voulu, un dump vieux de plusieurs jours
/// risque plus de signaler un mod qu'il n'a plus à signaler.
public enum PathoschildCompatibilityList {

    /// URL canonique du dump. Branche `develop` — c'est ce que publie
    /// Pathoschild en continu, jamais gelé sur une release.
    public static let dumpURL = URL(string:
        "https://raw.githubusercontent.com/Pathoschild/SmapiCompatibilityList/develop/data/mods.jsonc")!

    /// TTL du cache disque : 6 h. Au-delà, le fichier est ignoré et la
    /// requête réseau repart. Aligné sur la borne basse de la prescription
    /// A2-T4 (6–24 h).
    public static let cacheTTL: TimeInterval = 6 * 60 * 60

    /// Une entrée brute du dump, réduite aux champs que l'app utilise.
    /// Les autres (`name`, `author`, `github`, `curse`, `chucklefish`,
    /// `abandonedReason`, `warnings`, `source`, …) sont ignorées : on les
    /// laisse tomber côté décodeur, jamais on ne les propage. Ce qu'elles
    /// vaudraient est mesuré dans la ROADMAP (X56) — `warnings` porte
    /// 17 mentions d'Android sur 24, et `abandonedReason` n'accompagne jamais
    /// qu'un statut `abandoned` déjà rendu.
    public struct Entry: Decodable, Equatable, Sendable {
        public let id: String
        public let status: String?
        public let brokeIn: String?
        public let summary: String?
        /// L'identifiant Nexus tel que Pathoschild le porte — `null` quand le
        /// mod n'est pas listé chez Nexus (ex. mods GitHub/ModDrop/CurseForge
        /// exclusifs, mods très récents, mods retirés). Lu depuis le champ
        /// `nexus` du JSONC. C'est la source locale privilégiée pour associer
        /// un `UniqueID` à un `nexusID` quand smapi.io ne le rend pas —
        /// meilleure couverture que smapi.io sur le parc (Pathoschild tient
        /// ~4 000 mods là où smapi.io est plus étroit), et **offline** : on
        /// évite une requête Nexus par mod que smapi.io a ignoré.
        public let nexusID: Int?
        /// Ce que Pathoschild signale du mod **sans le déclarer cassé** :
        /// télémétrie non divulguée, plantages au chargement d'une sauvegarde,
        /// archive à la structure fausse. 24 entrées sur 4 720 en portent un
        /// (mesuré le 2026-09-05), dont **17 ne parlent que d'Android** — voir
        /// `ModPlatformWarnings`, qui tamise avant tout affichage.
        public let warnings: [String]

        /// La mise à jour non officielle que Pathoschild publie pour ce mod —
        /// version et lien — ou `nil`.
        ///
        /// **Ce champ est presque toujours seul.** Mesuré sur le dump du
        /// 2026-09-04 (4 720 entrées) : **67 le portent, dont 63 sans aucun
        /// `status` et 62 sans `summary`** ; les 67 ont un `brokeIn`. Sans lui,
        /// ces 63 entrées ne produisaient donc **aucun verdict** — le filet
        /// était muet exactement là où smapi.io, interrogé le même jour sur les
        /// mêmes identifiants, répond `Unofficial` et « broken, use unofficial
        /// version ». Sur le parc de référence, quatre mods : Bus Locations,
        /// Mod Update Menu et les deux moitiés de SAAT.
        public let unofficialUpdate: UnofficialUpdate?

        /// Version et destination d'une mise à jour non officielle. Toujours
        /// un objet `{ version, url }` dans le dump — jamais une chaîne,
        /// vérifié sur les 67.
        public struct UnofficialUpdate: Decodable, Equatable, Sendable {
            public let version: String
            public let url: String

            public init(version: String, url: String) {
                self.version = version
                self.url = url
            }
        }

        public init(id: String,
                    status: String?,
                    brokeIn: String?,
                    summary: String?,
                    nexusID: Int?,
                    unofficialUpdate: UnofficialUpdate? = nil,
                    warnings: [String] = []) {
            self.id = id
            self.status = status
            self.brokeIn = brokeIn
            self.summary = summary
            self.nexusID = nexusID
            self.unofficialUpdate = unofficialUpdate
            self.warnings = warnings
        }
    }

    public enum Failure: Error, Equatable {
        case transport(String)
        case http(Int)
        case decoding(String)
    }

    // MARK: - Cache disque

    /// Fichier cache dans Application Support (`StarHubTH/pathoschild_mods.jsonc`).
    /// On stocke le **texte brut** (pas un re-dump JSON) : un re-encodage
    /// perdrait les commentaires JSONC que la prochaine lecture doit re-stripper,
    /// et le décodeur est suffisamment rapide pour ne pas mériter ce détour.
    /// Visibilité `internal` (et non `private`) parce que `PathoschildNexusIndex`
    /// y accède depuis un fichier frère pour servir un dump potentiellement
    /// périmé quand le réseau est absent — le filet doit lire **aussi** un
    /// cache d'il y a trois jours, pas seulement un cache frais.
    static func cacheURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("StarHubTH", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pathoschild_mods.jsonc")
    }

    /// Charge le cache disque s'il est encore frais, sinon `nil`. La date
    /// d'écriture est posée par `writeCache`, lue par `cacheModificationDate`.
    public static func loadFreshCache(now: Date = Date()) -> Data? {
        guard let url = cacheURL(),
              let mtime = cacheModificationDate(url: url),
              now.timeIntervalSince(mtime) < cacheTTL,
              let data = try? Data(contentsOf: url) else { return nil }
        return data
    }

    private static func cacheModificationDate(url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    @discardableResult
    public static func writeCache(_ data: Data) -> Bool {
        guard let url = cacheURL() else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Réception + décodage

    /// Récupère le dump Pathoschild (réseau avec repli cache).
    /// `completion` est invoquée sur le **fil principal**.
    ///
    /// `onEvent` est invoquée à chaque étape significative (début, fin, échec)
    /// pour permettre à l'appelant de journaliser — la couche Core n'a pas
    /// accès au journal de l'app, et inliner un `print()` perdrait le
    /// `LogEntry` typé. La callback est **fire-and-forget** : une exception
    /// ou un retour lent ne doit pas casser le fetch.
    public static func fetch(session: URLSession = .shared,
                             now: Date = Date(),
                             onEvent: ((String) -> Void)? = nil,
                             completion: @escaping (Result<[Entry], Failure>) -> Void) {
        // Le cache, même périmé, vaut un fallback : un lancement hors-ligne
        // doit montrer ce qu'on a plutôt que rien. La fraîcheur est portée
        // par `dumpFetchedAt`, pas par le contenu.
        var request = URLRequest(url: dumpURL)
        request.setValue("application/jsonc", forHTTPHeaderField: "Accept")
        request.setValue(NexusRequestBuilder.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        onEvent?("Récupération du dump Pathoschild en cours…")
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                onEvent?("Dump Pathoschild : échec réseau (\(error.localizedDescription)) — repli cache")
                if let cached = loadFreshCache(now: now) ?? cachedAnyAge(),
                   let entries = decode(cached) {
                    onEvent?("Dump Pathoschild : \(entries.count) mod(s) servis depuis le cache")
                    DispatchQueue.main.async { completion(.success(entries)) }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(.transport(error.localizedDescription)))
                    }
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                onEvent?("Dump Pathoschild : réponse invalide (pas de HTTPURLResponse)")
                DispatchQueue.main.async { completion(.failure(.transport("no_response"))) }
                return
            }
            guard http.statusCode == 200, let data else {
                onEvent?("Dump Pathoschild : HTTP \(http.statusCode) — repli cache")
                if let cached = loadFreshCache(now: now) ?? cachedAnyAge(),
                   let entries = decode(cached) {
                    onEvent?("Dump Pathoschild : \(entries.count) mod(s) servis depuis le cache")
                    DispatchQueue.main.async { completion(.success(entries)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(.http(http.statusCode))) }
                }
                return
            }
            // Un 200 ne suffit pas : le corps doit se **lire**. La décision
            // vit dans `outcome(forPayload:cachedPayload:)` — c'est le seul
            // moyen de la tester, ce chemin-ci exigeant un réseau et le vrai
            // Application Support.
            // Un seul saut vers le fil principal, à la fin : les trois issues
            // se décident ici, et `completion` est rendue une fois.
            let result: Result<[Entry], Failure>
            switch outcome(forPayload: data,
                           cachedPayload: { loadFreshCache(now: now) ?? cachedAnyAge() }) {
            case .fresh(let entries):
                writeCache(data)
                onEvent?("Dump Pathoschild : \(entries.count) mod(s) récupérés, cache mis à jour")
                result = .success(entries)
            case .fallback(let entries):
                onEvent?("Dump Pathoschild : HTTP 200 au corps illisible — cache conservé, "
                         + "\(entries.count) mod(s) servis depuis lui")
                result = .success(entries)
            case .unreadable:
                onEvent?("Dump Pathoschild : HTTP 200 au corps illisible, et aucun cache lisible")
                result = .failure(.decoding("unreadable_payload"))
            }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
    }

    /// Ce que devient un corps de réponse HTTP 200.
    public enum PayloadOutcome: Equatable {
        /// Le corps se lit : ces entrées sont à servir, **et** le corps est à
        /// écrire en cache.
        case fresh([Entry])
        /// Le corps ne se lit pas mais le cache, si : on sert le cache et on
        /// **n'écrit rien**.
        case fallback([Entry])
        /// Ni l'un ni l'autre.
        case unreadable
    }

    /// La règle « on n'écrase le cache que par un corps qu'on sait lire »,
    /// isolée pour être vérifiable sans réseau ni disque.
    ///
    /// **Ce qu'elle corrige** : le code écrivait le cache dès le 200, avant
    /// tout décodage, puis rendait `.success(decode(data) ?? [])`. Une page
    /// d'erreur GitHub, un portail captif ou un transfert tronqué rendent tous
    /// un 200 dont le JSONC ne parse pas — le filet annonçait alors « 0 mod »
    /// comme un succès **et** détruisait un cache de 919 Ko. Ce cache n'est pas
    /// qu'un filet à verdicts : `PathoschildNexusIndex` le relit pour attribuer
    /// un identifiant Nexus aux mods que smapi.io ignore, hors ligne. Un seul
    /// mauvais 200 emportait les deux, jusqu'au prochain 200 valide.
    ///
    /// Le décodage n'a lieu **qu'une fois** par corps : l'ancien code repassait
    /// deux fois sur les 919 Ko pour compter puis pour rendre.
    static func outcome(forPayload data: Data,
                        cachedPayload: () -> Data?) -> PayloadOutcome {
        if let entries = decode(data) { return .fresh(entries) }
        if let cached = cachedPayload(), let entries = decode(cached) {
            return .fallback(entries)
        }
        return .unreadable
    }

    /// Le cache, quel que soit son âge. Distinct de `loadFreshCache` :
    /// un dump d'il y a trois jours reste publiable quand le réseau tombe,
    /// à charge pour l'UI d'en parler.
    private static func cachedAnyAge() -> Data? {
        guard let url = cacheURL() else { return nil }
        return try? Data(contentsOf: url)
    }

    /// La date du dernier 200 servi, ou du cache si rien n'a abouti en réseau.
    /// `nil` quand aucun dump n'a jamais été posé sur le disque.
    public static func dumpFetchedAt(now: Date = Date()) -> Date? {
        // La fraîcheur est mesurée par l'âge du fichier cache : c'est la
        // même opération que `loadFreshCache`, mais sans la borne haute du TTL.
        // Un fichier âgé de 8 h vaut « périmé mais disponible ».
        guard let url = cacheURL(),
              let data = try? Data(contentsOf: url),
              let mtime = cacheModificationDate(url: url),
              !data.isEmpty else { return nil }
        return mtime
    }

    // MARK: - Décodage

    /// Décode le payload JSONC : strippe les commentaires, puis
    /// `JSONSerialization` sur l'objet racine `{ "mods": [ … ] }`.
    /// Renvoie `nil` quand le JSONC est corrompu ou n'a pas la forme attendue.
    public static func decode(_ data: Data) -> [Entry]? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let cleaned = stripJSONComments(raw)
        guard let jsonData = cleaned.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let mods = root["mods"] as? [[String: Any]] else { return nil }
        return mods.compactMap(decodeEntry)
    }

    /// Joint `entries` à `uniqueIds` sur le champ `id` (= `UniqueID`).
    /// Renvoie un dictionnaire `UniqueID → ModCompatibility`. Les entrées sans
    /// `status` ou sans `UniqueID` installé sont silencieusement écartées.
    ///
    /// **Cette jointure est plus étroite que celle de `PathoschildNexusIndex`,
    /// et les chiffres sont là pour le prochain qui s'y intéressera** (mesuré
    /// le 2026-09-03 sur le dump réel — 4 720 entrées — et les 1 083 `UniqueID`
    /// du parc) :
    /// - le champ `id` du dump est parfois une **liste** (`"Gathouria.AdoptSkin,
    ///   Gathouria.AnimalSkinner"` : un mod sous ses deux identifiants
    ///   successifs) — **231 entrées**, dont **42 porteuses d'un statut**. Ici
    ///   on joint sur la chaîne entière, donc aucune de ces 42 n'est
    ///   atteignable ; `PathoschildNexusIndex.loadFromCache`, lui, découpe ;
    /// - la comparaison est sensible à la casse, là où SMAPI compare les
    ///   identifiants de mod sans la casse. Le dump et les manifestes
    ///   divergent réellement (`DIGUS.CustomKissingMod` contre
    ///   `Digus.CustomKissingMod`, `moonslime.ManaBarApi` contre
    ///   `moonslime.ManaBarAPI`).
    ///
    /// Joindre comme SMAPI apparierait **321 mods au lieu de 289** — et
    /// rendrait **exactement les mêmes 2 verdicts** : aucune des 32 entrées
    /// gagnées ne porte de statut. C'est pourquoi rien n'est changé ici :
    /// l'élargir demanderait de trancher deux questions dont la réponse n'est
    /// pas dans ce dépôt (un statut posé sur une paire de renommage vaut-il
    /// pour les deux identifiants ou pour le courant seul ? quelle entrée
    /// gagne quand deux ne diffèrent que par la casse ?) pour un gain mesuré
    /// nul. Si un jour un verdict manque à l'appel, la mesure est ici.
    ///
    /// Autre chose que la mesure a montrée et qui ne s'attrape pas : le champ
    /// `summary` du dump porte des liens Markdown, et **une entrée sur 4 720**
    /// (`Forkmaster.CustomGreenhouse`) oublie la parenthèse fermante de son
    /// lien. `ModCompatibility.parseSummary` laisse alors le balisage en
    /// clair, faute de mieux — deviner où finit l'URL serait une nouvelle
    /// façon d'abîmer une phrase valide. Zéro cas sur le parc de l'auteur.
    public static func verdicts(for uniqueIds: [String],
                                from entries: [Entry]) -> [String: ModCompatibility] {
        let wanted = Set(uniqueIds.filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return [:] }
        var byId: [String: Entry] = [:]
        for entry in entries where wanted.contains(entry.id) {
            byId[entry.id] = entry
        }
        var out: [String: ModCompatibility] = [:]
        for (uniqueId, entry) in byId {
            guard let verdict = verdict(for: entry) else { continue }
            out[uniqueId] = verdict
        }
        return out
    }

    /// Les avertissements **qui nous concernent**, par `UniqueID` installé.
    ///
    /// Deux différences avec `verdicts(for:from:)`, et les deux comptent :
    ///
    /// - l'`id` du dump est parfois une **liste d'alias** séparés par des
    ///   virgules (`"Entoarox.ShopExpander, EntoaroxShopExpander"`) — trois des
    ///   24 entrées à avertissement en portent une. Comparer la chaîne entière
    ///   les manquerait toutes les trois, la leçon que `PathoschildNexusIndex`
    ///   a déjà tirée pour les identifiants Nexus ;
    /// - la liste rendue est **tamisée** par `ModPlatformWarnings` : un mod
    ///   dont il ne reste rien à dire n'a pas d'entrée du tout, plutôt qu'une
    ///   entrée vide dont l'appelant devrait se méfier.
    public static func warnings(for uniqueIds: [String],
                                from entries: [Entry]) -> [String: [String]] {
        let wanted = Set(uniqueIds.filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return [:] }
        var out: [String: [String]] = [:]
        for entry in entries where !entry.warnings.isEmpty {
            let kept = ModPlatformWarnings.worthReading(entry.warnings)
            guard !kept.isEmpty else { continue }
            for alias in entry.id.split(separator: ",") {
                let id = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard wanted.contains(id) else { continue }
                out[id] = kept
            }
        }
        return out
    }

    /// Le verdict d'une entrée, statut inféré compris.
    ///
    /// **L'inférence ne comble qu'une absence.** Un `unofficialUpdate` sans
    /// `status` vaut `unofficial` — c'est ce que smapi.io répond pour ces
    /// mêmes entrées, et ce que la liste de compatibilité calcule en amont.
    /// Mais un statut déjà posé gagne toujours : quatre des 67 en portent un
    /// (trois `workaround`, un `abandoned`), et rétrograder un mod abandonné
    /// en « une mise à jour non officielle existe » perdrait plus que
    /// l'inférence ne gagne — `abandoned` dit justement qu'aucun remplaçant
    /// n'est proposé. Un statut **inconnu** garde lui aussi sa règle : `nil`,
    /// jamais un repli.
    ///
    /// Aucune phrase n'est fabriquée pour les 62 entrées sans `summary` : le
    /// libellé du statut et `brokeIn` sont déjà rendus localisés par l'UI, et
    /// une phrase écrite ici ne serait traduite nulle part. Le lien porte le
    /// **numéro de version** pour libellé — c'est ce qu'il faut installer.
    static func verdict(for entry: Entry) -> ModCompatibility? {
        let base = ModCompatibility.from(status: entry.status,
                                         brokeIn: entry.brokeIn,
                                         summary: entry.summary)
        guard let update = entry.unofficialUpdate else { return base }
        let declaredStatus = entry.status?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard declaredStatus == nil || declaredStatus?.isEmpty == true else { return base }

        let parsed = ModCompatibility.parseSummary(entry.summary ?? "")
        // Le résumé cite parfois déjà la même page (cas réel :
        // `Slothsoft.Informant`) — deux boutons vers la même destination
        // seraient du bruit, l'UI n'en affiche que deux en tout.
        let links = parsed.links.contains(where: { $0.url == update.url })
            ? parsed.links
            : parsed.links + [ModCompatibility.Link(label: update.version, url: update.url)]
        return ModCompatibility(status: .unofficial,
                                brokeIn: normalized(entry.brokeIn),
                                summary: parsed.text,
                                links: links)
    }

    // MARK: - Helpers

    /// Retire les commentaires `//` (jusqu'au prochain saut de ligne) et
    /// `/* … */` du texte. **String-aware** : on n'y touche pas à un `//`
    /// qui tombe à l'intérieur d'une chaîne `"…"`. Sans cette garde, le
    /// résumé « use [Z](https://example.com) instead. » se faisait couper
    /// à « use [Z](https: » — une URL dans une fiche de mod était plus
    /// fréquente qu'un commentaire, et l'inverse aurait coûté un verdict.
///
/// Les chaînes supportées sont celles qu'attend `JSONSerialization` :
/// guillemets droits, échappements `\"` et `\\`. Les séquences Unicode
/// (`\uXXXX`) ne déclenchent pas de commentaire : le `\"` consomme le
/// caractère suivant comme échappement, et c'est tout.
    static func stripJSONComments(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        let chars = Array(raw)
        var i = 0
        let n = chars.count
        var inString = false
        while i < n {
            let c = chars[i]
            if inString {
                out.append(c)
                if c == "\\", i + 1 < n {
                    // Séquence échappée : on reproduit le caractère tel quel.
                    out.append(chars[i + 1])
                    i += 2
                    continue
                }
                if c == "\"" { inString = false }
                i += 1
                continue
            }
            // Bloc /* … */ — peut traverser plusieurs lignes.
            if i + 1 < n, c == "/", chars[i + 1] == "*" {
                var j = i + 2
                while j + 1 < n, !(chars[j] == "*" && chars[j + 1] == "/") {
                    j += 1
                }
                i = (j + 1 < n) ? j + 2 : n
                continue
            }
            // Ligne // …⏎ — le saut de ligne est conservé.
            //
            // ⚠️ `isNewline`, **jamais** `!= "\n"` : `chars` est un tableau de
            // `Character`, et en Swift `\r\n` en est **un seul**. Sur un dump
            // en CRLF, aucun `Character` n'est jamais égal à `"\n"` — le
            // premier `//` du fichier (il y en a un dès la 5e ligne) emportait
            // donc tout jusqu'à la fin, et `decode` rendait `nil` : zéro
            // verdict, zéro identifiant Nexus, en silence. Vérifié en
            // convertissant le dump réel (919 Ko, 4 720 entrées, **0 CR
            // aujourd'hui**) en CRLF : décodage refusé. Le piège est le même
            // que celui qui avait coupé 1 474 `i18n` du parc.
            if i + 1 < n, c == "/", chars[i + 1] == "/" {
                while i < n, !chars[i].isNewline { i += 1 }
                continue
            }
            if c == "\"" { inString = true }
            out.append(c)
            i += 1
        }
        return out
    }

    /// Décode une entrée. Les champs inconnus (`name`, `author`, `github`,
    /// `abandonedReason`, `warnings`, `source`, …) sont ignorés — on ne les a
    /// pas déclarés sur `Entry`, `JSONSerialization` ne s'en plaint pas.
    private static func decodeEntry(_ dict: [String: Any]) -> Entry? {
        guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
        return Entry(
            id: id,
            status: dict["status"] as? String,
            brokeIn: dict["brokeIn"] as? String,
            summary: dict["summary"] as? String,
            // `nexus` est un entier positif, `null` quand le mod n'a pas de page
            // Nexus. Le `as? Int` accepte aussi un nombre négatif ou nul — on
            // le filtre au site d'usage (`PathoschildNexusIndex.resolveNexusID`)
            // pour n'avoir qu'une règle de validation, pas plusieurs.
            nexusID: dict["nexus"] as? Int,
            unofficialUpdate: decodeUnofficialUpdate(dict["unofficialUpdate"]),
            warnings: (dict["warnings"] as? [Any])?.compactMap { normalized($0 as? String) } ?? []
        )
    }

    /// Une chaîne débarrassée de ses blancs, ou `nil` si elle n'en portait
    /// que. Écrite ici plutôt qu'empruntée : le `trimmed`/`nonEmpty` de
    /// `ModCompatibility.swift` est `private` à son fichier, et une seconde
    /// copie d'extension sur `String` finirait par diverger de la première.
    private static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Décode `{ "version": …, "url": … }`. Les deux champs sont exigés :
    /// une version sans lien n'a pas de destination, un lien sans version n'a
    /// pas de libellé — et c'est le numéro de version qui dit ce qu'il faut
    /// installer. Zéro entrée amputée sur le dump réel ; la garde est là pour
    /// le jour où il en portera une.
    private static func decodeUnofficialUpdate(_ raw: Any?) -> Entry.UnofficialUpdate? {
        guard let dict = raw as? [String: Any],
              let version = normalized(dict["version"] as? String),
              let url = normalized(dict["url"] as? String) else { return nil }
        return Entry.UnofficialUpdate(version: version, url: url)
    }
}