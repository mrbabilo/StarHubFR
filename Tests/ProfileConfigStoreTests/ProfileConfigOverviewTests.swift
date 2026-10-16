import Foundation
import Testing
@testable import StarHubTHCore

/// R4 — la liste des configs qu'un profil retient : noms lisibles, orphelins
/// repérés et rangés à la fin.
@Suite struct ProfileConfigOverviewTests {

    private func mod(_ folder: String, name: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: folder.lowercased(), name: name, folderName: folder, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [])
    }

    @Test("Un mod installé prend son nom, un orphelin garde son dossier")
    func namesAndOrphans() {
        let overview = ProfileConfigOverview(storedFolders: ["Gone", "WalletTools"],
                                             installed: [mod("WalletTools", name: "Wallet Tools")])
        #expect(overview.rows.map(\.name) == ["Wallet Tools", "Gone"])
        #expect(overview.rows.map(\.isInstalled) == [true, false])
        #expect(overview.orphans == ["Gone"])
        #expect(overview.total == 2)
    }

    @Test("Un mod en pause n'est pas un orphelin")
    func pausedModIsInstalled() {
        let overview = ProfileConfigOverview(storedFolders: ["Paused"],
                                             installed: [mod("Paused", name: "Paused Mod", enabled: false)])
        #expect(overview.orphans.isEmpty)
    }

    @Test("Installés par nom d'abord, orphelins ensuite, ordre naturel")
    func ordering() {
        let overview = ProfileConfigOverview(
            storedFolders: ["z-orphan", "B", "a-orphan", "A10", "A2"],
            installed: [mod("B", name: "beta"), mod("A10", name: "Alpha 10"), mod("A2", name: "Alpha 2")])
        #expect(overview.rows.map(\.folderName) == ["A2", "A10", "B", "a-orphan", "z-orphan"])
    }
}
