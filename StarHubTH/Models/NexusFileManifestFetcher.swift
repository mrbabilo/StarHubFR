import Foundation

/// A1-T11 — lit, pour un mod Nexus, les manifestes de ses fichiers **au
/// format récent** : la liste par `modFiles` (GraphQL v2, sans clé), puis
/// chaque manifeste sur `mod-file-manifests.nexusmods.com`.
///
/// Les fichiers au format ancien (`uri` = nom du fichier stocké, chemins
/// seuls) ne sont demandés qu'avec `includeLegacy` — le nettoyage (A1-T11
/// plan 2). Une mise à jour ne les lit jamais : sans empreinte, ils ne
/// décident pas d'un retrait.
///
/// Appelé depuis la file de fond de l'installation : rien ici n'est
/// `@MainActor` (le mode Swift 6 arrête l'app au lancement quand une méthode
/// isolée au principal tourne au fond).
public enum NexusFileManifestFetcher {
    public struct ModFile: Decodable, Equatable, Sendable {
        public let fileId: Int
        public let version: String
        public let uri: String
        /// Date de dépôt, en secondes Unix.
        public let date: Int?

        public init(fileId: Int, version: String, uri: String, date: Int?) {
            self.fileId = fileId
            self.version = version
            self.uri = uri
            self.date = date
        }

        /// `2f/0b/09/2f0b092f-…` : format récent. L'ancien porte le nom du
        /// fichier stocké (`ItemBags 3.1.0 (PC)-5382-….zip`).
        public var isRecentFormat: Bool {
            uri.contains("/") && uri.allSatisfy { $0.isHexDigit || $0 == "/" || $0 == "-" }
        }
    }

    public struct Response: Sendable {
        public let body: Data?
        /// `nil` : pas de réponse (réseau, délai).
        public let status: Int?

        public init(body: Data?, status: Int?) {
            self.body = body
            self.status = status
        }
    }

    public typealias Transport = @Sendable (URLRequest) -> Response

    /// Un fichier Nexus au **format ancien** (chemins seuls) — lu pour le
    /// nettoyage seulement, jamais pour une mise à jour.
    public struct LegacyFile: Sendable {
        public let fileId: Int
        public let version: String
        public let manifest: NexusLegacyFileManifest
    }

    public struct Outcome: Sendable {
        public let files: [AuthorFileIndex.NexusFile]
        /// Au moins un manifeste n'a pas pu être lu (réseau, délai) : le tri
        /// garde alors ce qu'il ne peut pas expliquer, et le bilan le dit.
        public let incomplete: Bool
        /// Format ancien, du plus récent au plus ancien — vide sans
        /// `includeLegacy`.
        public var legacy: [LegacyFile] = []
    }

    /// Délai par mod, et plafond de requêtes simultanées. Les mods d'une
    /// installation passent un par un : le plafond est aussi global.
    public static let perModTimeout: TimeInterval = 20
    static let maxConcurrent = 8
    /// Un 404 sur un fichier déposé il y a moins de 30 jours n'est cru que 7
    /// jours : Nexus peut générer le manifeste après le dépôt.
    static let recentFileAge: TimeInterval = 30 * 86_400
    static let missingTrust: TimeInterval = 7 * 86_400

    public static func defaultCacheDirectory() -> URL? {
        AppSupport.directory?.appendingPathComponent("NexusFileManifests", isDirectory: true)
    }

    static func modFilesBody(modId: Int) -> Data? {
        let query = "query ModFiles($modId: ID!, $gameId: ID!) { modFiles(modId: $modId, gameId: $gameId) "
            + "{ fileId version uri date } }"
        let variables = ["modId": String(modId), "gameId": String(NexusRequestBuilder.gameId)]
        do {
            return try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        } catch {
            return nil
        }
    }

    static func decodeModFiles(_ data: Data) -> [ModFile]? {
        struct Payload: Decodable {
            struct DataField: Decodable { let modFiles: [ModFile]? }
            let data: DataField?
        }
        do {
            return try JSONDecoder().decode(Payload.self, from: data).data?.modFiles
        } catch {
            return nil
        }
    }

