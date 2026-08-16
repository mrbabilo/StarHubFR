import Testing
import Foundation
@testable import StarHubTHCore

/// Un mod peut porter plusieurs dossiers `i18n` — un pack en a un par
/// composant. Écrire dans le mauvais poserait la traduction d'un composant dans
/// le fichier d'un autre : elle n'y serait jamais chargée, et écraserait
/// peut-être une clé homonyme.
struct TranslationComponentResolverTests {

    private func makeMod(components: [String]) -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mod-\(UUID().uuidString)")
        for c in components {
            let dir = c.isEmpty
                ? root.appendingPathComponent("i18n")
                : root.appendingPathComponent(c).appendingPathComponent("i18n")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? "{}".write(to: dir.appendingPathComponent("default.json"),
                            atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func aSingleComponentModResolvesWithoutALabel() throws {
        let root = makeMod(components: [""])
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = try #require(TranslationComponentResolver.directory(
            forComponent: nil, inModDirectory: root))
        #expect(dir.lastPathComponent == "i18n")
    }

    @Test func eachComponentResolvesToItsOwnDirectory() throws {
        let root = makeMod(components: ["[CP] Alpha", "[CP] Beta"])
        defer { try? FileManager.default.removeItem(at: root) }
        let alphaLabel = TranslationCoverage.componentLabel(
            of: root.appendingPathComponent("[CP] Alpha").appendingPathComponent("i18n"),
            under: root)
        let dir = try #require(TranslationComponentResolver.directory(
            forComponent: alphaLabel, inModDirectory: root))
        #expect(dir.path.contains("Alpha"))
        #expect(dir.path.contains("Beta") == false)
    }

    @Test func anUnknownLabelResolvesToNothing() {
        // Retomber sur le premier dossier écrirait dans un composant au hasard :
        // mieux vaut ne rien écrire, et que l'appelant le dise.
        let root = makeMod(components: ["[CP] Alpha"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(TranslationComponentResolver.directory(
            forComponent: "[CP] Jamais vu", inModDirectory: root) == nil)
    }

    @Test func aMultiComponentModRefusesToGuessWithoutALabel() {
        // `nil` ne veut dire « le seul dossier » que s'il n'y en a qu'un. Sur un
        // pack, c'est une question sans réponse — pas une invitation à choisir.
        let root = makeMod(components: ["[CP] Alpha", "[CP] Beta"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(TranslationComponentResolver.directory(forComponent: nil,
                                                       inModDirectory: root) == nil)
    }

    @Test func aModWithoutAnyI18nResolvesToNothing() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vide-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(TranslationComponentResolver.directory(forComponent: nil,
                                                       inModDirectory: root) == nil)
    }
}
