import Foundation

/// La dernière capture GMCM/MCM de **chaque mod**, gardée par l'app.
///
/// La sonde réécrit `gmcm-options.json` en entier à chaque session de jeu,
/// avec les seuls mods chargés : mettre un mod en pause pour une session
/// effaçait ses libellés, ses aides et sa mise en page de l'éditeur, et ce
/// sont justement les mods en pause qu'on règle hors jeu (environ 1 000 sur
/// 1 075 dans le parc de test). L'archive absorbe chaque capture : un mod
/// absent de la nouvelle garde son entrée, un mod présent prend la nouvelle,
/// nouvelle version comprise (l'ancienne ne vaut plus : ses clés ont pu
/// bouger, et `options` vérifie de toute façon la version installée).
public struct GmcmCaptureArchive: Sendable {
    struct Entry: Codable, Sendable {
        let capturedAt: String
        let language: String?
        let mod: GmcmCapture.RawMod
    }

    private struct File: Codable {
        let version: Int
        let mods: [String: Entry]
    }

    /// Le format de ce fichier. Un fichier d'un format plus récent (écrit par
    /// une version plus récente de l'app) est lu mais jamais réécrit.
    static let formatVersion = 1

    private var mods: [String: Entry] = [:]
    private var writable = true

    public init() {}

    public var isEmpty: Bool { mods.isEmpty }

    /// Absente ou illisible : vide. Plus récente que ce format : vide aussi,
    /// et en lecture seule.
    public static func load(from url: URL) -> GmcmCaptureArchive {
        var archive = GmcmCaptureArchive()
        guard let data = FileManager.default.contents(atPath: url.path) else { return archive }
        do {
            // La version d'abord : un format futur peut ne plus se décoder,
            // et il ne s'écrase pas.
            guard try JSONDecoder().decode(VersionOnly.self, from: data).version <= formatVersion else {
                archive.writable = false
                return archive
            }
            archive.mods = try JSONDecoder().decode(File.self, from: data).mods
        } catch {
            // Illisible : on repart vide, la capture suivante la réécrit.
        }
        return archive
    }

    private struct VersionOnly: Decodable { let version: Int }

    /// Prend les mods de la capture, sauf ceux dont l'archive a une capture
    /// plus récente ou la même. Rend `true` si quelque chose a changé.
    @discardableResult
    public mutating func absorb(_ capture: GmcmCapture) -> Bool {
        var changed = false
        for (key, mod) in capture.modsById {
            if let kept = mods[key], kept.capturedAt >= capture.capturedAt { continue }
            mods[key] = Entry(capturedAt: capture.capturedAt, language: capture.language, mod: mod)
            changed = true
        }
        return changed
    }

    public func save(to url: URL) throws {
        guard writable else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(File(version: Self.formatVersion, mods: mods))
        try data.write(to: url, options: .atomic)
    }

    public func options(forMod uniqueId: String, installedVersion: String) -> GmcmModOptions? {
        mods[uniqueId.lowercased()].flatMap {
            GmcmCapture.options(of: $0.mod, language: $0.language, installedVersion: installedVersion)
        }
    }
}
