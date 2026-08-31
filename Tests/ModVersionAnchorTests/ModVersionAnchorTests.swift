import Testing
import Foundation
@testable import StarHubTHCore

/// L'ancre est le seul endroit où l'app affirme une version installée. Elle
/// doit survivre à un redémarrage sans rien perdre, et rester lisible quand
/// une version antérieure de l'app l'a écrite sans ses champs récents.
struct ModVersionAnchorTests {

    @Test func anAnchorSurvivesAnEncodeDecodeRoundTrip() throws {
        let anchor = ModVersionAnchor(
            uniqueId: "selph.ExtraMachineConfig",
            anchoredVersion: "1.18.0",
            origin: .install,
            anchoredAt: Date(timeIntervalSince1970: 1_700_000_000),
            nexusFacts: NexusInstallFacts(
                modId: "22256",
                fileId: 987,
                fileUploadedAt: Date(timeIntervalSince1970: 1_699_000_000),
                pageCreatedAt: Date(timeIntervalSince1970: 1_600_000_000)))

        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(ModVersionAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    @Test func anAnchorWithoutNexusFactsDecodes() throws {
        // Cas courant : « je l'ai déjà », ou une version vue changer sur
        // disque. L'app n'a alors posé aucun fichier, donc aucun fait Nexus.
        let anchor = ModVersionAnchor(uniqueId: "Advize.LovedLabels",
                                      anchoredVersion: "2.2.0",
                                      origin: .userAffirmed,
                                      anchoredAt: Date(timeIntervalSince1970: 1),
                                      nexusFacts: nil)
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(ModVersionAnchor.self, from: data)
        #expect(decoded.nexusFacts == nil)
        #expect(decoded.origin == .userAffirmed)
    }

    @Test func aPayloadMissingPageCreatedAtStillDecodes() throws {
        // `pageCreatedAt` renseigne, ne décide pas : son absence ne doit pas
        // faire perdre l'ancre entière.
        let json = """
        {"uniqueId":"a","anchoredVersion":"1.0","origin":"install",
         "anchoredAt":0,
         "nexusFacts":{"modId":"1","fileId":2,"fileUploadedAt":0}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ModVersionAnchor.self, from: json)
        #expect(decoded.nexusFacts?.pageCreatedAt == nil)
        #expect(decoded.nexusFacts?.fileId == 2)
    }

    @Test func anUnknownOriginIsRejectedRatherThanGuessed() {
        // Une ancre dont on ne sait plus si elle vient d'un constat ou d'une
        // convention ne vaut rien : mieux vaut la perdre que la mal lire.
        let json = """
        {"uniqueId":"a","anchoredVersion":"1.0","origin":"baseline","anchoredAt":0}
        """.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ModVersionAnchor.self, from: json)
        }
    }

    // MARK: - X9 : du fichier résolu au téléchargement aux faits d'installation

    @Test func unFichierResoluAvecDateDevientDesFaits() {
        // Le downloader a choisi le MAIN le plus récent d'une page et le
        // connaît intégralement : ces faits nourriront l'ancre de
        // l'installation qui suit.
        let file = NexusModFile(fileId: 5555, categoryId: 1, categoryName: "MAIN",
                                version: "5", modVersion: nil, uploadedTimestamp: 1_787_000_000)
        let facts = NexusInstallFacts(resolvedFile: file, modId: "50802")
        #expect(facts == NexusInstallFacts(modId: "50802",
                                           fileId: 5555,
                                           fileUploadedAt: Date(timeIntervalSince1970: 1_787_000_000)))
    }

    @Test func unFichierResoluSansDateNeFaitAucunFait() {
        // Sans `uploaded_timestamp`, la règle X9 ne peut pas arbitrer
        // « plus récent que celui qu'on tient » : un fait à moitié dressé
        // ferait croire à une certitude. La sonde du 2026-08-31 n'a vu aucun
        // tel fichier sur 810 pages, mais le format ne l'exige pas.
        let file = NexusModFile(fileId: 5555, categoryId: 1, categoryName: "MAIN",
                                version: "5", modVersion: nil, uploadedTimestamp: nil)
        #expect(NexusInstallFacts(resolvedFile: file, modId: "50802") == nil)
    }
}
