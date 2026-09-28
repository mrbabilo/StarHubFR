import Foundation
import CryptoKit

/// X116 — la liste noire croisée au **disque**, là où l'identifiant ne suffit
/// pas : l'empreinte du DLL d'entrée (un reupload piégé porte l'`Id` du mod
/// légitime) et les fichiers piégés rangés dans un mod. Mêmes règles que
/// SMAPI (`ModBlacklist.CheckMod` / `CheckLooseFile`) : chaque champ présent
/// d'une entrée doit correspondre.
///
/// Lit des fichiers : jamais sur le fil principal.
public enum SmapiBlacklistScan {
    /// Un dossier qui porte un `manifest.json` lisible avec un `UniqueID`.
    public struct Target: Equatable, Sendable {
        public let uniqueId: String
        public let folder: URL
        /// `EntryDll` du manifeste ; `nil` pour un pack de contenu.
        public let entryDll: String?
    }

    public struct Report: Equatable, Sendable {
        /// Par `UniqueID` du mod qui porte le DLL ou le fichier piégé.
        public let matches: [String: SmapiBlacklist.Entry]
        /// Entrées de fichier reconnues par la **seule** empreinte : SMAPI
        /// hache chaque fichier de chaque mod pour elles, pas nous (le parc
        /// pèse des Go). Comptées pour être dites, jamais ignorées en silence.
        public let uncheckedHashOnlyFiles: Int
    }

    /// Le point d'entrée du ViewModel : identifiants (`SmapiBlacklist.matches`)
    /// et disque fusionnés, et la ligne de journal qui dit le résultat.
    ///
    /// X118 — `registryDirectory` porte le registre des mods déjà vérifiés
    /// propres (`Registry`) : seuls les mods changés depuis se relisent.
    /// `checked` : combien de mods ont été relus ce passage.
    public static func run(dump: SmapiBlacklist.Dump, uniqueIds: [String], modsRoot: URL,
                           registryDirectory: URL? = nil, now: Date = Date())
        -> (matches: [String: SmapiBlacklist.Entry], summary: String, checked: Int) {
        let all = targets(modsRoot: modsRoot)
        let fingerprint = Registry.fingerprint(of: dump)
        let previous = registryDirectory.flatMap(Registry.load(from:))
        let full = previous.map { $0.listFingerprint != fingerprint
                                  || now.timeIntervalSince($0.fullScanAt) > Registry.fullScanInterval } ?? true
        // Un dossier dont l'empreinte ne se lit pas n'a pas d'entrée : il se
        // relit toujours, jamais « propre » sans preuve.
        let stamps = Dictionary(all.compactMap { target in Registry.stamp(of: target).map { (target.folder.path, $0) } },
                                uniquingKeysWith: { first, _ in first })
        let toCheck = full ? all : all.filter { target in
            guard let stamp = stamps[target.folder.path] else { return true }
            return previous?.cleanStamps[target.folder.path] != stamp
        }
        let report = scan(toCheck, dump: dump)
        if let registryDirectory {
            // Propres : vérifiés ce passage sans correspondance, ou inchangés
            // depuis leur dernière vérification. Un mod signalé n'y entre
            // jamais — il se relit à chaque passage.
            var clean = full ? [:] : (previous?.cleanStamps ?? [:]).filter { stamps[$0.key] == $0.value }
            for target in toCheck where report.matches[target.uniqueId] == nil {
                if let stamp = stamps[target.folder.path] { clean[target.folder.path] = stamp }
            }
            Registry(listFingerprint: fingerprint,
                     fullScanAt: full ? now : previous?.fullScanAt ?? now,
                     cleanStamps: clean).save(to: registryDirectory)
        }
        let matches = SmapiBlacklist.matches(uniqueIds: uniqueIds, in: dump)
            .merging(report.matches) { byId, _ in byId }
        var summary = matches.isEmpty
            ? "Liste noire SMAPI : aucun mod malveillant sur \(uniqueIds.count) identifiants installés"
            : "Liste noire SMAPI : \(matches.count) mod(s) malveillant(s) installé(s) — "
                + matches.keys.sorted().joined(separator: ", ")
        if report.uncheckedHashOnlyFiles > 0 {
            summary += " ; \(report.uncheckedHashOnlyFiles) fichier(s) surveillé(s) par empreinte seule, "
                + "non vérifiés (SMAPI les vérifie au lancement)"
        }
        summary += " — \(toCheck.count) mod(s) relu(s) sur \(all.count)"
        return (matches, summary, toCheck.count)
    }

    /// X118 — les mods déjà vérifiés propres contre **cette** liste, par
    /// dossier, avec l'empreinte de ce qui compte : taille et date du
    /// manifeste, du DLL d'entrée et du dossier. Une mise à jour touche au
    /// moins le manifeste ou le DLL ; un fichier ajouté plus bas dans
    /// l'arborescence ne change aucun des trois, d'où la relecture complète
    /// toutes les 24 h. Une liste neuve relit tout : une entrée neuve peut
    /// viser un mod déjà « propre ».
    ///
    /// Un cache de nos propres octets : illisible, il vaut absent (relecture
    /// complète) et s'écrase sans perte.
    struct Registry: Codable, Equatable {
        static let fileName = "smapi-blacklist-scan.json"
        static let fullScanInterval: TimeInterval = 24 * 3600

