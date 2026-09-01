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
///   `summary`) en ignorant les clés `name`, `author`, `nexus`, `github`, etc. ;
/// 4. **joint** sur `UniqueID` à la liste des mods installés, en rendant
///   `ModCompatibility` (le même type que smapi.io) pour ne pas multiplier les
///   formes de verdicts côté UI.
///
/// Le résultat n'est **pas** aussi riche que smapi.io — pas de
/// `suggestedUpdate`, pas de `unofficial` séparé — mais le verdict de statut
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
    /// `abandonedReason`, `source`, `unofficialUpdate`, …) sont ignorées :
    /// on les laisse tomber côté décodeur, jamais on ne les propage.
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
            // On a un 200 et un payload : on garde le cache à jour.
            writeCache(data)
            let count = decode(data)?.count ?? 0
            onEvent?("Dump Pathoschild : \(count) mod(s) récupérés, cache mis à jour")
            DispatchQueue.main.async { completion(.success(decode(data) ?? [])) }
        }
        task.resume()
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
            guard let verdict = ModCompatibility.from(
                status: entry.status, brokeIn: entry.brokeIn, summary: entry.summary
            ) else { continue }
            out[uniqueId] = verdict
        }
        return out
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
            // Ligne // …\n — le saut de ligne est conservé.
            if i + 1 < n, c == "/", chars[i + 1] == "/" {
                while i < n, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "\"" { inString = true }
            out.append(c)
            i += 1
        }
        return out
    }

    /// Décode une entrée. Les champs inconnus (`name`, `author`, `github`,
    /// `abandonedReason`, `source`, `unofficialUpdate`, …) sont ignorés — on ne
    /// les a pas déclarés sur `Entry`, `JSONSerialization` ne s'en plaint pas.
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
            nexusID: dict["nexus"] as? Int
        )
    }
}