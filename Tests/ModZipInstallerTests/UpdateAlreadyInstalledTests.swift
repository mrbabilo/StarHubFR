import Foundation
import Testing
@testable import StarHubTHCore

/// Une mise à jour proposée déjà présente sur le disque sous un autre
/// identifiant — les deux cas réels du 2026-10-03.
@Suite struct UpdateAlreadyInstalledTests {

    private func mod(_ uid: String, folder: String, version: String, nexus: String,
                     enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: uid, name: folder, folderName: folder, version: version,
                author: "A", description: "", nexusUrl: "", nexusModId: nexus,
                isEnabled: enabled, dependencies: [], children: nil, isGroup: false)
    }

    /// Wallet Tools : l'ancienne copie (ancien identifiant) est annoncée, la
    /// nouvelle est là sous `ThaleMagnus`.
    @Test func renamedCopyIsRecognised() {
        let mods = [mod("ThaleTheGreat.WalletTools", folder: "Wallet Tools old", version: "3.3.1", nexus: "47136", enabled: false),
                    mod("ThaleMagnus.WalletTools", folder: "Wallet Tools", version: "3.3.2", nexus: "47136")]
        #expect(UpdateAlreadyInstalled.explain(uniqueId: "ThaleTheGreat.WalletTools", nexusModId: "47136",
                                               latestVersion: "3.3.2", in: mods)
                == .renamed(name: "Wallet Tools", uniqueId: "ThaleMagnus.WalletTools", version: "3.3.2"))
        // Le voisin : la nouvelle copie plus ancienne que la proposition — vraie mise à jour.
        #expect(UpdateAlreadyInstalled.explain(uniqueId: "ThaleTheGreat.WalletTools", nexusModId: "47136",
                                               latestVersion: "3.4.0", in: mods) == nil)
    }

    /// Kids for the School Tokens : sans page Nexus déclarée, rattaché par
    /// smapi.io à celle du pack, qui est à jour.
    @Test func orphanModuleIsSupersededByThePackOnItsPage() {
        let mods = [mod("N3cro_92.KidsfortheSchoolTokens", folder: "Kids for the School Tokens", version: "3.2.3", nexus: ""),
                    mod("N3cro_92.KidsfortheSchool", folder: "[CP] Kids for the School", version: "3.2.9", nexus: "29295")]
        #expect(UpdateAlreadyInstalled.explain(uniqueId: "N3cro_92.KidsfortheSchoolTokens", nexusModId: "29295",
                                               latestVersion: "3.2.9", in: mods)
                == .supersededBy(name: "[CP] Kids for the School", version: "3.2.9"))
    }

    /// Les cas voisins restent de vraies mises à jour : un mod qui déclare
    /// sa propre page (même si un autre mod la partage, 58 au parc), ou
    /// personne d'autre à cette version.
    @Test func realUpdatesStayUpdates() {
        let shared = [mod("N3cro_92.KidsfortheSchool", folder: "[CP] KftS", version: "3.2.8", nexus: "29295"),
                      mod("N3cro_92.PennyandFlorSalary", folder: "[MFM] KftS", version: "3.2.9", nexus: "29295")]
        #expect(UpdateAlreadyInstalled.explain(uniqueId: "N3cro_92.KidsfortheSchool", nexusModId: "29295",
                                               latestVersion: "3.2.9", in: shared) == nil)
        let alone = [mod("Some.Mod", folder: "Some", version: "1.0.0", nexus: "")]
        #expect(UpdateAlreadyInstalled.explain(uniqueId: "Some.Mod", nexusModId: "5",
                                               latestVersion: "1.1.0", in: alone) == nil)
        #expect(UpdateAlreadyInstalled.explain(uniqueId: "Absent.Mod", nexusModId: "5",
                                               latestVersion: "1.1.0", in: alone) == nil)
    }
}
