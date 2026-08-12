import Testing
import Foundation
@testable import StarHubTHCore

/// La requête porte toute la subtilité du modèle : ce qu'on **affirme**
/// installé, et comment on nomme un mod dont l'auteur a oublié ses
/// `UpdateKeys`. S'y tromper, c'est soit rater une mise à jour, soit en
/// inventer une.
struct SmapiUpdateRequestTests {

    private func candidate(_ uid: String,
                           _ version: String,
                           keys: [String] = [],
                           paused: Bool = false,
                           manual: String? = nil) -> SmapiUpdateRequest.Candidate {
        .init(uniqueId: uid, manifestVersion: version, updateKeys: keys,
              isPaused: paused, manualNexusId: manual)
    }

    @Test func aModWithoutAnchorSendsItsManifestVersion() {
        let entries = SmapiUpdateRequest.entries(
            from: [candidate("a", "1.17.12", keys: ["Nexus:22256"])], anchors: [:])
        #expect(entries.count == 1)
        #expect(entries[0].installedVersion == "1.17.12")
        #expect(entries[0].updateKeys == ["Nexus:22256"])
    }

    @Test func anAnchoredModSendsTheAnchoredVersion() {
        // C'est le seul endroit où l'ancre agit — et ce qui empêche un auteur
        // distrait de produire une fausse mise à jour perpétuelle.
        let anchor = ModVersionAnchor(uniqueId: "a", anchoredVersion: "1.18.0",
                                      origin: .install, anchoredAt: Date())
        let entries = SmapiUpdateRequest.entries(
            from: [candidate("a", "1.17.12", keys: ["Nexus:22256"])],
            anchors: ["a": anchor])
        #expect(entries[0].installedVersion == "1.18.0")
    }

    @Test func aManualIdBecomesASyntheticUpdateKey() {
        // 59 mods du parc n'ont d'identifiant que celui saisi à la main.
        let entries = SmapiUpdateRequest.entries(
            from: [candidate("a", "1.0", manual: "49133")], anchors: [:])
        #expect(entries[0].updateKeys == ["Nexus:49133"])
    }

    @Test func aManualIdDoesNotOverrideAManifestNexusKey() {
        // Le manifest fait foi : c'est ce que SMAPI lit.
        let entries = SmapiUpdateRequest.entries(
            from: [candidate("a", "1.0", keys: ["Nexus:2400"], manual: "49133")],
            anchors: [:])
        #expect(entries[0].updateKeys == ["Nexus:2400"])
    }

    @Test func aManualIdIsAddedAlongsideNonNexusKeys() {
        // Un mod publié sur GitHub seulement, plus un identifiant Nexus saisi
        // à la main : les deux servent.
        let entries = SmapiUpdateRequest.entries(
            from: [candidate("a", "1.0", keys: ["GitHub:me/repo"], manual: "49133")],
            anchors: [:])
        #expect(entries[0].updateKeys == ["GitHub:me/repo", "Nexus:49133"])
    }

    @Test func duplicateUniqueIdsProduceASingleEntry() {
        // Swim Mod est installé deux fois sur le parc : en pack et à plat.
        let entries = SmapiUpdateRequest.entries(
            from: [candidate("FlyingTNT.Swim", "1.9.0", paused: true),
                   candidate("FlyingTNT.Swim", "1.9.0")],
            anchors: [:])
        #expect(entries.count == 1)
    }

    @Test func theActiveCopyWinsOverThePausedOne() {
        // Le jeu ne charge pas un dossier préfixé par un point : c'est la
        // copie active qui décrit ce qui tourne.
        let entries = SmapiUpdateRequest.entries(
            from: [candidate("a", "9.9.9", paused: true),
                   candidate("a", "1.0.0")],
            anchors: [:])
        #expect(entries[0].installedVersion == "1.0.0")
    }

    @Test func whenEveryCopyIsPausedTheHighestVersionWins() {
        // Aucune n'est chargée ; le choix ne prête pas à conséquence, mais il
        // doit être déterministe.
        let entries = SmapiUpdateRequest.entries(
            from: [candidate("a", "1.0.0", paused: true),
                   candidate("a", "2.0.0", paused: true)],
            anchors: [:])
        #expect(entries[0].installedVersion == "2.0.0")
    }

