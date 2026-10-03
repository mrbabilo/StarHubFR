import Foundation
import Testing
@testable import StarHubTHCore

/// Le même mod sous un nouvel `UniqueID` (2026-10-03, Wallet Tools :
/// `ThaleTheGreat.WalletTools` 3.3.1 → `ThaleMagnus.WalletTools` 3.3.2).
/// La décision du 2026-09-13 tient : un choix dans l'aperçu, jamais
/// d'écrasement sans lui — seuls le message et la présélection changent.
@Suite struct AuthorRenamedModTests {

    private func manifest(_ uid: String, nexus: String) -> ModManifest {
        let raw: [String: Any] = ["Name": "(TM) Wallet Tools", "Author": "Thale", "Version": "3.3.2",
                                  "UniqueID": uid, "UpdateKeys": ["Nexus:\(nexus)"]]
        return ModManifest(dict: raw)!
    }

    private func occupant(_ uid: String, nexus: String) -> ModItem {
        ModItem(uniqueId: uid, name: "(TTG) Wallet Tools", folderName: "Wallet Tools", version: "3.3.1",
                author: "Thale", description: "", nexusUrl: "", nexusModId: nexus,
                isEnabled: true, dependencies: [], children: nil, isGroup: false)
    }

    @Test func authorPrefixChangeIsAnUpdate() throws {
        let detection = ModZipInstaller.detectConflicts(
            forFolderName: "Wallet Tools",
            manifest: manifest("ThaleMagnus.WalletTools", nexus: "47136"),
            in: [occupant("ThaleTheGreat.WalletTools", nexus: "47136")])
        let conflict = try #require(detection.conflicts.first)
        #expect(conflict.conflictType == .authorRenamedId)
        #expect(ConflictResolution.default(for: conflict.conflictType) == .overwriteWithBackup)
        #expect(conflict.resolutionOptions == [.overwriteWithBackup, .rename, .skip])
        // L'occupant devient l'existant : sauvegarde, configs gardées, état actif.
        #expect(detection.existing?.uniqueId == "ThaleTheGreat.WalletTools")
    }

    /// Les cas voisins restent « nom pris par un autre mod » : autre page
    /// Nexus, nombre de segments différent (le cas SotV du 2026-09-13,
    /// `Juanpa98ar.SotV` → `Juanpa98ar.Source.SotV`), dernier segment
    /// différent, aucune page Nexus.
    @Test func neighbourCasesStayNameTaken() {
        #expect(!AuthorRenamedMod.isSameMod(installedId: "ThaleTheGreat.WalletTools", installedNexusId: "47136",
                                            incomingId: "ThaleMagnus.WalletTools", incomingNexusId: "99999"))
        #expect(!AuthorRenamedMod.isSameMod(installedId: "Juanpa98ar.SotV", installedNexusId: "1",
                                            incomingId: "Juanpa98ar.Source.SotV", incomingNexusId: "1"))
        #expect(!AuthorRenamedMod.isSameMod(installedId: "witchtopia.SeasideSounds", installedNexusId: "",
                                            incomingId: "Liana.SeasideSounds", incomingNexusId: ""))
        #expect(!AuthorRenamedMod.isSameMod(installedId: "Thale.WalletTools", installedNexusId: "47136",
                                            incomingId: "Thale.CoinCollector", incomingNexusId: "47136"))
        #expect(!AuthorRenamedMod.isSameMod(installedId: "Thale.WalletTools", installedNexusId: "47136",
                                            incomingId: "THALE.wallettools", incomingNexusId: "47136"))
        let detection = ModZipInstaller.detectConflicts(
            forFolderName: "Wallet Tools",
            manifest: manifest("ThaleMagnus.WalletTools", nexus: "99999"),
            in: [occupant("ThaleTheGreat.WalletTools", nexus: "47136")])
        #expect(detection.conflicts.first?.conflictType == .nameTakenByOtherMod)
        #expect(detection.existing == nil)
    }
}
