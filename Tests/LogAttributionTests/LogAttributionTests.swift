import Testing
import Foundation
@testable import StarHubTHCore

/// SMAPI écrit certaines erreurs pour le compte d'un mod : le crochet de source
/// porte « SMAPI », et le nom du mod n'est qu'un préfixe du message. Sans le
/// lire, ces erreurs ne sont imputées à personne.
struct LogAttributionTests {
    @Test func smapiErrorsWrittenForAModAreAttributedToIt() {
        // Ligne réelle relevée par l'utilisateur (Nexus « Gunther's Guide »).
        let msg = "Gunther's Guide: Tried to map a mod-provided API to interface "
                + "'GunthersGuide.Integrations.IGenericModConfigMenuApi', which isn't compatible."
        #expect(LogNoise.modNamePrefix(in: msg) == "Gunther's Guide")
    }

    @Test func warningsCountToo() {
        #expect(LogNoise.modNamePrefix(in: "Json Assets: something odd")
                == "Json Assets")
    }

    @Test func onlyWarningsAndErrorsAreOfferedToTheReader() {
        // Le filtrage par niveau est chez l'appelant ; la fonction, elle, ne
        // doit jamais inventer un nom à partir d'un chemin ou d'une phrase.
        #expect(LogNoise.modNamePrefix(in: "Loaded 95 items") == nil)   // pas de deux-points
    }

    @Test func pathsAndSentencesAreNotModNames() {
        #expect(LogNoise.modNamePrefix(in: "/Users/x/Mods/Foo: missing") == nil)
        #expect(LogNoise.modNamePrefix(in: "This failed. Then that: details") == nil)
        // Un préfixe trop long est une phrase, pas un nom.
        let longPrefix = String(repeating: "a", count: 61) + ": x"
        #expect(LogNoise.modNamePrefix(in: longPrefix) == nil)
    }
}