    @Test func theActiveCopyWinsEvenWhenListedFirst() {
        // Ordre inverse du test précédent : ensemble, ils écartent une
        // implémentation « le dernier écrit gagne », qui passerait l'un des deux.
        let entries = SmapiUpdateRequest.entries(
            from: [candidate("a", "1.0.0"),
                   candidate("a", "9.9.9", paused: true)],
            anchors: [:])
        #expect(entries[0].installedVersion == "1.0.0")
    }

    @Test func theHighestPausedVersionWinsEvenWhenListedFirst() {
        // Ordre inverse du test précédent : ensemble, ils écartent une
        // implémentation « le dernier écrit gagne ».
        let entries = SmapiUpdateRequest.entries(
            from: [candidate("a", "2.0.0", paused: true),
                   candidate("a", "1.0.0", paused: true)],
            anchors: [:])
        #expect(entries[0].installedVersion == "2.0.0")
    }

    @Test func duplicateCandidatesWithSameStatusAndVersionMergeUpdateKeys() {
        // Deux copies identiques en statut et version : fusion des clés.
        // Swim Mod peut être en pack et à plat avec la même version.
        let entries = SmapiUpdateRequest.entries(
            from: [candidate("a", "1.0", keys: ["Nexus:1", "GitHub:me/repo"]),
                   candidate("a", "1.0", keys: ["GitHub:me/repo", "Nexus:2"])],
            anchors: [:])
        #expect(entries.count == 1)
        // Union triée des deux listes
        #expect(entries[0].updateKeys == ["GitHub:me/repo", "Nexus:1", "Nexus:2"])
    }

    @Test func mergingUpdateKeysIsOrderIndependent() {
        // Le résultat de fusion doit être identique quel que soit l'ordre.
        let keys1 = ["Nexus:1"]
        let keys2 = ["GitHub:me/repo"]

        let entries1 = SmapiUpdateRequest.entries(
            from: [candidate("a", "1.0", keys: keys1),
                   candidate("a", "1.0", keys: keys2)],
            anchors: [:])

        let entries2 = SmapiUpdateRequest.entries(
            from: [candidate("a", "1.0", keys: keys2),
                   candidate("a", "1.0", keys: keys1)],
            anchors: [:])

        #expect(entries1[0].updateKeys == entries2[0].updateKeys)
    }

    @Test func aModWithNoIdentifierAtAllIsStillSent() {
        // smapi.io résout par UniqueID seul pour une partie du parc : c'est
        // ainsi que LovedLabels et SexyCombatIdols, sans aucune UpdateKey,
        // ressortent avec une mise à jour.
        let entries = SmapiUpdateRequest.entries(
            from: [candidate("Advize.LovedLabels", "2.1.0")], anchors: [:])
        #expect(entries.count == 1)
        #expect(entries[0].updateKeys.isEmpty)
    }

    @Test func aCandidateWithoutUniqueIdIsDropped() {
        // Sans `UniqueID`, smapi.io n'a rien à interroger.
        let entries = SmapiUpdateRequest.entries(from: [candidate("", "1.0")], anchors: [:])
        #expect(entries.isEmpty)
    }

    @Test func batchingSplitsAtTheGivenSize() {
        let entries = (0..<310).map {
            SmapiUpdateRequest.Entry(id: "m\($0)", updateKeys: [], installedVersion: "1.0")
        }
        let batches = SmapiUpdateRequest.batches(entries, size: 150)
        #expect(batches.map(\.count) == [150, 150, 10])
    }

    @Test func batchingAnEmptyListProducesNoBatch() {
        #expect(SmapiUpdateRequest.batches([], size: 150).isEmpty)
    }

    @Test func theEncodedBodyCarriesTheFieldsSmapiExpects() throws {
        let body = SmapiUpdateRequest.Body(
            mods: [.init(id: "a", updateKeys: ["Nexus:1"], installedVersion: "1.0")],
            gameVersion: "1.6.15")
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(body)) as! [String: Any]
        #expect(json["includeExtendedMetadata"] as? Bool == true)
        #expect(json["gameVersion"] as? String == "1.6.15")
        #expect(json["platform"] as? String == "Mac")
        #expect((json["mods"] as? [[String: Any]])?.count == 1)
    }
}
