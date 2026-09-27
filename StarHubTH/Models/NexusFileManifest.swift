import Foundation

/// A1-T11 — le manifeste d'un fichier Nexus **au format récent** :
/// `https://mod-file-manifests.nexusmods.com/<uri>`, public, sans clé. C'est
/// le lien « Preview file contents » de la page Nexus.
///
/// Vérifié le 2026-09-27 : Wildroot Chronicles 1.4.2 (fichier 184199), 289
/// fichiers, identiques un à un à l'archive réelle (chemins et SHA-256).
/// Le format ancien (chemins seuls, sans empreinte) n'est pas lu ici : il ne
/// décide jamais d'un retrait (spec A1-T11, plan 2 pour le nettoyage).
public struct NexusFileManifest: Equatable, Sendable {
    /// SHA-256 de l'archive telle que déposée, et de sa version reconditionnée
    /// par Nexus : l'un ou l'autre identifie le fichier Nexus d'une archive
    /// qu'on a sous la main.
    public let archiveSHA256: String?
    public let repackedSHA256: String?
    /// Chemin **relatif à l'archive** (`Cropgenics/…`) → SHA-256 minuscule.
    public let files: [String: String]

    public init(archiveSHA256: String?, repackedSHA256: String?, files: [String: String]) {
        self.archiveSHA256 = archiveSHA256
        self.repackedSHA256 = repackedSHA256
        self.files = files
    }

    private struct Raw: Decodable {
        struct Hashes: Decodable {
            let SHA256: String?
        }
        struct Part: Decodable {
            let hashes: Hashes?
        }
        struct File: Decodable {
            let file_path: String
            let file_hashes: Hashes?
        }
        let archive: Part?
        let repacked: Part?
        let files: [File]
    }

    /// `nil` quand ce n'est pas un manifeste récent — une page HTML de 404,
    /// un JSON sans `files`. Un fichier sans empreinte est ignoré : il ne
    /// peut rien prouver.
    public static func decode(_ data: Data) -> NexusFileManifest? {
        do {
            let raw = try JSONDecoder().decode(Raw.self, from: data)
            var files: [String: String] = [:]
            for file in raw.files {
                guard let sha = file.file_hashes?.SHA256, !sha.isEmpty else { continue }
                files[file.file_path.replacingOccurrences(of: "\\", with: "/")] = sha.lowercased()
            }
            return NexusFileManifest(archiveSHA256: raw.archive?.hashes?.SHA256?.lowercased(),
                                     repackedSHA256: raw.repacked?.hashes?.SHA256?.lowercased(),
                                     files: files)
        } catch {
            return nil
        }
    }

    /// Les fichiers de cette archive ramenés au dossier du mod installé :
    /// parmi les dossiers de l'archive qui contiennent un `manifest.json`,
    /// celui dont les fichiers concordent le mieux (clé et empreinte) avec
    /// `installed`.
    ///
    /// `nil` sans racine à `manifest.json` (un optionnel posé par-dessus le
    /// mod, des « Translator texts » : ce n'est pas une version d'auteur,
    /// spec A1-T11), sans concordance, ou à égalité entre deux racines.
    ///
    /// - Parameter installed: clé normalisée → empreinte, du dossier installé.
    /// - Returns: clé relative à la racine retenue → empreinte.
    public func files(matching installed: [String: String]) -> [String: String]? {
        let keyed = Dictionary(files.map { (ModFilePath.key($0.key), $0.value) },
                               uniquingKeysWith: { first, _ in first })
        var roots: Set<String> = []
        for key in keyed.keys {
            if key == "manifest.json" {
                roots.insert("")
            } else if key.hasSuffix("/manifest.json") {
                roots.insert(String(key.dropLast("manifest.json".count)))
            }
        }
        var best: (score: Int, files: [String: String])?
        var tie = false
        for root in roots {
            var mapped: [String: String] = [:]
            for (key, sha) in keyed where key.hasPrefix(root) {
                mapped[String(key.dropFirst(root.count))] = sha
            }
            let score = mapped.reduce(0) { $0 + (installed[$1.key] == $1.value ? 1 : 0) }
            if score > (best?.score ?? 0) {
                best = (score, mapped)
                tie = false
            } else if score > 0, score == best?.score {
                tie = true
            }
        }
        guard let best, !tie else { return nil }
        return best.files
    }
}
