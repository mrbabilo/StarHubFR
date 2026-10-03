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

    /// La règle resserrée (2026-10-03) : seul l'auteur change, page Nexus
    /// numérique — Merchant's Books (`Source`/`Code`) et `Nexus:???` restent dehors.
    @Test func onlyTheAuthorSegmentMayDiffer() {
        #expect(!AuthorRenamedMod.isSameMod(installedId: "Juanpa98ar.Source.MerchantsBooks", installedNexusId: "43034",
                                            incomingId: "Juanpa98ar.Code.MerchantsBooks", incomingNexusId: "43034"))
        #expect(!AuthorRenamedMod.isSameMod(installedId: "ceruleandeep.qf.personaleffects", installedNexusId: "???",
                                            incomingId: "other.qf.personaleffects", incomingNexusId: "???"))
    }

    private func item(_ uid: String, folder: String, version: String, nexus: String,
                      children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: uid, name: folder, folderName: folder, version: version,
                author: "A", description: "", nexusUrl: "", nexusModId: nexus, isEnabled: false,
                dependencies: [], children: children, isGroup: children != nil)
    }

    /// L'index du parc : chaque copie sait si elle est l'ancienne ou la
    /// nouvelle ; deux moitiés d'un même pack ne s'apparient pas ; à
    /// version égale, rien.
    @Test func parkIndexNamesOldAndNewCopies() {
        let mods = [item("ThaleTheGreat.Mapster", folder: "Mapster (ancien identifiant)", version: "1.7.1", nexus: "46311"),
                    item("ThaleMagnus.Mapster", folder: "Mapster", version: "1.7.2", nexus: "46311"),
                    item("", folder: "Defense Division", version: "", nexus: "", children: [
                        item("DLL.DefenseDivision", folder: "Defense Division/Code", version: "1.4.8", nexus: "12079"),
                        item("DD.DefenseDivision", folder: "Defense Division/Content", version: "1.4.9", nexus: "12079")]),
                    item("A.Same", folder: "One", version: "1.0", nexus: "7"),
                    item("B.Same", folder: "Two", version: "1.0", nexus: "7")]
        let index = AuthorRenamedMod.index(of: mods)
        #expect(index["thalethegreat.mapster"] == .oldCopy(otherFolder: "Mapster", otherVersion: "1.7.2"))
        #expect(index["thalemagnus.mapster"] == .newCopy(otherFolder: "Mapster (ancien identifiant)", otherVersion: "1.7.1"))
        #expect(index["dll.defensedivision"] == nil && index["dd.defensedivision"] == nil)
        #expect(index["a.same"] == nil)
    }

    /// Jusqu'à la puce « Identifiant changé » de l'onglet Problèmes.
    @Test func renamedCopiesBecomeAProblemKind() {
        let mods = [item("ThaleTheGreat.Mapster", folder: "Old", version: "1.7.1", nexus: "46311"),
                    item("ThaleMagnus.Mapster", folder: "New", version: "1.7.2", nexus: "46311")]
        var duplicates = ModDuplicateIndex.empty
        duplicates.renames = AuthorRenamedMod.index(of: mods)
        let anomaly = ModAnomalyReport.anomaly(for: mods[0], history: ModErrorHistory(),
                                               dependencyIssue: { _ in false }, duplicates: duplicates)
        #expect(anomaly?.severity == .warning)
        #expect(anomaly?.renamed == .oldCopy(otherFolder: "New", otherVersion: "1.7.2"))
        #expect(ModProblemKinds.of(anomaly: anomaly, hasNexusState: false) == [.renamed])
    }
}
