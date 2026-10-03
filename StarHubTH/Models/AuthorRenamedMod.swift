import Foundation

/// Le même mod sous un nouvel `UniqueID` : l'auteur a changé de préfixe.
///
/// Cas réel (2026-09-20, constaté le 2026-10-03) : Thale a renommé ses mods
/// `ThaleTheGreat.*` → `ThaleMagnus.*` (Wallet Tools 3.3.2, GMCM Advanced
/// Search, Mapster, Mine Level Indicators, Tool and Sprinkler Upgrades).
/// L'installateur voyait un **autre** mod sur le même nom de dossier, posait
/// la nouvelle version à côté, en pause, et l'ancienne restait active —
/// smapi.io continuait d'annoncer la mise à jour.
///
/// La règle, mesurée sur les 1 149 manifestes du parc : même page Nexus
/// (numérique — `Nexus:???` existe), même nombre de segments, **seul le
/// premier** (l'auteur) diffère. Le seul dernier segment prenait aussi
/// Merchant's Books (`Juanpa98ar.Source.X` / `Juanpa98ar.Code.X`) ; restent
/// les deux moitiés d'un même pack (`DLL.X` / `DD.X`), écartées par
/// `index(of:)`. Le parc : les 5 mods de Thale, rien d'autre.
public enum AuthorRenamedMod {

    public static func isSameMod(installedId: String, installedNexusId: String,
                                 incomingId: String, incomingNexusId: String) -> Bool {
        let installed = installedId.lowercased().split(separator: ".")
        let incoming = incomingId.lowercased().split(separator: ".")
        let nexus = installedNexusId.trimmingCharacters(in: .whitespaces)
        guard installed.count >= 2, installed.count == incoming.count,
              installed.first != incoming.first, installed.dropFirst() == incoming.dropFirst(),
              !nexus.isEmpty, nexus.allSatisfy(\.isASCII), nexus.allSatisfy(\.isNumber),
              nexus == incomingNexusId.trimmingCharacters(in: .whitespaces)
        else { return false }
        return true
    }

    /// Les paires du parc, par `UniqueID` plié : chaque copie apprend qu'elle
    /// est l'ancienne ou la nouvelle (la version tranche ; à égalité, rien).
    /// Deux composants d'un même pack ne s'apparient jamais.
    public static func index(of mods: [ModItem]) -> [String: ModAnomaly.Renamed] {
        let all = mods.flatMap(\.components).filter { !$0.uniqueId.isEmpty && !$0.nexusModId.isEmpty }
        let buckets = Dictionary(grouping: all) { mod in
            mod.nexusModId + "|" + mod.uniqueId.lowercased().split(separator: ".").dropFirst().joined(separator: ".")
        }
        var out: [String: ModAnomaly.Renamed] = [:]
        for bucket in buckets.values where bucket.count > 1 {
            for a in bucket {
                for b in bucket where !(pack(a) != nil && pack(a) == pack(b))
                    && isSameMod(installedId: a.uniqueId, installedNexusId: a.nexusModId,
                                 incomingId: b.uniqueId, incomingNexusId: b.nexusModId) {
                    let aNewer = ProbeLoadRecords.version(a.version, atLeast: components(b.version))
                    let bNewer = ProbeLoadRecords.version(b.version, atLeast: components(a.version))
                    guard aNewer != bNewer else { continue }
                    out[a.uniqueId.lowercased()] = aNewer
                        ? .newCopy(otherFolder: b.folderName, otherVersion: b.version)
                        : .oldCopy(otherFolder: b.folderName, otherVersion: b.version)
                }
            }
        }
        return out
    }

    /// Le pack d'un composant (`Pack/Comp` → `Pack`), `nil` hors pack.
    private static func pack(_ mod: ModItem) -> String? {
        mod.isPackComponent ? String(mod.folderName.split(separator: "/").first ?? "") : nil
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}
