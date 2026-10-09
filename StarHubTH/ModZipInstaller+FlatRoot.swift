import Foundation

/// Nom de dossier du cas `.flatRoot` — sorti de `ModZipInstaller.swift`,
/// verrouillé en taille par le cliquet des conventions (X129).
extension ModZipInstaller {

    /// X129 — nom de dossier d'une archive **sans dossier racine** (`.flatRoot`).
    /// Nexus nomme désormais ses téléchargements
    /// `<Nom> <modId> <version> <date>T<hh-mm>Z <jeton>` : garder ce nom fait
    /// porter au dossier la date et le jeton. Le `Name` du manifeste l'emporte,
    /// nettoyé des caractères interdits dans un chemin ; repli sur l'`UniqueID`,
    /// puis sur le nom d'archive (comportement d'avant, extension retirée).
    static func flatRootFolderName(manifest: ModManifest?, archiveName: String) -> String {
        for candidate in [manifest?.name, manifest?.uniqueId] {
            guard let cleaned = cleanFolderName(candidate) else { continue }
            return cleaned
        }
        return strippingArchiveExtension(from: archiveName)
    }

    /// Un nom de manifeste devient un nom de dossier sûr : séparateurs et
    /// deux-points remplacés (interdits ou fragiles sur un système de
    /// fichiers), sauts de ligne et espaces de bord enlevés. `nil` si vide.
    static func cleanFolderName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Le manifeste posé à la racine du dossier extrait, ou `nil` — sert au
    /// nom de dossier du cas `.flatRoot` (X129). Même lecteur indulgent que
    /// `installedUniqueId` : commentaires de bloc, casse des clés.
    func rootManifest(in dir: URL) -> ModManifest? {
        let manifestPath = dir.appendingPathComponent("manifest.json").path
        guard let data = FileManager.default.contents(atPath: manifestPath),
              let raw = String(data: data, encoding: .utf8),
              let json = ManifestJSON.decode(raw),
              let dict = json as? [String: Any] else { return nil }
        return ModManifest(dict: dict)
    }
}
