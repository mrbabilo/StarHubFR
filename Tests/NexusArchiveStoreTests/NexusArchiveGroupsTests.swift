import Foundation
import Testing
@testable import StarHubTHCore

/// Le regroupement par mod de l'écran Entretien : l'identité est
/// `uniqueId`, casse ignorée — jamais le nom affiché.
@Suite struct NexusArchiveGroupsTests {

    private func entry(_ id: String, _ version: String, name: String, at seconds: TimeInterval,
                       size: Int64 = 100) -> NexusArchiveEntry {
        NexusArchiveEntry(uniqueId: id, version: version, modName: name, fileName: "\(name)-\(version).zip",
                          byteSize: size, timestamp: Date(timeIntervalSince1970: seconds))
    }

    @Test func versionsOfOneModShareAGroupNewestFirst() {
        let groups = NexusArchiveGroups.group([
            entry("Pathoschild.ContentPatcher", "2.9.0", name: "Content Patcher", at: 1),
            entry("palmhacker13.UltraSmooth", "2.3.6", name: "UltraSmooth", at: 2),
            entry("Pathoschild.ContentPatcher", "2.9.1", name: "Content Patcher", at: 3),
        ])
        #expect(groups.map(\.modName) == ["Content Patcher", "UltraSmooth"])
        #expect(groups[0].entries.map(\.version) == ["2.9.1", "2.9.0"])
        #expect(groups[0].totalBytes == 200)
    }

    /// Le nom change d'une version à l'autre : le groupe suit l'identifiant
    /// (casse ignorée) et prend le nom le plus récent.
    @Test func groupFollowsTheUniqueIdNotTheName() {
        let groups = NexusArchiveGroups.group([
            entry("Author.Mod", "1.0", name: "Old Name", at: 1),
            entry("author.mod", "2.0", name: "New Name", at: 2),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].modName == "New Name")
    }

    /// Le cas voisin qui ne doit PAS fusionner : deux mods au même nom
    /// affiché, identifiants distincts.
    @Test func sameNameDifferentIdsStayApart() {
        let groups = NexusArchiveGroups.group([
            entry("a.swim", "1.0", name: "Swim", at: 1),
            entry("b.swim", "1.0", name: "Swim", at: 2),
        ])
        #expect(groups.count == 2)
        #expect(Set(groups.map(\.id)).count == 2)
    }

    @Test func emptyYieldsNoGroup() {
        #expect(NexusArchiveGroups.group([]).isEmpty)
    }
}