    static func manifestURL(uri: String) -> URL? {
        URL(string: "https://mod-file-manifests.nexusmods.com/" + uri)
    }

    /// `file-metadata.nexusmods.com/…/<modId>/<uri encodée>.json`. L'`uri`
    /// ancienne porte espaces et parenthèses (`ItemBags 3.1.0 (PC)-5382-….zip`) :
    /// tout est encodé sauf les non réservés — un nom non encodé échoue avant
    /// même la connexion (spec, « Deux formats »).
    static func legacyManifestURL(modId: Int, uri: String) -> URL? {
        guard !uri.isEmpty else { return nil }
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = uri.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        return URL(string: "https://file-metadata.nexusmods.com/file/nexus-files-s3-meta/"
                   + "\(NexusRequestBuilder.gameId)/\(modId)/\(encoded).json")
    }

    static func cacheName(uri: String) -> String {
        uri.replacingOccurrences(of: "/", with: "_")
    }

    /// Les manifestes récents du mod, du plus récent au plus ancien, dans la
    /// limite de `deadline`. Cache : un manifeste ne change jamais pour une
    /// `uri` donnée ; il n'est écrit **qu'une fois décodé** — un 200 illisible
    /// (page HTML) ne remplace rien.
    public static func fetch(modId: Int, cacheDirectory: URL?, deadline: Date,
                             now: Date = Date(),
                             transport: @escaping Transport = liveTransport,
                             includeLegacy: Bool = false) -> Outcome {
        guard now < deadline,
              let body = modFilesBody(modId: modId),
              let request = NexusRequestBuilder.makeGraphQLRequest(body: body, apiKey: nil)
        else { return Outcome(files: [], incomplete: true) }
        let listing = transport(request)
        guard listing.status == 200, let data = listing.body, let files = decodeModFiles(data) else {
            return Outcome(files: [], incomplete: true)
        }
        let recent = files.filter(\.isRecentFormat).sorted { $0.fileId > $1.fileId }
        let legacy = includeLegacy
            ? files.filter { !$0.isRecentFormat && !$0.uri.isEmpty }.sorted { $0.fileId > $1.fileId }
            : []
        let jobs = recent.map { (file: $0, isLegacy: false) } + legacy.map { (file: $0, isLegacy: true) }
        let collector = Collector()
        // L'appelant travaille lui-même : chaque itération prend le fichier
        // suivant jusqu'à épuisement, et celles qu'aucun autre thread n'a
        // prises tournent sur l'appelant. Une `OperationQueue` attendue par
        // `waitUntilAllOperationsAreFinished` gelait tout le processus de
        // test sur la CI (3 cœurs) : trois threads du pool coopératif y
        // attendaient, et aucune opération n'était jamais planifiée
        // (piles `sample` du run 36404006604, 2026-09-28).
        let next = NextIndex()
        DispatchQueue.concurrentPerform(iterations: min(maxConcurrent, jobs.count)) { _ in
            while let index = next.take(below: jobs.count) {
                let file = jobs[index].file
                if jobs[index].isLegacy {
                    switch read(cacheName: "legacy_" + cacheName(uri: file.uri),
                                url: legacyManifestURL(modId: modId, uri: file.uri),
                                fileDate: file.date, cacheDirectory: cacheDirectory,
                                deadline: deadline, now: now, transport: transport,
                                decode: NexusLegacyFileManifest.decode) {
                    case .found(let manifest):
                        collector.addLegacy(.init(fileId: file.fileId, version: file.version, manifest: manifest))
                    case .none:
                        break
                    case .failed:
                        collector.miss()
                    }
                } else {
                    switch read(cacheName: cacheName(uri: file.uri), url: manifestURL(uri: file.uri),
                                fileDate: file.date, cacheDirectory: cacheDirectory,
                                deadline: deadline, now: now, transport: transport,
                                decode: NexusFileManifest.decode) {
                    case .found(let manifest):
                        collector.add(.init(fileId: file.fileId, version: file.version, manifest: manifest))
                    case .none:
                        break
                    case .failed:
                        collector.miss()
                    }
                }
            }
        }
        let result = collector.result
        return Outcome(files: result.found.sorted { $0.fileId > $1.fileId }, incomplete: result.missed,
                       legacy: result.legacy.sorted { $0.fileId > $1.fileId })
    }

