import Foundation

/// Une entrée de la ligne `launch` de `inventory.jsonl` : un mod chargé, sa
/// version et l'empreinte de son `config.json` (`nil` : sans réglage).
public struct ProbeInventoryEntry: Equatable, Sendable {
    public let modId: String
    public let version: String
    public let configSha: String?

    public init(modId: String, version: String, configSha: String?) {
        self.modId = modId
        self.version = version
        self.configSha = configSha
    }
}

/// Une ligne `launch` : l'inventaire du parc au démarrage d'une session.
public struct ProbeInventoryLaunch: Equatable, Sendable {
    public let session: String
    public let at: Date?
    public let probe: String?
    public let mods: [ProbeInventoryEntry]

    public var byModId: [String: ProbeInventoryEntry] {
        Dictionary(mods.map { ($0.modId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public init(session: String, at: Date?, probe: String?, mods: [ProbeInventoryEntry]) {
        self.session = session
        self.at = at
        self.probe = probe
        self.mods = mods
    }
}

/// Une ligne `configChanged` : des réglages ont changé pendant la session.
public struct ProbeInventoryChange: Equatable, Sendable {
    public let session: String
    public let at: Date?
    /// Quand les fichiers ont changé (mtime borné par la sonde) ; c'est lui
    /// qui coupe la session. Retombe sur `at` s'il manque (`ProbeSegments`).
    public let changedAt: Date?
    /// modId → nouvelle empreinte (`nil` = config supprimé).
    public let configs: [String: String?]

    public init(session: String, at: Date?, changedAt: Date?, configs: [String: String?]) {
        self.session = session
        self.at = at
        self.changedAt = changedAt
        self.configs = configs
    }
}

/// `{Id: "sha"}` : la valeur peut être `null` (config supprimé), ce que
/// `[String: String?]` de `JSONDecoder` ne décode pas tout seul. Toujours
/// décodé par un `JSONDecoder()` nu : les clés sont des identifiants de mods.
struct ProbeConfigShas: Decodable, Equatable, Sendable {
    let values: [String: String?]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        var out: [String: String?] = [:]
        for key in container.allKeys {
            out[key.stringValue] = .some(try container.decodeIfPresent(String.self, forKey: key))
        }
        values = out
    }
}

private struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private struct LaunchLine: Decodable {
    let session: String
    let at: String
    let probe: String?
    let mods: [Mod]
    struct Mod: Decodable {
        let id: String
        let version: String
        let config: String?
    }
}

/// Décodé par un `JSONDecoder()` **nu**, pas `ProbeJSON.decoder()` : la
/// stratégie « première lettre en minuscule » s'applique aussi aux clés de
/// dictionnaire, et `Configs` a pour clés des identifiants de mods
/// (`FlashShifter.StardewValleyExpandedCP` serait mutilé en
/// `flashShifter.…` — perte silencieuse du réglage changé). Les CodingKeys
/// explicites portent le PascalCase.
private struct ChangeLine: Decodable {
    let session: String
    let at: String
    let changedAt: String?
    let configs: ProbeConfigShas

    enum CodingKeys: String, CodingKey {
        case session = "Session"
        case at = "At"
        case changedAt = "ChangedAt"
        case configs = "Configs"
    }
}

public enum ProbeInventory {
    /// Une ligne illisible, ou d'un `Kind` inconnu (sonde future), est
    /// **comptée**, jamais levée (motif `ProbeJSON.lines`).
    public static func decode(_ data: Data)
        -> (launches: [ProbeInventoryLaunch], changes: [ProbeInventoryChange], unreadable: Int) {
        let decoder = ProbeJSON.decoder()
        let plain = JSONDecoder()
        var launches: [ProbeInventoryLaunch] = []
        var changes: [ProbeInventoryChange] = []
        var unreadable = 0
        for chunk in data.split(separator: UInt8(ascii: "\n")) {
            var line = Data(chunk)
            if line.last == UInt8(ascii: "\r") { line.removeLast() }
            if line.allSatisfy({ $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") }) { continue }
            // Le `Kind` décide de la forme : le lire d'abord, à la main.
            guard let kind = kind(of: line) else { unreadable += 1; continue }
            do {
                switch kind {
                case "launch":
                    let raw = try decoder.decode(LaunchLine.self, from: line)
                    launches.append(ProbeInventoryLaunch(
                        session: raw.session, at: ProbeDate.parse(raw.at), probe: raw.probe,
                        mods: raw.mods.map { ProbeInventoryEntry(modId: $0.id, version: $0.version,
                                                                 configSha: $0.config) }))
                case "configChanged":
                    let raw = try plain.decode(ChangeLine.self, from: line)
                    changes.append(ProbeInventoryChange(
                        session: raw.session, at: ProbeDate.parse(raw.at),
                        changedAt: raw.changedAt.flatMap(ProbeDate.parse),
                        configs: raw.configs.values))
                default:
                    unreadable += 1
                }
            } catch {
                unreadable += 1
            }
        }
        return (launches, changes, unreadable)
    }

    private static func kind(of line: Data) -> String? {
        guard let range = line.range(of: Data("\"Kind\":\"".utf8)),
              let end = line[range.upperBound...].firstIndex(of: UInt8(ascii: "\""))
        else { return nil }
        return String(decoding: line[range.upperBound..<end], as: UTF8.self)
    }
}
