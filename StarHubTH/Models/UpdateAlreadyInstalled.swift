import Foundation

/// Une mise à jour proposée par smapi.io dont la version est **déjà sur le
/// disque**, sous un autre identifiant (constat du 2026-10-03) :
///
/// - `renamed` — l'auteur a changé l'`UniqueID` (`AuthorRenamedMod`) : la
///   nouvelle version est installée, celle-ci est l'ancienne copie
///   (Wallet Tools : `ThaleTheGreat.WalletTools` 3.3.1 annoncé, alors que
///   `ThaleMagnus.WalletTools` 3.3.2 était là, en pause) ;
/// - `supersededBy` — un module qui ne déclare **aucune** page Nexus, que
///   smapi.io rattache à celle d'un autre mod installé déjà à jour : le pack
///   l'a remplacé (`Kids for the School Tokens` 3.2.3 → page 29295, celle de
///   Kids for the School 3.2.9, qui livre désormais `ConfigTokens`).
///
/// L'écran le dit au lieu d'« Mise à jour disponible ».
public enum UpdateAlreadyInstalled: Equatable, Sendable {
    case renamed(name: String, uniqueId: String, version: String)
    case supersededBy(name: String, version: String)

    public static func explain(uniqueId: String, nexusModId: String, latestVersion: String,
                               in mods: [ModItem]) -> UpdateAlreadyInstalled? {
        guard let own = mods.mod(withUniqueId: uniqueId) else { return nil }
        let floor = latestVersion.split(separator: ".").map { Int($0) ?? 0 }
        let others = mods.flatMap(\.components).filter {
            $0.uniqueId.caseInsensitiveCompare(uniqueId) != .orderedSame
                && ProbeLoadRecords.version($0.version, atLeast: floor)
        }.sorted { ($0.name, $0.uniqueId) < ($1.name, $1.uniqueId) }
        if let renamed = others.first(where: {
            AuthorRenamedMod.isSameMod(installedId: uniqueId, installedNexusId: own.nexusModId,
                                       incomingId: $0.uniqueId, incomingNexusId: $0.nexusModId)
        }) {
            return .renamed(name: renamed.name, uniqueId: renamed.uniqueId, version: renamed.version)
        }
        let page = nexusModId.trimmingCharacters(in: .whitespaces)
        guard own.nexusModId.trimmingCharacters(in: .whitespaces).isEmpty, !page.isEmpty,
              let owner = others.first(where: { $0.nexusModId == page }) else { return nil }
        return .supersededBy(name: owner.name, version: owner.version)
    }
}
