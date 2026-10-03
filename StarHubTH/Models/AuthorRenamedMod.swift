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
/// La règle, mesurée sur les 1 139 manifestes du parc : même identifiant
/// Nexus, même nombre de segments, même **dernier** segment, préfixe
/// différent. Seule, elle prend aussi les deux moitiés d'un pack (`DLL.X` /
/// `DD.X`, `….Source.X` / `….Code.X`) — mais celles-là ne se disputent jamais
/// le même dossier. Elle ne sert donc **qu'à** qualifier une collision de nom
/// de dossier (`ModZipInstaller.detectConflicts`), jamais à apparier deux mods
/// en général.
public enum AuthorRenamedMod {

    public static func isSameMod(installedId: String, installedNexusId: String,
                                 incomingId: String, incomingNexusId: String) -> Bool {
        let installed = installedId.lowercased().split(separator: ".")
        let incoming = incomingId.lowercased().split(separator: ".")
        let nexus = installedNexusId.trimmingCharacters(in: .whitespaces)
        guard installed.count >= 2, installed.count == incoming.count,
              installed != incoming, installed.last == incoming.last,
              !nexus.isEmpty, nexus == incomingNexusId.trimmingCharacters(in: .whitespaces)
        else { return false }
        return true
    }
}