    private enum Read<Value> {
        case found(Value)
        /// Pas de manifeste chez Nexus (404) : rien à apprendre.
        case none
        /// Pas de réponse, illisible, ou délai dépassé.
        case failed
    }

    /// Un manifeste, du cache ou du réseau. Le cache n'est écrit **qu'une fois
    /// décodé** — un 200 illisible (page HTML) ne remplace rien — et un 404
    /// laisse une marque `.missing`, crue selon `trustsMissingMarker`.
    private static func read<Value>(cacheName: String, url: URL?, fileDate: Int?, cacheDirectory: URL?,
                                    deadline: Date, now: Date, transport: Transport,
                                    decode: (Data) -> Value?) -> Read<Value> {
        let fm = FileManager.default
        let cached = cacheDirectory?.appendingPathComponent(cacheName + ".json")
        let missing = cacheDirectory?.appendingPathComponent(cacheName + ".missing")
        if let cached, let data = fm.contents(atPath: cached.path), let value = decode(data) {
            return .found(value)
        }
        if let missing, trustsMissingMarker(at: missing, fileDate: fileDate, now: now) {
            return .none
        }
        let remaining = deadline.timeIntervalSince(Date())
        guard remaining > 0, let url else { return .failed }
        var request = NexusRequestBuilder.makeManifestRequest(url: url)
        request.timeoutInterval = min(remaining, perModTimeout)
        let response = transport(request)
        switch response.status {
        case 200:
            guard let data = response.body, let value = decode(data) else { return .failed }
            if let cached, let directory = cacheDirectory {
                write(data, to: cached, in: directory)
            }
            return .found(value)
        case 404:
            if let missing, let directory = cacheDirectory {
                write(Data(), to: missing, in: directory)
            }
            return .none
        default:
            return .failed
        }
    }

    static func trustsMissingMarker(at url: URL, fileDate: Int?, now: Date) -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let written = attributes[.modificationDate] as? Date else { return false }
            let uploaded = fileDate.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .distantPast
            if now.timeIntervalSince(uploaded) >= recentFileAge { return true }
            return now.timeIntervalSince(written) < missingTrust
        } catch {
            // Pas de marque : on demande.
            return false
        }
    }

    /// Un cache qu'on n'arrive pas à écrire se relira la fois suivante :
    /// jamais une raison d'arrêter l'installation.
    private static func write(_ data: Data, to url: URL, in directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    public static let liveTransport: Transport = { request in
        let box = ResponseBox()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            box.set(Response(body: error == nil ? data : nil,
                             status: error == nil ? (response as? HTTPURLResponse)?.statusCode : nil))
            done.signal()
        }.resume()
        done.wait()
        return box.value
    }

    /// L'index du prochain fichier à lire, partagé par les itérations.
    private final class NextIndex: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func take(below count: Int) -> Int? {
            lock.withLock {
                guard value < count else { return nil }
                defer { value += 1 }
                return value
            }
        }
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var found: [AuthorFileIndex.NexusFile] = []
        private var legacy: [LegacyFile] = []
        private var missed = false

        func add(_ file: AuthorFileIndex.NexusFile) { lock.withLock { found.append(file) } }
        func addLegacy(_ file: LegacyFile) { lock.withLock { legacy.append(file) } }
        func miss() { lock.withLock { missed = true } }
        var result: (found: [AuthorFileIndex.NexusFile], legacy: [LegacyFile], missed: Bool) {
            lock.withLock { (found, legacy, missed) }
        }
    }

    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = Response(body: nil, status: nil)

        func set(_ response: Response) { lock.withLock { stored = response } }
        var value: Response { lock.withLock { stored } }
    }
}
