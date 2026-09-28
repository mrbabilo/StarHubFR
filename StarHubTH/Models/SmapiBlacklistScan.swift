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
    public static func run(dump: SmapiBlacklist.Dump, uniqueIds: [String], modsRoot: URL)
        -> (matches: [String: SmapiBlacklist.Entry], summary: String) {
        let report = scan(targets(modsRoot: modsRoot), dump: dump)
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
        return (matches, summary)
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
