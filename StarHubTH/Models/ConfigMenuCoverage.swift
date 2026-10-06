import Foundation

/// D2-T3 §3.2 — les mods qui se déclarent configurables en jeu, depuis les
/// deux formes de journal relevées (spec §2). Couverture partielle par
/// nature : beaucoup de mods n'écrivent rien — l'UI le dit toujours.
public struct ConfigMenuEntry: Equatable, Sendable, Identifiable {
    public enum Flavor: Equatable, Sendable { case mcm, gmcm }
    public let name: String
    public let modId: String?
    public let flavor: Flavor
    /// Identité de dédoublonnage : l'ID quand la ligne le porte, le nom sinon.
    public var id: String { modId ?? name }
}

public enum ConfigMenuCoverage {

    static let mcmPrefix = "Registered config menu for "
    static let gmcmForm = "Registered with Generic Mod Config Menu."

    public static func coverage(in entries: [LogEntry]) -> [ConfigMenuEntry] {
        var seen: Set<String> = []
        var found: [ConfigMenuEntry] = []
        for entry in entries {
            guard let menu = parse(entry), seen.insert(menu.id).inserted else { continue }
            found.append(menu)
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func parse(_ entry: LogEntry) -> ConfigMenuEntry? {
        let message = entry.message
        // GMCM : le nom du mod est le crochet de source, pas le message.
        if message == gmcmForm {
            guard let name = entry.modName, !name.isEmpty else { return nil }
            return ConfigMenuEntry(name: name, modId: nil, flavor: .gmcm)
        }
        // MCM : ID dans le DERNIER groupe parenthésé final.
        guard message.hasPrefix(mcmPrefix), message.hasSuffix(").") else { return nil }
        let body = String(message.dropFirst(mcmPrefix.count).dropLast(1))
        guard let open = body.lastIndex(of: "("),
              body.index(after: open) < body.endIndex,
              body[body.index(before: body.endIndex)] == ")" else { return nil }
        let close = body.index(before: body.endIndex)
        let name = String(body[..<open]).trimmingCharacters(in: .whitespaces)
        let id = String(body[body.index(after: open)..<close])
        guard !name.isEmpty, !id.isEmpty, !id.contains("(") else { return nil }
        return ConfigMenuEntry(name: name, modId: id, flavor: .mcm)
    }
}
