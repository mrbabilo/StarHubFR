import CryptoKit
import Foundation

/// A1-T11 — la forme sous laquelle deux chemins de fichier de mod se
/// comparent, d'où qu'ils viennent : le disque, une archive, un manifeste
/// Nexus, le journal local.
public enum ModFilePath {
    /// `\` ramené à `/`, sans `/` de bord, en minuscules.
    ///
    /// Minuscules : le système de fichiers de macOS ignore la casse, donc
    /// `Assets/x.png` et `assets/x.png` sont le même fichier — un auteur qui
    /// renomme le dossier ne doit pas créer de fantômes. Pas de normalisation
    /// Unicode : Swift compare et hache les `String` par équivalence
    /// canonique, un nom décomposé (NFD) d'archive vaut déjà le nom composé
    /// du disque (vérifié par sabotage, `FingerprintTests`).
    public static func key(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    /// Un fichier de traduction autre que la langue de l'auteur :
    /// `i18n/fr.json`, `Sub/i18n/zh.json` — jamais `default.json` ni
    /// `en.json`, que l'auteur écrit (C2-T4). Prend une clé (`key(_:)`).
    public static func isTranslation(_ key: String) -> Bool {
        let parts = key.split(separator: "/")
        guard parts.count >= 2, parts[parts.count - 2] == "i18n",
              let name = parts.last, name.hasSuffix(".json") else { return false }
        return name != "default.json" && name != "en.json"
    }

    /// Du code : une retouche n'y est jamais gardée (règle 5), l'ancien code
    /// avec les nouveaux assets serait pire que la perte de la retouche.
    public static func isCode(_ key: String) -> Bool {
        [".dll", ".pdb", ".exe", ".dylib", ".so"].contains { key.hasSuffix($0) }
    }

    public static func lastComponent(_ key: String) -> String {
        key.split(separator: "/").last.map(String.init) ?? key
    }
}

/// Les empreintes d'un dossier de mod ou d'une archive extraite.
public enum ModFolderHasher {
    public struct Listing: Codable, Equatable, Sendable {
        /// Chemin relatif **tel que sur le disque** → SHA-256 en hexadécimal
        /// minuscule.
        public let hashes: [String: String]
        public let sizes: [String: Int64]
        /// Fichiers qu'on n'a pas pu lire : ni empreinte, ni décision de
        /// retrait possible (on garde, règle « sans certitude »).
        public let unreadable: [String]

        public init(hashes: [String: String], sizes: [String: Int64] = [:], unreadable: [String] = []) {
            self.hashes = hashes
            self.sizes = sizes
            self.unreadable = unreadable
        }

        /// Clé normalisée → empreinte, ce que le tri compare.
        public var byKey: [String: String] {
            var out: [String: String] = [:]
            for (path, sha) in hashes { out[ModFilePath.key(path)] = sha }
            return out
        }
    }

    /// Tous les fichiers ordinaires sous `folder`, résidus du système exclus
    /// (`OSJunk`, sur chaque composant du chemin).
    public static func listing(of folder: URL, using fm: FileManager = .default) -> Listing {
        var hashes: [String: String] = [:]
        var sizes: [String: Int64] = [:]
        var unreadable: [String] = []
        for relative in PreservedModData.relativeFiles(under: folder, using: fm) {
            let components = relative.split(separator: "/")
            if components.contains(where: { OSJunk.isJunk(String($0)) }) { continue }
            let url = folder.appendingPathComponent(relative)
            do {
                hashes[relative] = try sha256(of: url)
                let attributes = try fm.attributesOfItem(atPath: url.path)
                sizes[relative] = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            } catch {
                unreadable.append(relative)
            }
        }
        return Listing(hashes: hashes, sizes: sizes, unreadable: unreadable.sorted())
    }

    /// SHA-256 d'un fichier, lu par blocs de 1 Mio : SVE pèse 129 Mo.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            // Lecture terminée : une fermeture ratée ne change pas l'empreinte.
            do { try handle.close() } catch {}
        }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
