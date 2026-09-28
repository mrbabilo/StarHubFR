import Foundation
import CryptoKit

/// A2-T7 — la liste des mods **malveillants** que SMAPI refuse de charger.
///
/// **Distincte de `mods.jsonc`**, qui porte les incompatibilités. Ici les
/// messages disent « downloads malicious code from a remote server and runs it
/// on your computer », et plusieurs entrées sont des **reuploads piégés de mods
/// légitimes** — le cas qu'un joueur ne peut pas distinguer à l'œil sur Nexus.
///
/// **Ce que ça ajoute à SMAPI.** SMAPI bloque déjà ces mods, mais **au
/// lancement du jeu**, et il l'écrit dans un journal qui n'existe qu'après.
/// StarHubFR peut le dire **au scan**, sans lancer le jeu.
///
/// **On avertit, on ne supprime jamais.** Le verdict vient d'une source
/// externe et l'`UniqueID` est **déclaratif** : un mod peut usurper celui d'un
/// autre. Supprimer d'office sur cette base détruirait un mod sain.
///
/// Mesuré le 2026-09-15 sur la ressource réelle (HTTP 200, 5 029 octets) :
/// **9 entrées `Blacklist`** et **1 `LooseFileBlacklist`**. Croisées contre les
/// 1 112 manifestes du parc de référence : **aucune correspondance**, et aucun
/// fichier `.bat` du tout.
public enum SmapiBlacklist {

    /// URL canonique, servie publiquement par smapi.io (pas d'API, pas de clé).
    public static let dumpURL = URL(string: "https://smapi.io/SMAPI.blacklist.json")!

    /// TTL du cache disque. Plus court que les 6 h de la liste de
    /// compatibilité **à dessein** : celle-ci dit qu'un mod est cassé, celle-là
    /// qu'il est piégé. Une entrée neuve doit atteindre l'utilisateur vite.
    public static let cacheTTL: TimeInterval = 60 * 60

    /// Un mod bloqué. Chaque champ présent doit correspondre, un champ absent
    /// ne filtre rien (`ModBlacklist.CheckMod` de SMAPI) : l'`Id` seul, l'`Id`
    /// **et** l'empreinte du DLL d'entrée (un reupload piégé d'un mod
    /// légitime : l'`Id` seul condamnerait le vrai), ou l'empreinte seule —
    /// formes générées par smapi.io depuis SMAPI `d6f868e` (X116).
    public struct Entry: Equatable, Sendable {
        public let id: String?
        /// MD5 du DLL d'entrée (`EntryDll` du manifeste), tel que publié.
        public let entryDllHash: String?
        /// Le message de SMAPI, en anglais dans la source. Il dit quoi faire —
        /// supprimer le mod **et** lancer une analyse antivirus — donc on le
        /// montre tel quel plutôt que de le résumer.
        public let message: String

        public init(id: String?, entryDllHash: String? = nil, message: String) {
            self.id = id
            self.entryDllHash = entryDllHash
            self.message = message
        }
    }

    /// Un fichier piégé, reconnu par son nom, son extension et/ou son
    /// empreinte : chaque champ présent doit correspondre
    /// (`ModBlacklist.CheckLooseFile` de SMAPI).
    ///
    /// La source le dit : « If any file in a folder matches an entry, the
    /// entire folder is considered malicious. » Quand l'entrée porte une
    /// empreinte, le nom seul ne condamne pas — c'est elle qui tranche.
    public struct LooseFile: Equatable, Sendable {
        public let name: String?
        /// Avec son point (`.scr`), comme `Path.GetExtension`.
        public let `extension`: String?
        /// MD5, tel que publié. Choisi par la source, pas par nous : on
        /// compare ce qu'elle donne. MD5 est cassé pour la signature, pas pour
        /// reconnaître un fichier connu.
        public let hash: String?
        public let message: String

        public init(name: String?, extension: String? = nil, hash: String?, message: String) {
            self.name = name
            self.extension = `extension`
            self.hash = hash
            self.message = message
        }