        let listFingerprint: String
        let fullScanAt: Date
        let cleanStamps: [String: String]

        /// Seuls les champs qui jugent : un message reformulé ne change aucun
        /// verdict.
        static func fingerprint(of dump: SmapiBlacklist.Dump) -> String {
            let entries = dump.entries.map { "E|\($0.id ?? "")|\($0.entryDllHash ?? "")".lowercased() }
            let files = dump.looseFiles.map {
                "F|\($0.name ?? "")|\($0.extension ?? "")|\($0.hash ?? "")".lowercased()
            }
            let joined = (entries + files).sorted().joined(separator: "\n")
            return Insecure.MD5.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        /// `nil` quand le dossier ne se lit pas : jamais « propre » sans preuve.
        static func stamp(of target: Target) -> String? {
            let fm = FileManager.default
            var paths = [target.folder, target.folder.appendingPathComponent("manifest.json")]
            if let dll = target.entryDll { paths.append(target.folder.appendingPathComponent(dll)) }
            var parts: [String] = []
            for url in paths {
                do {
                    let attributes = try fm.attributesOfItem(atPath: url.path)
                    let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
                    let date = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
                    parts.append("\(size):\(date)")
                } catch {
                    return nil
                }
            }
            return parts.joined(separator: "|")
        }

        static func load(from directory: URL) -> Registry? {
            guard let data = FileManager.default.contents(
                atPath: directory.appendingPathComponent(fileName).path) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            do { return try decoder.decode(Registry.self, from: data) } catch { return nil }
        }

        func save(to directory: URL) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try encoder.encode(self).write(to: directory.appendingPathComponent(Self.fileName),
                                               options: .atomic)
            } catch {
                // Registre non écrit : le prochain passage relira tout.
            }
        }
    }

    /// Les mods du dossier, trouvés comme SMAPI les trouve : un dossier qui
    /// porte un manifeste est un mod, un dossier sans manifeste (un pack) se
    /// parcourt. Les mods en pause (préfixe point) comptent : ils restent
    /// installés. `__MACOSX` est un reste d'archive, jamais un mod.
    public static func targets(modsRoot: URL, maxDepth: Int = 5) -> [Target] {
        var out: [Target] = []
        let fm = FileManager.default
        func visit(_ folder: URL, depth: Int) {
            guard depth <= maxDepth else { return }
            let children: [URL]
            do {
                children = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            } catch {
                return   // dossier illisible : rien à y croiser, comme SMAPI
            }
            for child in children where child.lastPathComponent != "__MACOSX" {
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: child.path, isDirectory: &isDirectory), isDirectory.boolValue
                else { continue }
                let manifest = child.appendingPathComponent("manifest.json")
                if fm.fileExists(atPath: manifest.path) {
                    if let data = fm.contents(atPath: manifest.path),
                       let raw = String(data: data, encoding: .utf8),
                       let json = ManifestJSON.decode(raw),
                       let id = (json["UniqueID"] as? String)?.trimmingCharacters(in: .whitespaces),
                       !id.isEmpty {
                        out.append(Target(uniqueId: id, folder: child, entryDll: json["EntryDll"] as? String))
                    }
                } else {
                    visit(child, depth: depth + 1)
                }
            }
        }
        visit(modsRoot, depth: 0)
        return out
    }

    public static func scan(_ targets: [Target], dump: SmapiBlacklist.Dump,
                            md5: (URL) -> String? = SmapiBlacklistScan.md5(of:)) -> Report {
        var matches: [String: SmapiBlacklist.Entry] = [:]

        // DLL d'entrée : haché une fois par mod, et seulement si une entrée
        // à empreinte peut le viser (son `Id`, s'il en a un, est le sien).
        let hashed = dump.entries.filter { $0.entryDllHash != nil }
        for target in targets {
            guard let dll = target.entryDll else { continue }
            let candidates = hashed.filter { $0.id.map { $0.lowercased() == target.uniqueId.lowercased() } ?? true }
            guard !candidates.isEmpty,
                  let digest = md5(target.folder.appendingPathComponent(dll))?.lowercased(),
                  let hit = candidates.first(where: { $0.entryDllHash?.lowercased() == digest })
            else { continue }
            matches[target.uniqueId] = hit
        }

        // Fichiers : le nom ou l'extension trient, l'empreinte tranche.
        let screened = dump.looseFiles.filter { $0.name != nil || $0.extension != nil }
        if !screened.isEmpty {
            for target in targets where matches[target.uniqueId] == nil {
                if let hit = looseHit(in: target.folder, entries: screened, md5: md5) {
                    matches[target.uniqueId] = SmapiBlacklist.Entry(id: target.uniqueId, message: hit.message)
                }
            }
        }
        return Report(matches: matches,
                      uncheckedHashOnlyFiles: dump.looseFiles.count - screened.count)
    }

    public static func md5(of url: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func looseHit(in folder: URL, entries: [SmapiBlacklist.LooseFile],
                                 md5: (URL) -> String?) -> SmapiBlacklist.LooseFile? {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        else { return nil }
        for case let file as URL in files {
            let name = file.lastPathComponent
            for entry in entries where entry.screens(fileName: name) {
                guard let hash = entry.hash else { return entry }
                if md5(file)?.lowercased() == hash.lowercased() { return entry }
            }
        }
        return nil
    }
}
