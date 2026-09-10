import Foundation
import Testing
@testable import StarHubTHCore

/// La résolution d'identité Nexus (REFACTORING §6, Détail de mod, tranche 2)
/// : override utilisateur > manifeste ; les en-têtes de pack héritent du
/// premier enfant qui a quelque chose — conventions identiques pour l'id,
/// le lien et l'extra, éprouvées ensemble.
@Suite struct NexusModIdentityTests {

    private func mod(_ name: String, id: String, nexusModId: String = "",
                     nexusUrl: String = "", isGroup: Bool = false,
                     children: [ModItem]? = nil, folderName: String? = nil) -> ModItem {
        ModItem(
            uniqueId: id,
            name: name,
            folderName: folderName ?? name,
            version: "1.0",
            author: "T",
            description: "",
            nexusUrl: nexusUrl,
            nexusModId: nexusModId,
            updateKeys: [],
            isEnabled: true,
            dependencies: [],
            children: children,
            isGroup: isGroup)
    }

    // MARK: - Identifiant effectif

    /// L'override utilisateur gagne sur le manifeste ; à défaut, le
    /// manifeste parle.
    @Test func customOverrideWinsOverManifest() {
        let m = mod("Cheats", id: "cjb", nexusModId: "914")
        #expect(NexusModIdentity.effectiveId(for: m, customIds: ["Cheats": "1234"]) == "1234")
        #expect(NexusModIdentity.effectiveId(for: m, customIds: [:]) == "914")
        // Un override VIDE ne masque pas le manifeste.
        #expect(NexusModIdentity.effectiveId(for: m, customIds: ["Cheats": ""]) == "914")
    }

    /// L'en-tête d'un pack sans id hérite du premier enfant qui en a un.
    @Test func packHeaderResolvesFirstChildId() {
        let noId = mod("P1", id: "p.1", folderName: "Pack/P1")
        let withId = mod("P2", id: "p.2", nexusModId: "23169", folderName: "Pack/P2")
        let pack = mod("Pack", id: "", isGroup: true, children: [noId, withId], folderName: "Pack")
        #expect(NexusModIdentity.resolvedId(for: pack, customIds: [:]) == "23169")
    }

    // MARK: - Lien

    @Test func linkPrefersIdThenManifestUrlThenChild() {
        let byId = mod("ById", id: "a", nexusModId: "914")
        #expect(NexusModIdentity.link(for: byId, customIds: [:])
                == "https://www.nexusmods.com/stardewvalley/mods/914")

        // Pas d'id mais une URL de manifeste : c'est elle la source d'origine.
        let byUrl = mod("ByUrl", id: "b", nexusUrl: "https://example.com/mod")
        #expect(NexusModIdentity.link(for: byUrl, customIds: [:]) == "https://example.com/mod")

        // Ni l'un ni l'autre, mais un enfant a un id.
        let child = mod("P1", id: "p.1", nexusModId: "777", folderName: "Pack/P1")
        let pack = mod("Pack", id: "", nexusUrl: "", isGroup: true, children: [child], folderName: "Pack")
        #expect(NexusModIdentity.link(for: pack, customIds: [:])
                == "https://www.nexusmods.com/stardewvalley/mods/777")

        // Rien du tout : vide.
        let orphan = mod("Orphan", id: "o", folderName: "Orphan")
        #expect(NexusModIdentity.link(for: orphan, customIds: [:]) == "")
    }

    // MARK: - Extra

    /// L'extra se résout comme l'id, avec la même convention d'héritage ;
    /// un extra sans résumé ET sans image ne compte pas comme des données.
    @Test func extraFallsBackToFirstChildWithRealData() {
        let child = mod("P1", id: "p.1", nexusModId: "777", folderName: "Pack/P1")
        let pack = mod("Pack", id: "", isGroup: true, children: [child], folderName: "Pack")
        let customIds: [String: String] = [:]
        let real = NexusUpdateChecker.NexusModExtra(summary: "A summary", pictureUrl: "https://img")
        let blank = NexusUpdateChecker.NexusModExtra(summary: "", pictureUrl: "")

        // L'en-tête n'a pas d'id propre → hérite de l'extra de l'enfant.
        #expect(NexusModIdentity.extra(for: pack, customIds: customIds, extras: ["777": real]) == real)

        // Un extra vide pour l'enfant ne compte pas : nil pour le pack.
        #expect(NexusModIdentity.extra(for: pack, customIds: customIds, extras: ["777": blank]) == nil)
    }
}
