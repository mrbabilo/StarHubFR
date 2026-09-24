import Testing
@testable import StarHubTHCore

/// I-T13 — quel mod s'allume pour quelle mise à jour.
struct PendingModUpdatesTests {

    private func mod(_ id: String, folder: String? = nil, nexus: String = "",
                     children: [ModItem]? = nil) -> ModItem {
        var m = ModItem(uniqueId: id, name: folder ?? id, folderName: folder ?? id, version: "1",
                        author: "", description: "", nexusUrl: "", nexusModId: nexus,
                        isEnabled: true, dependencies: [])
        m.children = children
        return m
    }

    @Test func aSharedNexusIdLightsOnlyTheModWhoseUniqueIdMatches() {
        // Nexus:8828 couvre trois mods du parc : seul l'UniqueID décide.
        let index = PendingModUpdates(nexus: [(uniqueId: "a.one", latestVersion: "2")], smapi: [])
        #expect(index.pending(for: mod("a.one", nexus: "8828"))?.availableVersion == "2")
        #expect(index.pending(for: mod("b.two", nexus: "8828")) == nil)
    }

    @Test func aPackHeaderLightsThroughOneOfItsComponents() {
        let pack = mod("", folder: "Pack", children: [mod("p.a", folder: "Pack/A"),
                                                       mod("p.b", folder: "Pack/B")])
        let index = PendingModUpdates(nexus: [(uniqueId: "p.b", latestVersion: "3")], smapi: [])
        #expect(index.pending(for: pack)?.source == .nexus(uniqueId: "p.b"))
    }

    @Test func theUniqueIdMatchIgnoresCase() {
        // Casse différente des deux côtés : le relevé et le manifeste ne
        // s'accordent pas toujours.
        let index = PendingModUpdates(nexus: [(uniqueId: "author.mod", latestVersion: "2")], smapi: [])
        #expect(index.pending(for: mod("Author.Mod")) != nil)
    }

    @Test func nexusWinsOverTheSmapiLogForTheSameMod() {
        let index = PendingModUpdates(
            nexus: [(uniqueId: "a.one", latestVersion: "2")],
            smapi: [(folderName: "a.one", version: "1.9", url: "https://smapi.io/mods#A")])
        #expect(index.pending(for: mod("a.one"))?.source == .nexus(uniqueId: "a.one"))
    }

    @Test func aSmapiEntryLightsItsResolvedFolder() {
        let index = PendingModUpdates(
            nexus: [], smapi: [(folderName: "Wildroot", version: "1.4.1", url: "u")])
        #expect(index.pending(for: mod("w.id", folder: "Wildroot"))
                == .init(availableVersion: "1.4.1", source: .smapi(url: "u")))
        #expect(index.pending(for: mod("x.id", folder: "Other")) == nil)
    }

    @Test func anEmptyUniqueIdLightsNothing() {
        // 111 mods du parc sans identifiant : aucun ne doit hériter d'une ligne.
        let index = PendingModUpdates(nexus: [(uniqueId: "", latestVersion: "2")], smapi: [])
        #expect(index.pending(for: mod("")) == nil)
    }
}
