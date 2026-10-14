import Foundation

/// Contenu de `keybind_families.json` : les familles de touches corrigées à la
/// main, par nom de dossier logique. Un fichier d'un format plus récent refuse
/// de se relire (`FutureFormat`) : relu sans ses champs, il serait réécrit amputé.
struct KeybindFamilyFile: Codable, Equatable {
    static let currentVersion = 1

    struct FutureFormat: Error, Equatable {
        let version: Int
    }

    var families: [String: KeybindFamily] = [:]

    init(families: [String: KeybindFamily] = [:]) {
        self.families = families
    }

    private enum CodingKeys: String, CodingKey { case version, families }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version <= Self.currentVersion else { throw FutureFormat(version: version) }
        families = try c.decodeIfPresent([String: KeybindFamily].self, forKey: .families) ?? [:]
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(families, forKey: .families)
    }
}
