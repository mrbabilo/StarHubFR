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

    /// Un mod bloqué, par son `UniqueID`.
    public struct Entry: Equatable, Sendable {
        public let id: String
        /// Le message de SMAPI, en anglais dans la source. Il dit quoi faire —
        /// supprimer le mod **et** lancer une analyse antivirus — donc on le
        /// montre tel quel plutôt que de le résumer.
        public let message: String

        public init(id: String, message: String) {
            self.id = id
            self.message = message
        }
    }

    /// Un fichier piégé, reconnu par son nom **et** son empreinte.
    ///
    /// La source le dit : « If any file in a folder matches an entry, the
    /// entire folder is considered malicious. » Le nom seul ne suffit donc pas
    /// à condamner — c'est l'empreinte qui tranche.
    public struct LooseFile: Equatable, Sendable {
        public let name: String
        /// MD5, tel que publié. Choisi par la source, pas par nous : on
        /// compare ce qu'elle donne. MD5 est cassé pour la signature, pas pour
        /// reconnaître un fichier connu.
        public let hash: String
        public let message: String

        public init(name: String, hash: String, message: String) {
            self.name = name
            self.hash = hash
            self.message = message
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

        let entries = (root["Blacklist"] as? [[String: Any]] ?? []).compactMap { dict -> Entry? in
            guard let id = (dict["Id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty else { return nil }
            return Entry(id: id, message: (dict["Message"] as? String) ?? "")
        }
        let loose = (root["LooseFileBlacklist"] as? [[String: Any]] ?? []).compactMap { dict -> LooseFile? in
            guard let name = (dict["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  let hash = (dict["Hash"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !hash.isEmpty else { return nil }
            return LooseFile(name: name, hash: hash,
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
        var byLowerId: [String: Entry] = [:]
        for entry in dump.entries { byLowerId[entry.id.lowercased()] = entry }
        var out: [String: Entry] = [:]
        for uid in uniqueIds {
            let key = uid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let entry = byLowerId[key] else { continue }
            out[uid] = entry
        }
        return out
    }

    /// Les noms de fichiers à surveiller, en minuscules.
    ///
    /// Sert de **grille de tri** avant tout calcul d'empreinte : le parc compte
    /// des centaines de milliers de fichiers, en hacher ne serait-ce qu'une
    /// fraction serait hors de question. Un seul nom est surveillé aujourd'hui
    /// (`Auto_Alchemistry.bat`), et le parc de référence n'en porte aucun — ni
    /// même un seul `.bat`.
    public static func watchedFileNames(in dump: Dump) -> Set<String> {
        Set(dump.looseFiles.map { $0.name.lowercased() })
    }

    /// Le verdict sur un fichier dont le **nom** a déjà passé la grille.
    ///
    /// Rend l'entrée seulement si l'empreinte correspond aussi : un fichier qui
    /// porte le nom sans le contenu est innocent, et le condamner sur son nom
    /// accuserait à tort.
    public static func looseFileVerdict(name: String, contents: Data, in dump: Dump) -> LooseFile? {
        let lower = name.lowercased()
        let digest = Insecure.MD5.hash(data: contents).map { String(format: "%02x", $0) }.joined()
        return dump.looseFiles.first {
            $0.name.lowercased() == lower && $0.hash.lowercased() == digest
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
}