        /// Nom et extension correspondent (sans la casse) : le fichier passe
        /// la grille, reste l'empreinte s'il y en a une. `false` pour une
        /// entrée sans nom ni extension — elle ne se juge qu'en hachant tout.
        public func screens(fileName: String) -> Bool {
            guard name != nil || `extension` != nil else { return false }
            if let name, name.lowercased() != fileName.lowercased() { return false }
            if let ext = `extension` {
                let own = (fileName as NSString).pathExtension
                guard !own.isEmpty, ("." + own).lowercased() == ext.lowercased() else { return false }
            }
            return true
        }
    }

    public struct Dump: Equatable, Sendable {
        public let entries: [Entry]
        public let looseFiles: [LooseFile]

        public init(entries: [Entry], looseFiles: [LooseFile]) {
            self.entries = entries
            self.looseFiles = looseFiles
        }

        public var isEmpty: Bool { entries.isEmpty && looseFiles.isEmpty }
    }

    // MARK: - Lecture

    /// Décode le JSONC publié. `nil` quand le document est illisible —
    /// **jamais un dump vide** : « aucun mod malveillant » et « je n'ai pas su
    /// lire la liste » ne sont pas la même chose, et les confondre ferait
    /// afficher un parc sain alors qu'on ne sait rien.
    public static func decode(_ data: Data) -> Dump? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        // Le document porte des commentaires bloc **et** ligne (les dates
        // `// 2026-07` qui regroupent les vagues). Le strip est celui de la
        // liste de compatibilité — une seule implémentation, pas deux qui
        // divergeraient.
        let cleaned = PathoschildCompatibilityList.stripJSONComments(raw)
        guard let jsonData = cleaned.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return nil }

        // Un champ vide vaut absent ; une entrée sans aucun champ bloquerait
        // tout — SMAPI la refuse (`MalwareBlacklistConverter`), nous aussi.
        func field(_ dict: [String: Any], _ key: String) -> String? {
            let value = (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        let entries = (root["Blacklist"] as? [[String: Any]] ?? []).compactMap { dict -> Entry? in
            let id = field(dict, "Id"), hash = field(dict, "EntryDllHash")
            guard id != nil || hash != nil else { return nil }
            return Entry(id: id, entryDllHash: hash, message: (dict["Message"] as? String) ?? "")
        }
        let loose = (root["LooseFileBlacklist"] as? [[String: Any]] ?? []).compactMap { dict -> LooseFile? in
            let name = field(dict, "Name"), ext = field(dict, "Extension"), hash = field(dict, "Hash")
            guard name != nil || ext != nil || hash != nil else { return nil }
            return LooseFile(name: name, extension: ext, hash: hash,
                             message: (dict["Message"] as? String) ?? "")
        }
        // Un document où les deux sections manquent n'est pas un dump vide :
        // c'est une structure qu'on n'a pas reconnue.
        guard root["Blacklist"] != nil || root["LooseFileBlacklist"] != nil else { return nil }
        return Dump(entries: entries, looseFiles: loose)
    }

    // MARK: - Croisement

    /// Les mods installés qui figurent sur la liste, par `UniqueID` tel que
    /// déclaré par le manifeste.
    ///
    /// ⚠️ **La comparaison ignore la casse, et c'est délibérément différent de
    /// `PathoschildCompatibilityList.verdicts`.** Là-bas, joindre avec la casse
    /// a été mesuré sans effet sur le verdict. Ici l'enjeu n'est pas le même :
    /// SMAPI lui-même compare les identifiants de mod **sans** la casse, donc
    /// un reupload déclarant `opularenous.portablecommunitycenter` serait bloqué
    /// par le jeu tout en échappant à une comparaison stricte — l'app dirait
    /// « sain » d'un mod que SMAPI refuse. Une liste de sécurité doit être au
    /// moins aussi large que celle qu'elle relaie.
    public static func matches(uniqueIds: [String], in dump: Dump) -> [String: Entry] {
        guard !dump.entries.isEmpty else { return [:] }
        // Seules les entrées à `Id` sans empreinte se jugent sur l'`Id` : les
        // autres attendent le DLL (`SmapiBlacklistScan`).
        var byLowerId: [String: Entry] = [:]
        for entry in dump.entries where entry.entryDllHash == nil {
            if let id = entry.id { byLowerId[id.lowercased()] = entry }
        }
        var out: [String: Entry] = [:]
        for uid in uniqueIds {
            let key = uid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let entry = byLowerId[key] else { continue }
            out[uid] = entry
        }
        return out
    }

    /// Le verdict sur un fichier : chaque champ présent de l'entrée doit
    /// correspondre, l'empreinte comprise. Un fichier qui porte le nom sans le
    /// contenu est innocent, et le condamner sur son nom accuserait à tort.
    public static func looseFileVerdict(name: String, contents: Data, in dump: Dump) -> LooseFile? {
        let digest = Insecure.MD5.hash(data: contents).map { String(format: "%02x", $0) }.joined()
        return dump.looseFiles.first {
            $0.screens(fileName: name) && ($0.hash.map { $0.lowercased() == digest } ?? true)
        }
    }

    // MARK: - Cache disque

    static func cacheURL() -> URL? {
        AppSupport.directory?.appendingPathComponent("smapi-blacklist.json")
    }

    /// Le cache s'il est plus jeune que `cacheTTL`, sinon `nil`.
    public static func loadFreshCache(now: Date = Date()) -> Data? {
        guard let url = cacheURL(),
              let modified = cacheModificationDate(url: url),
              now.timeIntervalSince(modified) < cacheTTL,
              let data = try? Data(contentsOf: url) else { return nil }
        return data
    }

    private static func cacheModificationDate(url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    @discardableResult
    public static func writeCache(_ data: Data) -> Bool {
        guard let url = cacheURL() else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Le cache quel que soit son âge — filet quand le réseau est coupé.
    ///
    /// Une liste de mods piégés périmée vaut mieux que pas de liste : un mod
    /// malveillant le reste, une entrée ne s'annule pas.
    public static func cachedAnyAge() -> Data? {
        guard let url = cacheURL() else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Ce qu'il faut pour composer une ligne d'alerte, à partir du parc.
    ///
    /// Vit ici plutôt que dans le ViewModel (REFACTORING F1-T2) : c'est de la
    /// logique pure, et la construire à l'écran la rendait invérifiable.
    ///
    /// `physicalFolderName` et non `folderName` : un mod en pause vit dans un
    /// dossier préfixé d'un point, et « Montrer dans le Finder » doit désigner
    /// le dossier **réel**, pas sa forme logique.
    public static func issueInputs(
        matches: [String: Entry],
        nameByUniqueId: [String: String],
        physicalFolderByUniqueId: [String: String],
        modsRoot: String)
        -> [(uniqueId: String, name: String, folderPath: String, message: String)] {
        matches.keys.sorted().compactMap { uniqueId in
            guard let name = nameByUniqueId[uniqueId],
                  let entry = matches[uniqueId] else { return nil }
            let physical = physicalFolderByUniqueId[uniqueId] ?? ""
            let path = physical.isEmpty
                ? ""
                : (modsRoot as NSString).appendingPathComponent(physical)
            return (uniqueId: uniqueId, name: name, folderPath: path, message: entry.message)
        }
    }

    /// Tous les identifiants d'un parc, composants de pack compris.
    ///
    /// Un pack ne déclare pas d'`UniqueID` : ce sont ses enfants qui en
    /// portent. Ne regarder que le premier niveau laisserait un mod
    /// malveillant passer dès qu'il est livré à l'intérieur d'un pack.
    public static func uniqueIds(ofTopLevel ids: [String],
                                 children: [[String]]) -> [String] {
        var out: [String] = []
        for (index, id) in ids.enumerated() {
            if !id.isEmpty { out.append(id) }
            for child in children.indices.contains(index) ? children[index] : []
            where !child.isEmpty { out.append(child) }
        }
        return out
    }

    // MARK: - Réception

    public enum Failure: Error, Equatable {
        case http(Int)
        case transport(String)
        case decoding(String)
    }

    /// Ce que devient un corps de réponse HTTP 200.
    public enum PayloadOutcome: Equatable {
        /// Lisible : à servir **et** à mettre en cache.
        case fresh(Dump)
        /// Illisible, mais le cache se lit : on sert le cache et on **n'écrit
        /// rien**.
        case fallback(Dump)
        /// Ni l'un ni l'autre.
        case unreadable
    }

    /// La règle « on n'écrase le cache que par un corps qu'on sait lire ».
    ///
    /// **Reprise telle quelle de `PathoschildCompatibilityList.outcome`, et
    /// pour une raison mesurée là-bas** : le code y écrivait le cache dès le
    /// 200, avant tout décodage. Une page d'erreur, un portail captif ou un
    /// transfert tronqué rendent tous un 200 qui ne parse pas — le filet
    /// annonçait « 0 mod » **et** détruisait son cache.
    ///
    /// Ici l'enjeu est pire qu'un verdict manquant : « 0 entrée » sur une
    /// liste de mods malveillants se lit « votre parc est sain ». Un corps
    /// illisible ne doit jamais produire cette phrase.
    static func outcome(forPayload data: Data, cachedPayload: () -> Data?) -> PayloadOutcome {
        if let dump = decode(data) { return .fresh(dump) }
        if let cached = cachedPayload(), let dump = decode(cached) { return .fallback(dump) }
        return .unreadable
    }

    /// Récupère la liste (réseau, repli cache). `completion` part du fil
    /// principal ; `onEvent` non — d'où les deux `@Sendable` (P5-L5).
    public static func fetch(session: URLSession = .shared,
                             onEvent: (@Sendable (String) -> Void)? = nil,
                             completion: @escaping @Sendable (Result<Dump, Failure>) -> Void) {
        var request = URLRequest(url: dumpURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(NexusRequestBuilder.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        onEvent?("Liste noire SMAPI : récupération en cours…")
        session.dataTask(with: request) { data, response, error in
            let result: Result<Dump, Failure>
            defer { DispatchQueue.main.async { completion(result) } }

            if let error {
                // Hors ligne : le cache, même périmé, reste vrai.
                if let cached = cachedAnyAge(), let dump = decode(cached) {
                    onEvent?("Liste noire SMAPI : réseau indisponible, \(dump.entries.count) "
                             + "entrée(s) servies depuis le cache")
                    result = .success(dump)
                } else {
                    onEvent?("Liste noire SMAPI : réseau indisponible et aucun cache lisible")
                    result = .failure(.transport(error.localizedDescription))
                }
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let data else {
                if let cached = cachedAnyAge(), let dump = decode(cached) {
                    onEvent?("Liste noire SMAPI : HTTP \(code), \(dump.entries.count) "
                             + "entrée(s) servies depuis le cache")
                    result = .success(dump)
                } else {
                    onEvent?("Liste noire SMAPI : HTTP \(code), et aucun cache lisible")
                    result = .failure(.http(code))
                }
                return
            }
            switch outcome(forPayload: data, cachedPayload: cachedAnyAge) {
            case .fresh(let dump):
                writeCache(data)
                onEvent?("Liste noire SMAPI : \(dump.entries.count) entrée(s) et "
                         + "\(dump.looseFiles.count) fichier(s) surveillés, cache mis à jour")
                result = .success(dump)
            case .fallback(let dump):
                onEvent?("Liste noire SMAPI : corps illisible — cache conservé, "
                         + "\(dump.entries.count) entrée(s) servies depuis lui")
                result = .success(dump)
            case .unreadable:
                onEvent?("Liste noire SMAPI : corps illisible, et aucun cache lisible")
                result = .failure(.decoding("unreadable_payload"))
            }
        }.resume()
    }
}
